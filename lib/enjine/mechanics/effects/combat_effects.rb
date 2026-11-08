# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Base for effects with a second selector besides `to` (`with` / `from`).
      class PairEffect < Effect
        def self.other_key = raise(NotImplementedError)
        def self.keys = ["to", other_key, "if"]

        attr_reader :other

        def setup(params, errors, path)
          key = self.class.other_key
          raw = Mechanics.fetch_param(params, key)
          @other = if raw.nil?
                     (errors << "#{path}.#{key}: required") && nil
                   else
                     Selector.build(raw, errors, "#{path}.#{key}", targets_count: @targets_count, results_count: @results_count)
                   end
        end

        def other_creatures(engine, ctx)
          other.resolve(engine, ctx).select { engine.state.battlefield.include?(it) && engine.chars(it).creature? }
        end

        def creatures(engine, ctx) = objects(engine, ctx).select { engine.chars(it).creature? }
      end

      # "Target creature you control fights target creature an opponent controls." (CR 701.14)
      class Fight < PairEffect
        primitive :effect, :fight,
                  description: "The creature referenced by `to` fights the one referenced by `with`: each deals " \
                               "damage equal to its power to the other at the same time (not combat damage). If " \
                               "either is gone, no longer a creature or an illegal target, neither deals damage.",
                  rules: %w[701.14a 701.14b 701.14c 701.14d],
                  params: { "to" => "selector (one creature)", "with" => "selector (one creature)" },
                  example: { "fight" => { "to" => { "target" => 0 }, "with" => { "target" => 1 } } }

        def self.other_key = "with"

        def apply(engine, ctx)
          one = refs(engine, ctx).first
          other_one = other.resolve(engine, ctx).first
          engine.fight!(one, other_one) # nothing happens unless both are creatures on the battlefield
        end

        def to_s = "#{to} fights #{other}"
      end

      # "Target creatures you control each deal damage equal to their power to target creature." ("bite")
      class Bite < PairEffect
        primitive :effect, :bite,
                  description: "Each creature referenced by `from` deals damage equal to its power to each creature, " \
                               "planeswalker or player referenced by `to` (one damage event per source; not combat " \
                               "damage, and nothing is dealt back).",
                  rules: %w[120.3 120.4 608.2b],
                  params: { "from" => "selector (the creatures dealing damage)", "to" => "selector" },
                  example: { "bite" => { "from" => { "target" => 0 }, "to" => { "target" => 1 } } }

        def self.other_key = "from"

        def apply(engine, ctx)
          sources = other_creatures(engine, ctx)
          powers = sources.to_h { [it, engine.power(engine.object(it))] } # determined before any is dealt
          sources.each { |source| refs(engine, ctx).each { engine.deal_damage!(source, it, powers[source]) } }
        end

        def to_s = "#{other} each deal damage equal to their power → #{to}"
      end

      # "Remove two +1/+1 counters from target creature." (CR 122.8)
      class RemoveCounters < Effect
        primitive :effect, :remove_counters,
                  description: "Remove up to `amount` counters named `counter` from each referenced permanent.",
                  rules: %w[122.8],
                  params: { "counter" => "counter name", "amount" => "amount", "to" => "selector" },
                  example: { "remove_counters" => { "counter" => "+1/+1", "amount" => 2, "to" => { "target" => 0 } } }

        attr_reader :counter

        def self.keys = %w[counter amount to if]

        def setup(params, errors, path)
          @counter = Counters.normalize(Mechanics.fetch_param(params, :counter))
          message = Counters.error(@counter)
          errors << "#{path}.counter: #{message}" if message
        end

        def apply(engine, ctx)
          n = amount_for(engine, ctx)
          objects(engine, ctx).each { engine.remove_counters!(engine.object(it), counter, n) }
        end

        def to_s = "remove #{amount} #{counter} counter(s) → #{to}"
      end

      # "Remove all +1/+1 counters from it" / "remove all counters from it".
      class RemoveAllCounters < Effect
        primitive :effect, :remove_all_counters,
                  description: "Remove every counter named `counter` (every counter, if no `counter` is given) from " \
                               "each referenced permanent.",
                  rules: %w[122.8],
                  params: { "counter" => "optional counter name", "to" => "selector" },
                  example: { "remove_all_counters" => { "counter" => "+1/+1", "to" => { "target" => 0 } } }

        attr_reader :counter

        def self.keys = %w[counter to if]

        def setup(params, errors, path)
          raw = Mechanics.fetch_param(params, :counter)
          @counter = raw && Counters.normalize(raw)
          message = @counter && Counters.error(@counter)
          errors << "#{path}.counter: #{message}" if message
        end

        def apply(engine, ctx) = objects(engine, ctx).each { engine.remove_all_counters!(engine.object(it), counter) }
        def to_s = "remove all #{counter || "counters"} → #{to}"
      end

      # "All damage already dealt to it is healed" / "remove all damage from it" (CR 120.6, 514.2).
      class RemoveDamage < Effect
        primitive :effect, :remove_damage,
                  description: "Remove all damage marked on each referenced permanent.",
                  rules: %w[120.6 514.2],
                  params: { "to" => "selector" },
                  example: { "remove_damage" => { "to" => { "target" => 0 } } }

        def self.keys = %w[to if]

        def apply(engine, ctx) = objects(engine, ctx).each { engine.remove_damage!(engine.object(it)) }
        def to_s = "remove all damage → #{to}"
      end

      # "Gain control of target permanent" / "... until end of turn" / "Target opponent gains control of
      # target permanent you control" (CR 613.1b, 108.4, 506.4, 302.6).
      class GainControl < Effect
        DURATIONS = %w[permanent end_of_turn].freeze

        primitive :effect, :gain_control,
                  description: "The player referenced by `gains` (default you) gains control of each referenced " \
                               "permanent: indefinitely (`duration: \"permanent\"`, default) or until end of turn. " \
                               "A permanent that changes control leaves combat and is newly under its controller's " \
                               "control (it can't attack or {T} without haste).",
                  rules: %w[613.1b 108.4 506.4 302.6 514.2],
                  params: { "to" => "selector (permanents)", "gains" => "selector (a player; default \"you\")",
                            "duration" => DURATIONS.join(" | ") },
                  example: { "gain_control" => { "to" => { "target" => 0 }, "duration" => "end_of_turn" } }

        attr_reader :gains, :duration

        def self.keys = %w[to gains duration if]

        def setup(params, errors, path)
          @gains = Selector.build(Mechanics.fetch_param(params, :gains) || "you", errors, "#{path}.gains",
                                  targets_count: @targets_count, results_count: @results_count)
          @duration = Mechanics.fetch_param(params, :duration) || "permanent"
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
        end

        def apply(engine, ctx)
          player = gains.resolve(engine, ctx).filter_map { Filters.player_index(engine, it) }.first or return
          objects(engine, ctx).each do |id|
            obj = engine.object(id)
            duration == "permanent" ? engine.gain_control!(obj, player) : engine.gain_control_until_end_of_turn!(obj, player, ctx)
          end
        end

        def to_s = "#{gains} gains control#{" until end of turn" if duration == "end_of_turn"} → #{to}"
      end

      # "Until end of turn, they become Warriors in addition to their other types." (CR 613.1d, 205.1b)
      class AddSubtypes < Effect
        primitive :effect, :add_subtypes,
                  description: "Each referenced permanent gets the `subtypes` in addition to its other types until " \
                               "end of turn (layer 4).",
                  rules: %w[613.1d 205.1b 611.2a 611.2c],
                  params: { "subtypes" => "list of lowercase subtypes", "to" => "selector" },
                  example: { "add_subtypes" => { "subtypes" => ["warrior"], "to" => { "target" => 0 } } }

        attr_reader :subtypes

        def self.keys = %w[subtypes to if]

        def setup(params, errors, path)
          @subtypes = Mechanics.list_param(params, :subtypes, errors, path).map(&:to_s)
          ok = !@subtypes.empty? && @subtypes.all? { CardDefinition::SUBTYPE_FORMAT.match?(it) }
          errors << "#{path}.subtypes: must be a non-empty list of lowercase subtypes" unless ok
        end

        def apply(engine, ctx) = engine.add_continuous_effect!("add_subtypes", ctx, objects(engine, ctx), "subtypes" => subtypes)
        def to_s = "becomes #{subtypes.join(" ")} in addition until end of turn → #{to}"
      end
    end
  end
end
