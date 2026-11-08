# frozen_string_literal: true

module Enjine
  module Mechanics
    # One-shot and continuous effects (CR 609-611). Each effect is built from data
    # and applied at resolution with an EffectContext.
    module Effects
      COUNTER_KINDS = %w[+1/+1 -1/-1 loyalty].freeze

      # Base effect: parses the common "to" selector, an "amount" (fixed or computed, see
      # Mechanics::Amount) and an optional "if" condition checked on resolution (CR 608.2c).
      class Effect < Primitive
        attr_reader :to, :condition

        def self.keys = %w[amount to if]
        def self.default_to = nil

        def self.build(params, errors, path, targets_count: 0, **)
          Mechanics.check_keys(params, keys, errors, path)
          raw_to = Mechanics.fetch_param(params, :to) || default_to
          to = if raw_to.nil?
                 errors << "#{path}.to: required"
                 nil
               else
                 Selector.build(raw_to, errors, "#{path}.to", targets_count: targets_count)
               end
          new(to: to, params: params, errors: errors, path: path, targets_count: targets_count)
        end

        def initialize(to:, params:, errors:, path:, targets_count: 0)
          super()
          @to = to
          if self.class.keys.include?("amount")
            raw = Mechanics.fetch_param(params, :amount)
            @amount = if raw.nil?
                        (errors << "#{path}.amount: required") && Amount::Fixed.new(0)
                      else
                        Amount.build(raw, errors,
                                     "#{path}.amount", targets_count: targets_count)
                      end
          end
          raw_if = Mechanics.fetch_param(params, :if)
          @condition = raw_if && Condition.build(raw_if, errors, "#{path}.if", targets_count: targets_count)
          setup(params, errors, path)
          freeze
        end

        # The fixed amount (for display), or the amount computed for this resolution.
        def amount = @amount.is_a?(Amount::Fixed) ? @amount.n : @amount
        def amount_for(engine, ctx) = @amount.value(engine, ctx)

        def setup(_params, _errors, _path) = nil

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
                  description: "Put `amount` counters of kind `counter` (+1/+1, -1/-1, loyalty) on each referenced " \
                               "permanent.",
                  rules: %w[122.1 122.6 613.4c],
                  params: { "counter" => COUNTER_KINDS.join(" | "), "amount" => "integer", "to" => "selector" },
                  example: { "add_counters" => { "counter" => "+1/+1", "amount" => 1,
                                                 "to" => { "each" => "creature", "controller" => "you" } } }

        attr_reader :counter

        def self.keys = %w[counter amount to if]

        def setup(params, errors, path)
          @counter = Mechanics.fetch_param(params, :counter)
          return if COUNTER_KINDS.include?(@counter)

          errors << "#{path}.counter: must be one of #{COUNTER_KINDS.join(", ")}"
        end

        def to_s = "#{amount} #{counter} counter(s) → #{to}"

        def apply(engine, ctx)
          n = amount_for(engine, ctx)
          objects(engine, ctx).each { engine.add_counters!(engine.object(it), counter, n) }
        end
      end

      # +N/+N until end of turn (CR 611.2, 613.4c). Affected set is locked in on resolution (611.2c).
      class Pump < Effect
        primitive :effect, :pump,
                  description: "Each referenced creature gets +power/+toughness until end of turn. The set of " \
                               "affected creatures is locked in when the effect starts.",
                  rules: %w[611.2a 611.2c 613.4c 514.2],
                  params: { "power" => "integer (may be negative)", "toughness" => "integer (may be negative)",
                            "to" => "selector" },
                  example: { "pump" => { "power" => 3, "toughness" => 3, "to" => { "target" => 0 } } }

        attr_reader :power, :toughness

        def self.keys = %w[power toughness to if]

        def setup(params, errors, path)
          @power = Mechanics.integer_param(params, :power, errors, path, default: 0)
          @toughness = Mechanics.integer_param(params, :toughness, errors, path, default: 0)
        end

        def to_s = "#{format("%+d", power)}/#{format("%+d", toughness)} until end of turn → #{to}"

        def apply(engine, ctx)
          affected = objects(engine, ctx).select { engine.chars(it).creature? }
          engine.add_continuous_effect!("pump", ctx, affected, "power" => power, "toughness" => toughness)
        end
      end

      # Gain life (CR 119.3).
      class GainLife < Effect
        primitive :effect, :gain_life, description: "Each referenced player gains `amount` life (default: you).",
                                       rules: %w[119.3], params: { "amount" => "integer", "to" => "selector" },
                                       example: { "gain_life" => { "amount" => 3 } }
        def self.default_to = "you"
        def apply(engine, ctx) = players(engine, ctx).each { engine.change_life!(it, amount_for(engine, ctx)) }
      end

      # Lose life (CR 119.3).
      class LoseLife < Effect
        primitive :effect, :lose_life, description: "Each referenced player loses `amount` life.",
                                       rules: %w[119.3], params: { "amount" => "integer", "to" => "selector" },
                                       example: { "lose_life" => { "amount" => 2, "to" => "each_opponent" } }
        def apply(engine, ctx) = players(engine, ctx).each { engine.change_life!(it, -amount_for(engine, ctx)) }
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

      # Counter a spell (CR 701.6).
      class CounterSpell < Effect
        primitive :effect, :counter, description: "Counter each referenced spell: it leaves the stack for its " \
                                                  "owner's graveyard without resolving.",
                                     rules: %w[701.6a], params: { "to" => "selector" },
                                     example: { "counter" => { "to" => { "target" => 0 } } }
        def self.keys = %w[to if]

        def apply(engine, ctx)
          refs(engine, ctx).each do |id|
            next unless engine.state.stack.include?(id)

            engine.move!(id, :graveyard, reason: "countered")
          end
        end
      end
    end
  end
end
