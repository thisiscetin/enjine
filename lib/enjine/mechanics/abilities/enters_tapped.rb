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
        def payable?(engine, object) = engine.state.battlefield.include?(object.id)
        def pay!(engine, object) = engine.move!(object.id, :graveyard, reason: "sacrifice")
        def to_s = "Sacrifice this"
      end
    end
  end
end
