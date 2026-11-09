# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "[Effects]. If [condition], repeat this process." (CR 608.2c): the effects run in order, then, while
      # `while` holds, they run again. Each pass is a fresh process with results of its own: {"result": n} inside
      # the list (and in `while`) names what effect n of the list did during this pass. What every pass moved or
      # created is also the result of the `repeat` effect itself.
      class Repeat < ChoiceEffect
        # A mandatory loop that never ends would be a draw (CR 104.4b); the engine stops after this many passes.
        MAX_PASSES = 100

        primitive :effect, :repeat,
                  description: "Run `effects`, then run them again for as long as `while` (a condition) holds after a " \
                               "pass (\"if the exiled card is a land card, repeat this process\"). {\"result\": n} in " \
                               "the list and in `while` names what effect n did during the current pass. At most " \
                               "#{MAX_PASSES} passes.",
                  rules: %w[608.2c 400.7j 104.4b],
                  params: { "effects" => "list of effects (one pass)", "while" => "condition, checked after each pass" },
                  example: { "repeat" => { "effects" => [{ "mill" => { "amount" => 1 } }],
                                           "while" => { "amount" => { "count" => { "result" => 0, "for" => { "types" => ["land"] } } },
                                                        "at_least" => 1 } } }

        attr_reader :effects

        def self.keys = %w[effects while if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @effects = Abilities::StackAbility.parse_effects(params, errors, path, @targets_count) # results of its own
          errors << "#{path}.effects: needs at least one effect" if @effects.empty?
          raw = Mechanics.fetch_param(params, :while)
          errors << "#{path}.while: required" if raw.nil?
          @while = raw && Condition.build(raw, errors, "#{path}.while", targets_count: @targets_count,
                                                                        results_count: @effects.size)
        end

        def nested_effects = @effects
        def to_s = "#{@effects.join("; ")} — repeat while #{@while}"

        # Progress in `locals`: "pass" (1, 2, ...), "next" (the effect of this pass to run), "results" / "amounts"
        # (what this pass's effects did so far) and the running effect's own locals under "child".
        def run(engine, ctx, locals)
          return :done unless locals["pass"] || condition.nil? || condition.true?(engine, ctx)

          locals["pass"] ||= 1
          loop do
            return :wait if run_pass(engine, ctx, locals) == :wait
            return :done if locals["pass"] >= MAX_PASSES || !@while&.true?(engine, pass_context(ctx, locals))

            locals["pass"] += 1
            %w[next results amounts].each { locals.delete(it) }
          end
        end

        private

        def run_pass(engine, ctx, locals)
          locals["next"] ||= 0
          while (i = locals["next"]) < @effects.size
            status, ids, amount = engine.recording_apart { @effects[i].run(engine, pass_context(ctx, locals), locals["child"] ||= {}) }
            (locals["results"] ||= [])[i] = Array(locals["results"][i]) + ids
            (locals["amounts"] ||= [])[i] = locals["amounts"][i].to_i + amount
            return :wait if status == :wait

            locals.delete("child")
            locals["next"] += 1
          end
          :done
        end

        # This pass's results, one list per effect of the list (CR 400.7j).
        def pass_context(ctx, locals)
          results = Array.new(@effects.size) { Array(locals.dig("results", it)) }
          amounts = Array.new(@effects.size) { locals.dig("amounts", it).to_i }
          EffectContext.new(ctx.controller, ctx.source, ctx.object, ctx.targets, results, amounts, ctx.memory)
        end
      end
    end
  end
end
