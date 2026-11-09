# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Gain life (CR 119.3).
      class GainLife < Effect
        primitive :effect, :gain_life, description: "Each referenced player gains `amount` life (default: you).",
                                       rules: %w[119.3], params: { "amount" => "integer", "to" => "selector" },
                                       example: { "gain_life" => { "amount" => 3 } }
        def self.default_to = "you"
        def apply(engine, ctx) = players(engine, ctx).each { LoseLife.change!(engine, it, amount_for(engine, ctx)) }
      end

      # Lose life (CR 119.3).
      class LoseLife < Effect
        primitive :effect, :lose_life, description: "Each referenced player loses `amount` life. The life lost is " \
                                                    "recorded for {\"this_way\": n}.",
                                       rules: %w[119.3], params: { "amount" => "integer", "to" => "selector" },
                                       example: { "lose_life" => { "amount" => 2, "to" => "each_opponent" } }
        def apply(engine, ctx) = players(engine, ctx).each { LoseLife.change!(engine, it, -amount_for(engine, ctx)) }

        # Changes a life total and records how much it changed (life lost "this way", CR 608.2c).
        def self.change!(engine, index, delta)
          before = engine.player(index).life
          engine.change_life!(index, delta)
          engine.record_amount!((engine.player(index).life - before).abs)
        end
      end
    end
  end
end
