# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Flipping coins (CR 705). With `count: "wins"` (default) the flipper calls each coin, heads or tails,
      # and wins the flips whose result matches the call (CR 705.2); with `count: "heads"` the effect only
      # cares how many coins come up heads and nobody wins or loses. The number counted is the effect's
      # amount for later effects ({"this_way": n}): "if you win the flip, ..." is an `if` comparing it.
      class FlipCoins < ChoiceEffect
        COUNTS = %w[wins heads].freeze
        CALLS = [{ "type" => "call", "call" => "heads" }, { "type" => "call", "call" => "tails" }].freeze

        primitive :effect, :flip_coins,
                  description: "You flip `amount` coins (default 1), each coming up heads or tails at random (the " \
                               "game's random number generator). `count`: \"wins\" (default; you call each flip and " \
                               "win it if the call matches) or \"heads\" (no one wins or loses). How many were " \
                               "counted is this effect's amount: {\"this_way\": n} in later effects and conditions.",
                  rules: %w[705.1 705.2 608.2c],
                  params: { "amount" => "amount (default 1)", "count" => COUNTS.join(" | ") },
                  example: { "flip_coins" => {} }

        def self.keys = %w[amount count if]
        def self.default_to = "you"

        def initialize(to:, params:, errors:, path:, targets_count: 0, results_count: 0)
          params = params.transform_keys(&:to_s)
          params["amount"] = 1 unless params.key?("amount")
          super
        end

        def setup(params, errors, path)
          @count = Mechanics.fetch_param(params, :count) || "wins"
          errors << "#{path}.count: must be one of #{COUNTS.join(", ")}" unless COUNTS.include?(@count)
        end

        def to_s = "flip #{amount == 1 ? "a coin" : "#{amount} coins"} (counting #{@count})"

        # A call is asked before each flip (CR 705.2); the flips happen as they are called.
        def run(engine, ctx, locals)
          unless locals["left"]
            return :done unless condition.nil? || condition.true?(engine, ctx)

            locals["left"] = amount_for(engine, ctx)
          end
          while locals["left"].positive?
            call = @count == "wins" ? answers(locals).shift&.fetch("call") : nil
            return ask(engine, locals, ctx.controller, "Call the coin flip", CALLS) if @count == "wins" && call.nil?

            flip!(engine, ctx, call)
            locals["left"] -= 1
          end
          :done
        end

        private

        def flip!(engine, ctx, call)
          heads = engine.state.rng.rand(2).zero?
          won = call && (call == "heads") == heads
          engine.emit Events::CoinFlipped.new(player: engine.name(ctx.controller), heads: heads, won: won)
          engine.record_amount!(1) if call ? won : heads
        end
      end
    end
  end
end
