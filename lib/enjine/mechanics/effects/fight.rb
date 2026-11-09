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
    end
  end
end
