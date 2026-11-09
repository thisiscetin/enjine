# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Rolling dice (CR 706): you roll `amount` dice with `sides` sides each (CR 706.1a), each result from 1 to
      # `sides` at random (the game's random number generator). The total of the results is the effect's amount
      # for later effects ({"this_way": n}), so a results table is a list of effects with `if` comparing it
      # (CR 706.3a).
      class RollDice < Effect
        primitive :effect, :roll_dice,
                  description: "You roll `amount` dice (default 1) with `sides` sides (default 6). The total of the " \
                               "results is this effect's amount: {\"this_way\": n} in later effects and conditions " \
                               "(a results table is effects with an `if` on it).",
                  rules: %w[706.1 706.1a 706.2 706.3a 608.2c],
                  params: { "sides" => "integer >= 2 (default 6)", "amount" => "amount (default 1)" },
                  example: { "roll_dice" => { "sides" => 20 } }

        def self.keys = %w[sides amount if]
        def self.default_to = "you"

        def initialize(to:, params:, errors:, path:, targets_count: 0, results_count: 0)
          params = params.transform_keys(&:to_s)
          params["amount"] = 1 unless params.key?("amount")
          super
        end

        def setup(params, errors, path)
          @sides = Mechanics.fetch_param(params, :sides) || 6
          errors << "#{path}.sides: must be an integer >= 2" unless @sides.is_a?(Integer) && @sides >= 2
        end

        def to_s = "roll #{amount == 1 ? "a" : amount} d#{@sides}"

        def apply(engine, ctx)
          amount_for(engine, ctx).times do
            result = engine.state.rng.rand(@sides) + 1 # CR 706.2: the natural result
            engine.emit Events::RolledDie.new(player: engine.name(ctx.controller), sides: @sides, result: result)
            engine.record_amount!(result)
          end
        end
      end
    end
  end
end
