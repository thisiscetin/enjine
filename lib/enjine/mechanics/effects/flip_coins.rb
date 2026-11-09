# frozen_string_literal: true

require_relative "../abilities/turn_rules"

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
                  rules: %w[705.1 705.2 705.3 608.2c],
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
            locals["fixed"] = true if Abilities::FirstFlipsWin.applies?(engine, ctx.controller) # CR 705.3
          end
          calls = @count == "wins" && !locals["fixed"] # a flip with a stated result needs no call (CR 705.3)
          while locals["left"].positive?
            call = calls ? answers(locals).shift&.fetch("call") : nil
            return ask(engine, locals, ctx.controller, "Call the coin flip", CALLS) if calls && call.nil?

            flip!(engine, ctx, call, fixed: locals["fixed"])
            locals["left"] -= 1
          end
          :done
        end

        private

        # CR 705.3: a flip with a stated result (heads, and won) ignores the actual result.
        def flip!(engine, ctx, call, fixed: false)
          heads = fixed || engine.state.rng.rand(2).zero?
          won = fixed ? @count == "wins" || nil : call && (call == "heads") == heads
          call = "heads" if fixed && @count == "wins"
          engine.emit Events::CoinFlipped.new(player: engine.name(ctx.controller), heads: heads, won: won)
          engine.record_amount!(1) if call ? won : heads
        end
      end
    end

    module Abilities
      # "The first time you flip one or more coins each turn, those coins come up heads and you win those flips"
      # (CR 705.3): the flips of the first flip_coins effect its controller performs each turn have that result
      # (no call is asked). A flip is remembered in the turn's history (Engine::TurnHistory "coin_flips").
      class FirstFlipsWin < TurnRule
        primitive :ability, :first_flips_win,
                  description: "The first time each turn its controller flips one or more coins, those coins come up " \
                               "heads and they win those flips.",
                  rules: %w[705.3 604.1], example: "first_flips_win"

        INSTANCE = new.freeze

        def kind = :first_flips_win
        def to_s = "The first time you flip one or more coins each turn, those coins come up heads and you win those flips"

        def self.applies?(engine, index)
          engine.turn_log(index).fetch("coin_flips", 0).zero? &&
            engine.state.battlefield.any? do |id|
              engine.object(id).controller == index && engine.chars(id).abilities.any? { it.ability.kind == :first_flips_win }
            end
        end
      end
    end
  end
end
