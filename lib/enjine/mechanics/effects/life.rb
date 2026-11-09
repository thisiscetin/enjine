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

      # "Your life total becomes 10" (CR 119.5): the player gains or loses the difference.
      class SetLife < Effect
        primitive :effect, :set_life,
                  description: "Each referenced player's life total becomes `amount` (default: you): they gain or " \
                               "lose the difference (so \"can't gain life\" and life-gain triggers apply).",
                  rules: %w[119.5 119.7], params: { "amount" => "amount", "to" => "selector" },
                  example: { "set_life" => { "amount" => 10 } }
        def self.default_to = "you"

        def apply(engine, ctx)
          players(engine, ctx).each { LoseLife.change!(engine, it, amount_for(engine, ctx) - engine.player(it).life) }
        end
      end

      # "Exchange life totals with target opponent" (CR 701.12a, 701.12c): the player `to` (default you) and
      # the player `with` each gain or lose life to end at the other's previous total; if either can't (CR
      # 119.7), nothing happens. The life the first player lost this way is recorded for {"this_way": n}.
      class ExchangeLifeTotals < Effect
        primitive :effect, :exchange_life_totals,
                  description: "The player `to` references (default you) and the one `with` references exchange " \
                               "life totals: each gains or loses the difference. If either can't gain life and " \
                               "would, no exchange happens. The life the first player lost this way is recorded for " \
                               "{\"this_way\": n}.",
                  rules: %w[701.12a 701.12c 119.7],
                  params: { "to" => "selector (a player, default you)", "with" => "selector (a player)" },
                  example: { "exchange_life_totals" => { "with" => { "target" => 0 } } }

        attr_reader :with

        def self.keys = %w[to with if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @with = Exchange.with(params, errors, path, @targets_count, @results_count)
        end

        def apply(engine, ctx)
          one, other = [to, with].map { |sel| sel.resolve(engine, ctx).filter_map { Filters.player_index(engine, it) }.first }
          return engine.record_amount!(0) if one.nil? || other.nil? || one == other

          lives = [one, other].to_h { [it, engine.player(it).life] }
          gains = { one => lives[other] - lives[one], other => lives[one] - lives[other] }
          return engine.record_amount!(0) if gains.any? { |index, delta| delta.positive? && engine.player_rule?(index, "cant_gain_life") }

          gains.each { |index, delta| engine.change_life!(index, delta) }
          engine.record_amount!([lives[one] - engine.player(one).life, 0].max)
        end

        def to_s = "exchange life totals: #{to} and #{with}"
      end
    end
  end
end
