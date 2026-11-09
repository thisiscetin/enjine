# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
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

      # "Choose a counter on target permanent. Put another counter of that kind on it." (CR 122.1, 122.6):
      # for each referenced permanent with counters, its controller's chosen kind among the kinds already on
      # it (no choice with only one kind) gets one more counter. Nothing happens to one without counters.
      class AnotherCounter < ChoiceEffect
        primitive :effect, :another_counter,
                  description: "For each referenced permanent, the controller chooses a kind of counter already on it " \
                               "(asked only when there are several kinds) and puts one more counter of that kind on it.",
                  rules: %w[122.1 122.6],
                  params: { "to" => "selector" },
                  example: { "another_counter" => { "to" => { "target" => 0 } } }

        def self.keys = %w[to if]

        def to_s = "another counter of a kind already there → #{to}"

        def run(engine, ctx, locals)
          unless locals["ids"]
            return :done unless condition.nil? || condition.true?(engine, ctx)

            locals["ids"] = objects(engine, ctx)
            locals["i"] = 0
          end
          while locals["i"] < locals["ids"].size
            obj = engine.state.objects[locals["ids"][locals["i"]]]
            kinds = obj&.zone == :battlefield ? obj.counters.select { |_, n| n.positive? }.keys.sort : []
            kind = kinds.first
            if kinds.size > 1
              answer = answers(locals)[locals.fetch("k", 0)] or return ask_kind(engine, ctx, obj, kinds)
              kind = answer["counter"]
              locals["k"] = locals.fetch("k", 0) + 1
            end
            engine.add_counters!(obj, kind, 1, by_player: ctx.controller) if kind
            locals["i"] += 1
          end
          :done
        end

        private

        def ask_kind(engine, ctx, obj, kinds)
          engine.ask!("kind" => "effect_choice", "player" => ctx.controller,
                      "prompt" => "Choose a kind of counter on #{obj.id} to put another of",
                      "choices" => kinds.map { { "type" => "counter", "counter" => it } })
          :wait
        end
      end

      # "Distribute N +1/+1 counters among one or two target creatures" (CR 601.2d): the division was
      # announced while casting (the spell ability's `divide`); each target that is still legal gets its
      # share (CR 608.2b).
      class DistributeCounters < Effect
        primitive :effect, :distribute_counters,
                  description: "Put on each legal target the number of `counter` counters assigned to it as the spell " \
                               "or ability was cast (its `divide` amount, at least one per target).",
                  rules: %w[601.2d 608.2b 122.1],
                  params: { "counter" => "counter name" },
                  example: { "distribute_counters" => { "counter" => "+1/+1" } }

        attr_reader :counter

        def self.keys = %w[counter if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @counter = Counters.normalize(Mechanics.fetch_param(params, :counter))
          message = Counters.error(@counter)
          errors << "#{path}.counter: #{message}" if message
        end

        def to_s = "distribute #{counter} counters among the targets"

        def apply(engine, ctx)
          engine.object(ctx.object).memory.fetch("division", {}).each do |ref, n|
            next unless ctx.targets.flatten.include?(ref) # still a legal target (CR 608.2b)

            engine.add_counters!(engine.object(ref), counter, n, by_player: ctx.controller)
          end
        end
      end
    end
  end
end
