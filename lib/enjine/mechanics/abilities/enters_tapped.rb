# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # "This permanent enters tapped." A replacement effect on its own entering (CR 614.1c, 614.12).
      class EntersTapped < Primitive
        primitive :ability, :enters_tapped,
                  description: "This permanent enters the battlefield tapped (a self-replacement effect).",
                  rules: %w[614.1c 614.12],
                  example: "enters_tapped"

        INSTANCE = new.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          INSTANCE
        end

        def kind = :enters_tapped
        def mana_ability? = false
        def allowed_types = nil
        def to_s = "enters tapped"
        def try_effects = []

        # Called by the replacement pass for the entering object.
        def modify_entering(enters) = enters["tapped"] = true
      end

      # "As this enters, you may pay N life. If you don't, it enters tapped." (CR 614.12, 119.4).
      # The controller chooses before it enters.
      class EntersTappedUnlessPayLife < Primitive
        primitive :ability, :enters_tapped_unless_pay_life,
                  description: "As this permanent enters, its controller may pay `life` life; if they don't, it enters " \
                               "tapped. You can't pay more life than you have.",
                  rules: %w[614.12 119.4],
                  params: { "life" => "integer" },
                  example: { "enters_tapped_unless_pay_life" => { "life" => 2 } }

        attr_reader :life

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[life], errors, path)
          new(Mechanics.integer_param(params, :life, errors, path, min: 1))
        end

        def initialize(life)
          super()
          @life = life
          freeze
        end

        def kind = :entering_choice
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        def to_s = "as this enters, pay #{life} life or it enters tapped"

        # Options for the controller (CR 119.4: paying life needs at least that much).
        def options(engine, controller)
          pay = engine.player(controller).life >= life ? [{ type: "pay_life", life: life }] : []
          pay + [{ type: "enter_tapped" }]
        end

        def enters_for(answer) = { "tapped" => answer[:type] != "pay_life" }
      end

      # "This land enters tapped unless you control two or more other lands." A self-replacement effect that
      # checks its condition as the permanent would enter (CR 614.1c, 614.12): it isn't on the battlefield
      # yet, so "you control" counts only the others.
      class EntersTappedUnless < Primitive
        primitive :ability, :enters_tapped_unless,
                  description: "This permanent enters tapped unless `condition` is true as it would enter (checked for " \
                               "its controller; the permanent itself isn't on the battlefield yet).",
                  rules: %w[614.1c 614.12],
                  params: { "condition" => "a condition, e.g. {\"controls\": {\"each\": \"land\", \"controller\": \"you\"}, " \
                                           "\"at_least\": 2}" },
                  example: { "enters_tapped_unless" => { "condition" => { "controls" => { "each" => "land", "controller" => "you" },
                                                                          "at_least" => 2 } } }

        attr_reader :condition

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[condition], errors, path)
          raw = Mechanics.fetch_param(params, :condition)
          condition = raw.nil? ? ((errors << "#{path}.condition: required") && nil) : Condition.build(raw, errors, "#{path}.condition")
          new(condition)
        end

        def initialize(condition)
          super()
          @condition = condition
          freeze
        end

        def kind = :enters_tapped
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        def to_s = "enters tapped unless #{condition}"

        # Called by the replacement pass for the entering object (Replacements.entering!).
        def modify_entering_for(engine, controller, object_id, enters)
          enters["tapped"] = true unless condition&.true?(engine, EffectContext.new(controller, object_id, nil, []))
        end
      end
    end
  end
end
