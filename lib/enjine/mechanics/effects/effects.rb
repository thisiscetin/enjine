# frozen_string_literal: true

module Enjine
  module Mechanics
    # One-shot and continuous effects (CR 609-611). Each effect is built from data
    # and applied at resolution with an EffectContext.
    module Effects
      # Base effect: parses the common "to" selector, an "amount" (fixed or computed, see
      # Mechanics::Amount) and an optional "if" condition checked on resolution (CR 608.2c).
      class Effect < Primitive
        attr_reader :to, :condition

        def self.keys = %w[amount to if]
        def self.default_to = nil

        # `results_count`: how many earlier effects of the enclosing list a {"result": n} selector may name.
        def self.build(params, errors, path, targets_count: 0, results_count: 0, **)
          Mechanics.check_keys(params, keys, errors, path)
          raw_to = Mechanics.fetch_param(params, :to) || default_to
          to = if raw_to.nil?
                 errors << "#{path}.to: required"
                 nil
               else
                 Selector.build(raw_to, errors, "#{path}.to", targets_count: targets_count, results_count: results_count)
               end
          new(to: to, params: params, errors: errors, path: path, targets_count: targets_count, results_count: results_count)
        end

        def initialize(to:, params:, errors:, path:, targets_count: 0, results_count: 0)
          super()
          @to = to
          @targets_count = targets_count
          @results_count = results_count
          if self.class.keys.include?("amount")
            raw = Mechanics.fetch_param(params, :amount)
            @amount = if raw.nil?
                        (errors << "#{path}.amount: required") && Amount::Fixed.new(0)
                      else
                        Amount.build(raw, errors, "#{path}.amount", targets_count: targets_count,
                                                                    results_count: results_count)
                      end
          end
          raw_if = Mechanics.fetch_param(params, :if)
          @condition = raw_if && Condition.build(raw_if, errors, "#{path}.if", targets_count: targets_count,
                                                                               results_count: results_count)
          setup(params, errors, path)
          freeze
        end

        # The fixed amount (for display), or the amount computed for this resolution.
        def amount = @amount.is_a?(Amount::Fixed) ? @amount.n : @amount
        def amount_for(engine, ctx) = @amount.value(engine, ctx)

        def setup(_params, _errors, _path) = nil

        # Effects nested inside this one (a "may" or delayed trigger's list); see CardDefinition#all_effects.
        def nested_effects = []

        # CR 118.3: whether the effect can be done fully now (an optional effect offered as a cost).
        def possible?(_engine, _ctx) = true

        # Runs the effect during resolution. Effects that need a player's choice override this,
        # keep their progress in `locals` (plain JSON data) and return :wait after asking.
        def run(engine, ctx, _locals)
          apply(engine, ctx) if condition.nil? || condition.true?(engine, ctx)
          :done
        end

        def refs(engine, ctx) = to ? to.resolve(engine, ctx) : []

        def to_s
          words = self.class.primitive_name.tr("_", " ")
          words += " #{amount}" if amount
          "#{words} → #{to}"
        end

        def objects(engine, ctx)
          refs(engine, ctx).select { engine.state.objects.key?(it) && engine.state.battlefield.include?(it) }
        end

        def players(engine, ctx) = refs(engine, ctx).filter_map { Filters.player_index(engine, it) }
      end

      # Deal N damage (CR 120).
      class DealDamage < Effect
        primitive :effect, :deal_damage,
                  description: "Deal `amount` damage to each referenced creature, planeswalker or player. Damage to a " \
                               "player causes life loss; to a planeswalker removes loyalty counters; to a creature " \
                               "is marked until cleanup.",
                  rules: %w[120.3a 120.3c 120.3e 120.6],
                  params: { "amount" => "integer", "to" => "selector" },
                  example: { "deal_damage" => { "amount" => 3, "to" => { "target" => 0 } } }

        def apply(engine, ctx)
          n = amount_for(engine, ctx)
          refs(engine, ctx).each { engine.deal_damage!(ctx.source || ctx.object, it, n) }
        end
      end

      # Put counters on permanents (CR 122).
      class AddCounters < Effect
        primitive :effect, :add_counters,
                  description: "Put `amount` counters named `counter` on each referenced permanent. Any counter " \
                               "name works (+1/+1, -1/-1, loyalty, stun, shield, oil, a keyword, ...); see " \
                               "docs/reference/counters.md for the ones with rules.",
                  rules: %w[122.1 122.6 613.4c],
                  params: { "counter" => "counter name (+X/+Y, -X/-Y or a lowercase word)", "amount" => "integer",
                            "to" => "selector" },
                  example: { "add_counters" => { "counter" => "+1/+1", "amount" => 1,
                                                 "to" => { "each" => "creature", "controller" => "you" } } }

        attr_reader :counter

        def self.keys = %w[counter amount to if]

        def setup(params, errors, path)
          @counter = Counters.normalize(Mechanics.fetch_param(params, :counter))
          message = Counters.error(@counter)
          errors << "#{path}.counter: #{message}" if message
        end

        def to_s = "#{amount} #{counter} counter(s) → #{to}"

        def apply(engine, ctx)
          n = amount_for(engine, ctx)
          objects(engine, ctx).each { engine.add_counters!(engine.object(it), counter, n, by_player: ctx.controller) }
        end
      end

      # +N/+N until end of turn (CR 611.2, 613.4c). Affected set is locked in on resolution (611.2c).
      # "Until your next turn" lasts until the controller's next turn begins (CR 611.2a, 500.1; see
      # Engine::Rules#end_effects_until_turn_of!).
      class Pump < Effect
        DURATIONS = %w[end_of_turn until_your_next_turn].freeze

        primitive :effect, :pump,
                  description: "Each referenced creature gets +power/+toughness until end of turn (`duration: " \
                               "\"until_your_next_turn\"`: until its controller's next turn begins). The set of " \
                               "affected creatures is locked in when the effect starts.",
                  rules: %w[611.2a 611.2c 613.4c 514.2 500.1],
                  params: { "power" => "amount (may be negative, e.g. {\"times\": [\"x\", -1]} for -X)",
                            "toughness" => "amount (may be negative)", "to" => "selector",
                            "duration" => DURATIONS.join(" | ") },
                  example: { "pump" => { "power" => 3, "toughness" => 3, "to" => { "target" => 0 } } }

        attr_reader :duration

        def self.keys = %w[power toughness to duration if]

        # A signed amount: an integer, or a computed Amount ("+X/+X, where X is ...", CR 608.2h).
        def self.signed(params, key, errors, path, **context)
          raw = Mechanics.fetch_param(params, key)
          raw.nil? ? Amount::Fixed.new(0) : Amount.build(raw, errors, "#{path}.#{key}", min: -1_000_000, **context)
        end

        def self.signed_text(amount) = amount.is_a?(Amount::Fixed) ? format("%+d", amount.n) : "+(#{amount})"

        def setup(params, errors, path)
          context = { targets_count: @targets_count, results_count: @results_count }
          @power = Pump.signed(params, :power, errors, path, **context)
          @toughness = Pump.signed(params, :toughness, errors, path, **context)
          @duration = Mechanics.fetch_param(params, :duration) || "end_of_turn"
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
        end

        # The fixed bonus (for display); computed bonuses are Amounts.
        def power = @power.is_a?(Amount::Fixed) ? @power.n : @power
        def toughness = @toughness.is_a?(Amount::Fixed) ? @toughness.n : @toughness

        def to_s
          "#{Pump.signed_text(@power)}/#{Pump.signed_text(@toughness)} until #{duration.delete_prefix("until_").tr("_", " ")} → #{to}"
        end

        # The amounts are computed once, as the effect starts (CR 608.2h, 611.2c).
        def apply(engine, ctx)
          affected = objects(engine, ctx).select { engine.chars(it).creature? }
          engine.add_continuous_effect!("pump", ctx, affected, "power" => @power.value(engine, ctx),
                                                               "toughness" => @toughness.value(engine, ctx),
                                                               "duration" => duration)
        end
      end

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

      # Draw cards (CR 121).
      class Draw < Effect
        primitive :effect, :draw, description: "Each referenced player draws `amount` cards (default: you).",
                                  rules: %w[121.1 121.2], params: { "amount" => "integer", "to" => "selector" },
                                  example: { "draw" => { "amount" => 2 } }
        def self.default_to = "you"
        def apply(engine, ctx) = players(engine, ctx).each { |i| amount_for(engine, ctx).times { engine.draw!(i) } }
      end

      # Destroy permanents (CR 701.8).
      class Destroy < Effect
        primitive :effect, :destroy, description: "Destroy each referenced permanent (it goes to its owner's graveyard).",
                                     rules: %w[701.8a], params: { "to" => "selector" },
                                     example: { "destroy" => { "to" => { "target" => 0 } } }
        def self.keys = %w[to if]

        # CR 702.12b: indestructible permanents aren't destroyed.
        def apply(engine, ctx)
          objects(engine, ctx).each do |id|
            engine.move!(id, :graveyard, reason: "destroy") unless engine.chars(id).keyword?(:indestructible)
          end
        end
      end

      # Counter a spell or ability (CR 701.6).
      class CounterSpell < Effect
        primitive :effect, :counter, description: "Counter each referenced spell or ability: a spell leaves the " \
                                                  "stack for its owner's graveyard without resolving, an ability " \
                                                  "ceases to exist. A spell that can't be countered stays.",
                                     rules: %w[701.6a 701.6b 101.2], params: { "to" => "selector" },
                                     example: { "counter" => { "to" => { "target" => 0 } } }
        def self.keys = %w[to if]

        def apply(engine, ctx)
          refs(engine, ctx).each { engine.counter!(it) if engine.state.stack.include?(it) }
        end
      end
    end
  end
end
