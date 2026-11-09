# frozen_string_literal: true

module Enjine
  module Mechanics
    # Which permanents a static ability of a permanent applies to, relative to its controller:
    #   {"each": filter, "controller": "you" | "opponent" | "any", "other": true}
    class Affects
      CONTROLLERS = %w[you opponent any].freeze

      attr_reader :filter, :controller, :other

      def self.build(data, errors, path)
        unless data.is_a?(Hash) && data["each"]
          errors << "#{path}: must be {\"each\": filter, \"controller\": you|opponent|any, \"other\": bool}"
          return new(nil, "any", false)
        end
        Mechanics.check_keys(data, %w[each controller other], errors, path)
        controller = data.fetch("controller", "any")
        errors << "#{path}.controller: must be one of #{CONTROLLERS.join(", ")}" unless CONTROLLERS.include?(controller)
        new(Mechanics.build_entry(:filter, data["each"], errors, "#{path}.each"), controller, data["other"] == true)
      end

      def initialize(filter, controller, other)
        @filter = filter
        @controller = controller
        @other = other
        freeze
      end

      def controller_ok?(object_controller, source)
        controller == "any" || (controller == "you") == (object_controller == source.controller)
      end

      # A permanent on the battlefield, by its current characteristics and status.
      def match?(engine, obj, source)
        return false if other && obj.id == source.id
        return false unless controller_ok?(obj.controller, source)

        filter.match_for?(engine, obj.id, source.controller, source.id)
      end

      # A permanent about to enter under `entering_controller` (CR 614.12: as it would exist there).
      def match_facts?(facts, entering_controller, source)
        !filter.nil? && controller_ok?(entering_controller, source) && filter.matches_facts?(facts)
      end

      def to_s
        name = filter.is_a?(Class) ? filter.primitive_name.tr("_", " ") : filter.to_s
        "#{"other " if other}#{name}s#{{ "you" => " you control", "opponent" => " opponents control" }[controller]}"
      end
    end

    module Abilities
      # Base for replacement effects of a permanent's static abilities (CR 614.1, 614.12): no stack.
      class StaticReplacement < Primitive
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
      end

      # "If you would draw a card, draw two cards instead." (CR 614.11)
      class DrawReplacement < StaticReplacement
        primitive :ability, :draw_replacement,
                  description: "While this permanent is on the battlefield, each time its controller would draw a " \
                               "card, they draw `amount` cards instead (even with an empty library). The draws it " \
                               "makes aren't replaced by it again, but another such effect applies to each of them.",
                  rules: %w[614.11 614.11a 614.5 121.2 616.1],
                  params: { "amount" => "integer >= 2" },
                  example: { "draw_replacement" => { "amount" => 2 } }

        attr_reader :amount

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[amount], errors, path)
          new(Mechanics.integer_param(params, :amount, errors, path, min: 2))
        end

        def initialize(amount)
          super()
          @amount = amount
          freeze
        end

        def kind = :draw_replacement
        def replace_draw = true
        def to_s = "if you would draw a card, draw #{amount} instead"
      end

      # "If another creature you control with a +1/+1 counter on it would be destroyed, instead remove all
      # +1/+1 counters from it and remove all damage from it." (CR 614.1a, regeneration-like 614.8)
      class DestroyReplacement < StaticReplacement
        primitive :ability, :destroy_replacement,
                  description: "If a permanent matching `affects` would be destroyed (by an effect, lethal damage or " \
                               "deathtouch), instead: all its `remove_counters` counters are removed (if given) and, " \
                               "with `remove_damage: true`, all damage marked on it is removed. Sacrificing isn't " \
                               "destroying, and 0 toughness isn't either.",
                  rules: %w[614.1a 614.8 701.8a 701.21a 704.5f 704.5g 704.5h],
                  params: { "affects" => "{\"each\": filter, \"controller\": ..., \"other\": bool}",
                            "remove_counters" => "counter name", "remove_damage" => "boolean" },
                  example: { "destroy_replacement" => {
                    "affects" => { "each" => { "creature" => { "counters" => "+1/+1" } }, "controller" => "you", "other" => true },
                    "remove_counters" => "+1/+1", "remove_damage" => true
                  } }

        attr_reader :affects, :counter, :damage

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[affects remove_counters remove_damage], errors, path)
          affects = Affects.build(Mechanics.fetch_param(params, :affects), errors, "#{path}.affects")
          counter = Mechanics.fetch_param(params, :remove_counters)
          counter &&= Counters.parse(counter, errors, "#{path}.remove_counters")
          damage = Mechanics.fetch_param(params, :remove_damage) == true
          errors << "#{path}: needs remove_counters and/or remove_damage" unless counter || damage
          new(affects, counter, damage)
        end

        def initialize(affects, counter, damage)
          super()
          @affects = affects
          @counter = counter
          @damage = damage
          freeze
        end

        def kind = :destroy_replacement
        def replaces?(engine, obj, source) = affects.match?(engine, obj, source)

        def replace_destroy(engine, obj)
          engine.remove_all_counters!(obj, counter) if counter
          engine.remove_damage!(obj) if damage
        end

        def to_s
          instead = [counter && "remove all #{counter} counters", damage && "remove all damage"].compact.join(" and ")
          "if #{affects} would be destroyed, instead #{instead}"
        end
      end

      # "If one or more tokens would be created under your control, that many 3/3 Illusion tokens are
      # created instead." (CR 614.1a, 111.1)
      class TokenReplacement < StaticReplacement
        primitive :ability, :token_replacement,
                  description: "If tokens would be created under this permanent's controller's control, that many " \
                               "`token` tokens are created instead (tapped or attacking if the originals would be). " \
                               "`token` is a predefined token name or inline card data.",
                  rules: %w[614.1a 614.16 111.1 616.1],
                  params: { "token" => "\"Treasure\" | \"Clue\" | \"Food\" | {card data}" },
                  example: { "token_replacement" => { "token" => { "name" => "Illusion", "types" => %w[artifact creature],
                                                                   "subtypes" => ["illusion"], "power" => 3,
                                                                   "toughness" => 3 } } }

        attr_reader :token_definition

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[token], errors, path)
          raw = Mechanics.fetch_param(params, :token)
          data = raw.is_a?(String) ? Enjine::Tokens.fetch(raw) : raw
          return new(CardDefinition.token(data)) if data.is_a?(Hash)

          errors << "#{path}.token: must be a predefined token (#{Enjine::Tokens::LIBRARY.keys.join(", ")}) or card data"
          new(nil)
        rescue InvalidCardDefinition => e
          e.errors.each { errors << "#{path}.token.#{it}" }
          new(nil)
        end

        def initialize(definition)
          super()
          @token_definition = definition
          freeze
        end

        def kind = :token_replacement
        def to_s = "if tokens would be created under your control, that many #{token_definition.name} tokens are created instead"
      end

      # "If one or more tokens would be created under your control, twice that many of those tokens are
      # created instead." (CR 614.1a, 111.1)
      class DoubleTokens < StaticReplacement
        primitive :ability, :double_tokens,
                  description: "While this permanent is on the battlefield, if tokens would be created under its " \
                               "controller's control, twice that many of those tokens are created instead. Several " \
                               "apply one after another (two make four times as many).",
                  rules: %w[614.1a 614.5 111.1 616.1],
                  example: "double_tokens"

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          new
        end

        def initialize
          super
          freeze
        end

        def kind = :double_tokens
        def doubles_tokens = true
        def to_s = "if tokens would be created under your control, twice that many are created instead"
      end

      # "If a creature an opponent controls would die, exile it instead." (CR 614.1a, 700.4)
      class ExileIfDiesStatic < StaticReplacement
        primitive :ability, :exile_if_dies,
                  description: "While this permanent is on the battlefield, a permanent matching `affects` that would " \
                               "be put into a graveyard from the battlefield is exiled instead.",
                  rules: %w[614.1a 700.4],
                  params: { "affects" => "{\"each\": filter, \"controller\": you|opponent|any, \"other\": bool}" },
                  example: { "exile_if_dies" => { "affects" => { "each" => "creature", "controller" => "opponent" } } }

        attr_reader :affects

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[affects], errors, path)
          new(Affects.build(Mechanics.fetch_param(params, :affects), errors, "#{path}.affects"))
        end

        def initialize(affects)
          super()
          @affects = affects
          freeze
        end

        def kind = :exile_if_dies
        def exiles_dying?(engine, obj, source) = affects.match?(engine, obj, source)
        def to_s = "if #{affects} would die, exile it instead"
      end

      # "Lands you control enter untapped." (CR 614.1c, 614.12; applied after every "enters tapped", 616.1)
      class EntersUntapped < StaticReplacement
        primitive :ability, :enters_untapped,
                  description: "Permanents matching `affects` enter the battlefield untapped, even if another effect " \
                               "or their own ability would have them enter tapped.",
                  rules: %w[614.1c 614.12 616.1],
                  params: { "affects" => "{\"each\": filter, \"controller\": you|opponent|any}" },
                  example: { "enters_untapped" => { "affects" => { "each" => "land", "controller" => "you" } } }

        attr_reader :affects

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[affects], errors, path)
          new(Affects.build(Mechanics.fetch_param(params, :affects), errors, "#{path}.affects"))
        end

        def initialize(affects)
          super()
          @affects = affects
          freeze
        end

        def kind = :enters_untapped
        def enters_untapped?(source, controller, facts) = affects.match_facts?(facts, controller, source)
        def to_s = "#{affects} enter untapped"
      end

      # "If a creature you control would enter while you control an attacking creature, instead it enters
      # tapped and attacking." (CR 614.1c, 508.4)
      class EntersAttacking < StaticReplacement
        primitive :ability, :enters_attacking,
                  description: "While this permanent's controller controls an attacking creature, permanents matching " \
                               "`affects` enter the battlefield tapped and attacking (the defending player). They " \
                               "never \"attacked\", so attack triggers don't see them.",
                  rules: %w[614.1c 508.4 506.4],
                  params: { "affects" => "{\"each\": filter, \"controller\": you|opponent|any}" },
                  example: { "enters_attacking" => { "affects" => { "each" => "creature", "controller" => "you" } } }

        attr_reader :affects

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[affects], errors, path)
          new(Affects.build(Mechanics.fetch_param(params, :affects), errors, "#{path}.affects"))
        end

        def initialize(affects)
          super()
          @affects = affects
          freeze
        end

        def kind = :enters_attacking

        def enters_attacking?(engine, source, controller, facts)
          engine.attackers.keys.any? { engine.object(it).controller == source.controller } &&
            affects.match_facts?(facts, controller, source)
        end

        def to_s = "#{affects} enter tapped and attacking while you control an attacking creature"
      end
    end

    module Effects
      # "Until end of turn, if one or more counters would be put on a permanent you control, that many plus
      # one of each of those kinds are put on it instead." (CR 614.1a, 611.2a)
      class CounterBonus < Effect
        primitive :effect, :counter_bonus,
                  description: "Until end of turn, whenever one or more counters would be put on a permanent the " \
                               "controller controls (including counters it enters with), that many plus `amount` " \
                               "of each of those kinds are put on it instead.",
                  rules: %w[614.1a 614.16 611.2a 122.6 616.1],
                  params: { "amount" => "integer (default 1)" },
                  example: { "counter_bonus" => { "amount" => 1 } }

        def self.keys = %w[amount if]
        def self.default_to = "you"

        def initialize(to:, params:, errors:, path:, targets_count: 0, results_count: 0)
          params = params.transform_keys(&:to_s)
          params["amount"] = 1 unless params.key?("amount")
          super
        end

        def apply(engine, ctx)
          engine.add_continuous_effect!("counter_bonus", ctx, [], "amount" => amount_for(engine, ctx))
        end

        def to_s = "until end of turn, counters put on your permanents: that many plus #{amount}"
      end

      # "If that creature would die this turn, exile it instead." (CR 614.1a, 700.4)
      class ExileIfDies < Effect
        primitive :effect, :exile_if_dies,
                  description: "Until end of turn, if a referenced permanent would be put into a graveyard from the " \
                               "battlefield, it is exiled instead.",
                  rules: %w[614.1a 700.4 611.2a 611.2c],
                  params: { "to" => "selector" },
                  example: { "exile_if_dies" => { "to" => { "target" => 0 } } }

        def self.keys = %w[to if]

        def apply(engine, ctx) = engine.add_continuous_effect!("exile_if_dies", ctx, objects(engine, ctx), {})
        def to_s = "if it would die this turn, exile it instead → #{to}"
      end

      # "Exile [this spell]" as part of its own resolution, so it doesn't go to the graveyard (CR 608.2n).
      class ExileThisSpell < Effect
        primitive :effect, :exile_this_spell,
                  description: "The resolving spell is exiled instead of being put into its owner's graveyard as it " \
                               "finishes resolving.",
                  rules: %w[608.2n 406.1],
                  example: "exile_this_spell"

        def self.keys = %w[if]
        def self.default_to = "you"

        # The resolving object is on the stack; an ability (not a spell) has no card to exile.
        def apply(engine, ctx)
          engine.move!(ctx.object, :exile, reason: "exile") if engine.state.objects[ctx.object]&.kind == "card"
        end

        def to_s = "exile this spell"
      end
    end
  end
end
