# frozen_string_literal: true

require_relative "actions"

module Enjine
  module Mechanics
    module Effects
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
    end
  end
end
