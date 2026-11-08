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
    end

    module Costs
      # "Sacrifice this permanent" as a cost (CR 701.21, 602.2b).
      class SacrificeSelf < Primitive
        primitive :cost, :sacrifice,
                  description: "Sacrifice the permanent the ability belongs to (it goes to its owner's graveyard).",
                  rules: %w[701.21a 602.2b 118.3],
                  example: "sacrifice"

        INSTANCE = new.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          INSTANCE
        end

        def mana? = false
        # CR 701.21a, 614.17b: only a permanent its controller may sacrifice.
        def payable?(engine, object) = engine.can_sacrifice?(object, object.controller)
        def pay!(engine, object) = engine.move!(object.id, :graveyard, reason: "sacrifice")
        def to_s = "Sacrifice this"
      end
    end
  end
end
