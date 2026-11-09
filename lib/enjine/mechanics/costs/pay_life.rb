# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # "Pay 2 life" / "Pay X life" as a cost (CR 119.4, 118.3b): {"pay_life": 2} or {"pay_life": "X"}. A
      # player can pay life only if their life total is at least that much; 0 life can always be paid
      # (CR 119.4b). X is announced with the spell or ability (CR 601.2b, 107.3a), at most the life total.
      class PayLife < Primitive
        primitive :cost, :pay_life,
                  description: "Pay that much life (you lose it). Only possible while your life total is at least " \
                               "that much. `\"X\"` pays the X announced for the spell or ability (at most your life " \
                               "total); it may be a spell's additional cost.",
                  rules: %w[119.4 119.4b 118.3b 601.2b 107.3a],
                  params: { "(value)" => "integer >= 1, or \"X\"" },
                  example: { "pay_life" => 2 }

        attr_reader :amount

        def self.scalar_params? = true

        def self.build(params, errors, path, **)
          errors << "#{path}: must be an integer >= 1 or \"X\"" unless params == "X" || (params.is_a?(Integer) && params >= 1)
          new(params)
        end

        def initialize(amount)
          super()
          @amount = amount
          freeze
        end

        def mana? = false
        def spell_cost? = true
        def x? = @amount == "X"

        # X is bounded by the life total as it's announced (Engine::Costs#x_limit).
        def payable?(engine, object) = x? || engine.player(object.controller).life >= @amount.to_i

        def pay!(engine, object)
          life = x? ? engine.casting&.fetch("x", 0).to_i : @amount.to_i
          engine.change_life!(object.controller, -life) if life.positive?
        end

        def to_s = "Pay #{@amount} life"
      end
    end
  end
end
