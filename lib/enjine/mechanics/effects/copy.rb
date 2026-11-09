# frozen_string_literal: true

require_relative "../copy_except"
require_relative "../abilities/play_permissions"

module Enjine
  module Mechanics
    module Effects
      # Effects that copy something named by `of` (CR 707.1). "of": "self" is the source in any zone,
      # or, when it has left its zone (a card exiled from a graveyard to pay the cost), its card.
      module CopyOf
        def setup_of(params, errors, path)
          raw = Mechanics.fetch_param(params, :of)
          return (errors << "#{path}.of: required") && nil if raw.nil?

          Selector.build(raw, errors, "#{path}.of", targets_count: @targets_count, results_count: @results_count)
        end

        def of_refs(engine, ctx)
          return [] unless @of
          return @of.resolve(engine, ctx) unless @of.kind == :self

          [ctx.source].compact
        end

        # The copiable values [card, except] of each referenced object (CR 707.2). An object that left its
        # zone since is used as it last existed (CR 608.2h).
        def copy_values(engine, ctx)
          of_refs(engine, ctx).filter_map do |ref|
            obj = engine.state.objects[ref]
            next engine.copiable_values(obj) if obj && !obj.ability?

            lki = engine.resolving_last_known(ref)
            next [lki["card"], lki["except"] || {}] if lki&.key?("card")

            source_card(engine, ctx) if @of.kind == :self
          end
        end

        def source_card(engine, ctx)
          stacked = engine.state.objects[ctx.object]
          stacked&.ability? ? [stacked.card, {}] : nil
        end
      end

      # "Create a token that's a copy of ..." (CR 707.8, 111.1).
      class CreateTokenCopy < Effect
        include CopyOf

        primitive :effect, :create_token_copy,
                  description: "For each object `of` refers to (a permanent, a card in any zone, or the source with " \
                               "\"self\"), the referenced players (default: you) each create `amount` tokens that " \
                               "are copies of it: its copiable values (its card as modified by other copy effects, " \
                               "not counters, status or other effects), with the `except` modifications. The tokens " \
                               "are the effect's result, for later effects such as granting haste or a delayed " \
                               "sacrifice.",
                  rules: %w[707.2 707.8 707.9a 707.9b 111.1 614.1c],
                  params: { "of" => "selector (what to copy)", "amount" => "amount (default 1)", "tapped" => "boolean",
                            "except" => CopyExcept::PARAM, "to" => "selector (default \"you\")" },
                  example: { "create_token_copy" => { "of" => { "target" => 0 }, "except" => { "legendary" => false } } }

        def self.keys = %w[of amount tapped except to if]
        def self.default_to = "you"

        def initialize(to:, params:, errors:, path:, targets_count: 0, results_count: 0)
          params = params.transform_keys(&:to_s)
          params["amount"] = 1 unless params.key?("amount")
          super
        end

        def setup(params, errors, path)
          @of = setup_of(params, errors, path)
          @tapped = Mechanics.flag_param(params, :tapped, errors, path)
          @except = CopyExcept.build(Mechanics.fetch_param(params, :except), errors, "#{path}.except")
        end

        def to_s
          "create #{amount} token cop#{amount == 1 ? "y" : "ies"} of #{@of}#{" tapped" if @tapped}" \
            "#{CopyExcept.to_s(@except)} → #{to}"
        end

        def apply(engine, ctx)
          n = amount_for(engine, ctx)
          values = copy_values(engine, ctx)
          players(engine, ctx).each do |index|
            values.each do |card, except|
              merged = [card, Engine::Copies.merge_except(except, @except)]
              n.times { engine.create_token_copy!(merged, index, tapped: @tapped) }
            end
          end
        end
      end

      # "... becomes a copy of ..." (CR 707.4, 613.2a), for a duration.
      class BecomeCopy < Effect
        include CopyOf

        DURATIONS = %w[end_of_turn permanent].freeze

        primitive :effect, :become_copy,
                  description: "Each referenced permanent becomes a copy of the (first) object `of` refers to, with the " \
                               "`except` modifications, until end of turn (default) or for as long as it stays on the " \
                               "battlefield (`duration: \"permanent\"`). It keeps its counters, status and other " \
                               "effects; nothing enters or leaves, so no enter or leave abilities trigger. Several copy " \
                               "effects apply in timestamp order.",
                  rules: %w[707.2 707.4 613.2a 613.7 611.2a 514.2],
                  params: { "to" => "selector (the permanents that become copies)", "of" => "selector (what they copy)",
                            "except" => CopyExcept::PARAM, "duration" => DURATIONS.join(" | ") },
                  example: { "become_copy" => { "to" => "self", "of" => { "target" => 0 } } }

        def self.keys = %w[of except duration to if]

        def setup(params, errors, path)
          @of = setup_of(params, errors, path)
          @except = CopyExcept.build(Mechanics.fetch_param(params, :except), errors, "#{path}.except")
          @duration = Mechanics.fetch_param(params, :duration) || "end_of_turn"
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
        end

        def to_s = "becomes a copy of #{@of}#{CopyExcept.to_s(@except)} (#{@duration.tr("_", " ")}) → #{to}"

        def apply(engine, ctx)
          first = copy_values(engine, ctx).first or return
          values = [first[0], Engine::Copies.merge_except(first[1], @except)]
          objects(engine, ctx).each { engine.become_copy!(engine.object(it), values, duration: @duration) }
        end
      end

      # "Copy [spell]" / "copy target activated or triggered ability" (CR 707.10): the copy goes on the stack
      # with the same choices; it isn't cast or activated.
      class CopySpell < ChoiceEffect
        include CopyOf

        primitive :effect, :copy_spell,
                  description: "Copy each spell or ability on the stack `of` refers to (\"self\": the spell this ability " \
                               "or spell belongs to; a `stack_ability` target: an activated or triggered ability) " \
                               "`amount` times. The copies are put on the stack under the referenced player's " \
                               "control (default: you) with the same modes, X, kicker and targets; they aren't cast " \
                               "or activated, and an ability's copy has the same source. With `new_targets: true` " \
                               "the controller may choose new targets for each copy. A copy of a permanent spell " \
                               "becomes a token as it resolves.",
                  rules: %w[707.10 707.10a 707.10b 707.10c 707.10f 608.3f],
                  params: { "of" => "selector (spells or abilities on the stack)", "amount" => "amount (default 1)",
                            "new_targets" => "boolean", "to" => "selector (default \"you\")" },
                  example: { "copy_spell" => { "of" => "self" } }

        def self.keys = %w[of amount new_targets to if]
        def self.default_to = "you"

        def initialize(to:, params:, errors:, path:, targets_count: 0, results_count: 0)
          params = params.transform_keys(&:to_s)
          params["amount"] = 1 unless params.key?("amount")
          super
        end

        def setup(params, errors, path)
          @of = setup_of(params, errors, path)
          @new_targets = Mechanics.flag_param(params, :new_targets, errors, path)
        end

        def to_s = "copy #{@of}#{" #{amount} times" if amount != 1}#{" (new targets)" if @new_targets} → #{to}"

        # Each copy is planned as [spell, controller]; with new targets, its targets are chosen one at a
        # time (keep the old one or pick a legal new one, CR 707.10c) before it's put on the stack.
        def run(engine, ctx, locals)
          return :done unless locals["plan"] || condition.nil? || condition.true?(engine, ctx)

          locals["plan"] ||= plan(engine, ctx)
          while (spell_id, controller = locals["plan"].first)
            spell = engine.state.objects[spell_id]
            if spell&.zone == :stack
              targets = @new_targets ? choose_targets(engine, spell, controller, locals) : spell.targets&.dup
              return :wait if targets == :wait

              engine.copy_spell!(spell, controller, targets)
            end
            locals["plan"].shift
            locals.delete("answers")
            locals.delete("asked")
          end
          :done
        end

        private

        def plan(engine, ctx)
          n = amount_for(engine, ctx)
          spells = of_refs(engine, ctx).select { engine.state.objects[it]&.zone == :stack }
          players(engine, ctx).flat_map { |index| spells.flat_map { |id| Array.new(n) { [id, index] } } }
        end

        def choose_targets(engine, spell, controller, locals)
          old = spell.targets || []
          specs = engine.resolving_ability(spell)&.targets_for(spell.modes || [], kicked: spell.memory.key?("kicked_with")) || []
          slots = engine.target_slots(old, specs) # each target of a counted slot in turn; same number (CR 707.10c)
          chosen = answers(locals).map { it["target"] }
          return engine.regroup_targets(chosen, old) if chosen.size >= slots.size

          i = chosen.size
          current, spec = slots[i]
          keep = [{ "type" => "target", "target" => current }]
          others = spec ? new_choices(engine, spec, controller, spell, current) : []
          ask(engine, locals, controller, "Choose target ##{i + 1} for the copy", keep + others)
        end

        def new_choices(engine, spec, controller, spell, current)
          source = spell.ability? ? spell.source : nil # an ability's copy has the same source (CR 707.10b)
          spec.candidates_for(engine, controller, source).filter_map do |ref|
            next if ref == current || ref == spell.id || !engine.targetable?(ref, controller, source, targeter: source || spell.id)

            { "type" => "target", "target" => ref }
          end
        end
      end

      # "Copy that card" / "create a copy of this card" (CR 707.12): copies of cards, in the zone the card is in.
      class CopyCard < Effect
        include CopyOf

        primitive :effect, :copy_card,
                  description: "Create `amount` copies of each card `of` refers to (\"self\": the source card), in the zone " \
                               "that card is in, owned by you. They are the effect's result, e.g. for `cast_free` or " \
                               "`cast`. A card copy ceases to exist if it is anywhere but the stack or the " \
                               "battlefield (so one that isn't cast now is gone at the next state-based-action check).",
                  rules: %w[707.12 707.12a 707.10a 704.5d],
                  params: { "of" => "selector (cards)", "amount" => "amount (default 1)" },
                  example: { "copy_card" => { "of" => { "result" => 0 }, "amount" => 2 } }

        def self.keys = %w[of amount if]
        def self.default_to = "you"

        def initialize(to:, params:, errors:, path:, targets_count: 0, results_count: 0)
          params = params.transform_keys(&:to_s)
          params["amount"] = 1 unless params.key?("amount")
          super
        end

        def setup(params, errors, path) = @of = setup_of(params, errors, path)
        def to_s = "copy #{@of}#{" #{amount} times" if amount != 1}"

        def apply(engine, ctx)
          n = amount_for(engine, ctx)
          of_refs(engine, ctx).each do |ref|
            obj = engine.state.objects[ref]
            next unless obj && !obj.ability? && obj.zone != :battlefield

            n.times { engine.create_card_copy!(engine.copiable_values(obj), ctx.controller, obj.zone) }
          end
        end
      end

      # "You may cast [it]" while the effect resolves, paying its costs (CR 608.2g, 707.12, 601.2a): like
      # cast_free, but the spell's mana cost is paid as usual.
      class Cast < CastFree
        primitive :effect, :cast,
                  description: "The controller may cast referenced cards (or card copies) now, while this resolves, " \
                               "paying their costs; timing restrictions don't apply. `to`, `for`, `not_types`, " \
                               "`max_mana_value` and `count` work as for `cast_free`.",
                  rules: %w[608.2g 707.12 707.12a 601.2a 601.2f],
                  params: { "to" => "selector", "for" => "card spec", "not_types" => "list of card types",
                            "max_mana_value" => "amount", "count" => "1 or \"any\"" },
                  example: { "cast" => { "to" => { "result" => 0 } } }

        def to_s = super.sub(" free", "")
        def via = "resolving"
        def prompt = "You may cast a spell"
        def castable_now?(engine, index, id) = engine.castable_while_resolving?(index, id)
      end

      # A card or permanent gains an ability (CR 113.6b, 611.2): "that card gains '...'". The ability lives
      # in this card's data (its reference "granted:<card>:<ref>"); it lasts while the object stays in its
      # zone, or until end of turn.
      class GrantAbility < Effect
        DURATIONS = %w[permanent end_of_turn].freeze

        primitive :effect, :grant_ability,
                  description: "Each referenced object (a permanent, or a card in any zone, e.g. an exiled card) gains " \
                               "`ability` (any ability entry) for as long as it stays in its zone (default) or until " \
                               "end of turn. `for` (a card spec) keeps only matching objects (\"that nonland card\"). " \
                               "An activated ability with `zone` works from that zone (\"activate only if this card is " \
                               "exiled\").",
                  rules: %w[113.6b 611.2a 613.1f],
                  params: { "ability" => "an ability", "to" => "selector", "for" => "card spec",
                            "duration" => DURATIONS.join(" | ") },
                  example: { "grant_ability" => { "to" => { "result" => 0 },
                                                  "ability" => { "activated" => { "cost" => [{ "mana" => "{1}" }],
                                                                                  "zone" => "exile",
                                                                                  "effects" => [{ "draw" => { "amount" => 1 } }] } } } }

        attr_reader :ref, :granted_ability

        def self.keys = %w[ability duration for to if]

        def setup(params, errors, path)
          @ref = "grant:#{path}"
          @for = CardSpec.build(Mechanics.fetch_param(params, :for), errors, "#{path}.for")
          raw = Mechanics.fetch_param(params, :ability)
          @granted_ability = if raw.nil?
                               (errors << "#{path}.ability: required") && nil
                             else
                               Mechanics.build_entry(:ability, raw, errors,
                                                     "#{path}.ability")
                             end
          @duration = Mechanics.fetch_param(params, :duration) || "permanent"
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
        end

        def nested_effects = @granted_ability.respond_to?(:effects) ? @granted_ability.effects : []
        def to_s = "gains \"#{@granted_ability}\"#{" until end of turn" if @duration == "end_of_turn"} → #{to}"

        def apply(engine, ctx)
          card = engine.state.objects[ctx.object]&.card or return
          affected = refs(engine, ctx).select { (obj = engine.state.objects[it]) && @for.match?(engine, obj) }
          engine.grant_card_ability!(ctx, affected, card, @ref, @duration) unless affected.empty?
        end
      end
    end
  end
end
