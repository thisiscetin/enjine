# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # "Pay 2 life" / "Pay X life" as a cost (CR 119.4, 118.3b): {"pay_life": 2} or {"pay_life": "X"}. A
      # player can pay life only if their life total is at least that much; 0 life can always be paid
      # (CR 119.4b). X is announced with the spell or ability (CR 601.2b, 107.3a), at most the life total.
      # An amount ("Ward—Pay life equal to Raubahn's power": {"pay_life": {"power": "self"}}) is computed as
      # the cost is paid: while a spell or ability resolves (`pay`, ward) in its context (#fixed), while
      # casting or activating for the object it's paid for.
      class PayLife < Primitive
        primitive :cost, :pay_life,
                  description: "Pay that much life (you lose it). Only possible while your life total is at least " \
                               "that much. `\"X\"` pays the X announced for the spell or ability (at most your life " \
                               "total); it may be a spell's additional cost. An amount (e.g. {\"power\": \"self\"}, " \
                               "\"pay life equal to its power\") is computed as the cost is paid.",
                  rules: %w[119.4 119.4b 118.3b 601.2b 107.3a 702.21a],
                  params: { "(value)" => "integer >= 1, \"X\", or an amount" },
                  example: { "pay_life" => 2 }

        attr_reader :amount

        def self.scalar_params? = true

        def self.build(params, errors, path, **)
          return new(Amount.build(params, errors, path, targets_count: 0)) if params.is_a?(Hash)

          ok = params == "X" || (params.is_a?(Integer) && params >= 1)
          errors << "#{path}: must be an integer >= 1, \"X\" or an amount" unless ok
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
        def computed? = @amount.respond_to?(:value)
        def x_limit(engine, object) = [engine.player(object.controller).life, 0].max

        # The cost with its amount computed in `ctx` (an EffectContext): "its power" as a ward trigger resolves.
        def fixed(engine, ctx) = computed? ? PayLife.new([@amount.value(engine, ctx), 0].max) : self

        # X is bounded by the life total as it's announced (Engine::Costs#x_limit).
        def payable?(engine, object) = x? || engine.player(object.controller).life >= life(engine, object)

        def pay!(engine, object)
          n = x? ? engine.casting&.fetch("x", 0).to_i : life(engine, object)
          engine.change_life!(object.controller, -n) if n.positive?
        end

        def to_s = computed? ? "Pay life equal to #{@amount}" : "Pay #{@amount} life"

        private

        def life(engine, object)
          return @amount.to_i unless computed?

          [@amount.value(engine, EffectContext.new(object.controller, object.id, object.id, [])), 0].max
        end
      end
    end
  end
end
