# frozen_string_literal: true

module Enjine
  module Mechanics
    # Auras and Equipment (CR 301.5, 303.4, 701.3, 702.5, 702.6). A permanent is attached to
    # another through GameObject#attached_to; "equipped/enchanted creature" abilities refer to
    # whatever the source is attached to (CR 301.5f, 303.4m). The engine side (legality,
    # attach!/unattach!, state-based actions 704.5m/n/p) is in Engine::Attachments.
    module Subtypes
      # Shared rules of the subtypes that make a permanent attachable.
      class AttachmentSubtype < Primitive
        def self.validate_definition(_defn, _errors) = nil
      end

      # Aura (CR 303.4): an enchantment that enters attached to what its spell targeted.
      class Aura < AttachmentSubtype
        primitive :subtype, :aura,
                  description: "An enchantment that is cast targeting what its `enchant` ability allows and enters " \
                               "the battlefield attached to that target. If it's attached to something it can't " \
                               "enchant, or to nothing, it's put into its owner's graveyard (a state-based action).",
                  rules: %w[303.4 303.4a 303.4c 303.4d 608.3c 704.5m],
                  example: { "types" => ["enchantment"], "subtypes" => ["aura"], "abilities" => [{ "enchant" => "creature" }] }

        def self.applies_to = [:enchantment]

        # CR 303.4a: an Aura spell requires a target, defined by its enchant ability.
        def self.validate_definition(defn, errors)
          count = defn.abilities.count { it.kind == :enchant }
          errors << "abilities: an Aura needs exactly one enchant ability (CR 303.4a, 702.5a)" unless count == 1
        end
      end

      # Equipment (CR 301.5): an artifact that can be attached to a creature, usually by equip.
      class Equipment < AttachmentSubtype
        primitive :subtype, :equipment,
                  description: "An artifact that can be attached to a creature (it enters unattached). If the " \
                               "creature it equips stops being a creature or leaves, it becomes unattached and " \
                               "stays on the battlefield (a state-based action).",
                  rules: %w[301.5 301.5b 301.5c 704.5n],
                  example: { "types" => ["artifact"], "subtypes" => ["equipment"],
                             "abilities" => [{ "equip" => { "cost" => [{ "mana" => "{2}" }] } }] }

        def self.applies_to = [:artifact]
      end
    end

    module Abilities
      # Enchant [object] (CR 702.5): what an Aura spell can target and what the Aura can enchant.
      class Enchant < Primitive
        primitive :ability, :enchant,
                  description: "The Aura's enchant ability: a target filter for what its spell targets and what the " \
                               "Aura may be attached to, e.g. \"creature\" or {\"permanent\": {\"any_of\": " \
                               "[\"artifact\", \"creature\"]}}. Only Auras have it.",
                  rules: %w[702.5a 115.1b 303.4a],
                  params: { "(value)" => "a target filter for a permanent" },
                  example: { "enchant" => "creature" }

        PLAYER_FILTERS = %w[player opponent any_target].freeze

        attr_reader :filter

        def self.scalar_params? = true

        def self.build(params, errors, path, **)
          filter = Mechanics.build_entry(:filter, params, errors, path)
          base = filter.respond_to?(:base) ? filter.base : filter
          if base && (base.zone != :battlefield || PLAYER_FILTERS.include?(base.primitive_name))
            errors << "#{path}: must be a filter for permanents (Auras that enchant players are not supported yet)"
          end
          new(filter)
        end

        def initialize(filter)
          super()
          @filter = filter
          freeze
        end

        def kind = :enchant
        def mana_ability? = false
        def allowed_types = [:enchantment]
        def try_effects = []

        def validate_definition(defn, errors, path)
          errors << "#{path}: only Auras have enchant (CR 702.5a)" unless defn.subtypes.include?(:aura)
        end

        def to_s = "Enchant #{filter.is_a?(Class) ? filter.primitive_name.tr("_", " ") : filter}"
      end

      # The spell ability an Aura spell has implicitly (CR 115.1b, 303.4a): one target chosen
      # by its enchant ability, no effects. Resolving attaches the Aura to it (CR 608.3c).
      class AuraSpell < StackAbility
        def self.for(enchant) = new(targets: [enchant.filter].freeze, effects: [].freeze)

        def kind = :aura_spell
      end

      # Equip [cost] (CR 702.6a): "[Cost]: Attach this permanent to target creature you control.
      # Activate only as a sorcery."
      class Equip < ActivatedAbility
        primitive :ability, :equip,
                  description: "Equip: pay `cost` to attach this Equipment to target creature you control (not " \
                               "itself). Sorcery speed. Only Equipment have it.",
                  rules: %w[702.6a 301.5b 301.5c 701.3a],
                  params: { "cost" => "list of costs, e.g. [{\"mana\": \"{2}\"}]" },
                  example: { "equip" => { "cost" => [{ "mana" => "{2}" }] } }

        TARGET = { "creature" => { "controller" => "you", "other" => true } }.freeze
        EFFECT = { "attach" => { "to" => { "target" => 0 } } }.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost], errors, path)
          costs = parse_costs(params, errors, path)
          errors << "#{path}.cost: must be a non-empty list" if costs.empty? && errors.none? { it.start_with?("#{path}.cost") }
          targets = [Mechanics.build_entry(:filter, TARGET, errors, path)].freeze
          effects = [Mechanics.build_entry(:effect, EFFECT, errors, path, targets_count: 1)].freeze
          new(targets: targets, effects: effects, costs: costs, sorcery: true)
        end

        def allowed_types = [:artifact]

        def validate_definition(defn, errors, path)
          errors << "#{path}: only Equipment have equip (CR 702.6a)" unless defn.subtypes.include?(:equipment)
        end

        def to_s = "Equip #{costs.join(", ")}"
      end
    end

    module Effects
      # Attach the source Aura or Equipment to a permanent (CR 701.3).
      class Attach < Effect
        primitive :effect, :attach,
                  description: "Attach this Aura or Equipment (the ability's source), or the `attachment` (e.g. a token " \
                               "an earlier effect created, {\"result\": n}), to the referenced permanent. Nothing " \
                               "happens if it can't legally be attached to it, if it's already attached to it, or if " \
                               "the attachment has left the battlefield.",
                  rules: %w[701.3a 701.3b 701.3c 301.5c],
                  params: { "to" => "selector naming one permanent: {\"target\": n}, \"self\" or {\"result\": n}",
                            "attachment" => "selector (default: the source)" },
                  example: { "attach" => { "to" => { "target" => 0 } } }

        SINGLE = %i[target self result].freeze

        def self.keys = %w[to attachment if]

        def setup(params, errors, path)
          if to && !SINGLE.include?(to.kind)
            errors << "#{path}.to: must be {\"target\": n}, \"self\" or {\"result\": n} (an attachment equips one object, CR 301.5c)"
          end
          raw = Mechanics.fetch_param(params, :attachment)
          @attachment = raw && Selector.build(raw, errors, "#{path}.attachment", targets_count: @targets_count,
                                                                                 results_count: @results_count)
        end

        def apply(engine, ctx)
          target = objects(engine, ctx).first or return
          ids = @attachment ? @attachment.resolve(engine, ctx) : [ctx.source]
          ids.each do |id|
            source = engine.state.objects[id]
            engine.attach!(source, target) if source && engine.state.battlefield.include?(id)
          end
        end

        def to_s = "attach to #{to}"
      end
    end
  end
end
