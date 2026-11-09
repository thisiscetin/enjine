# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Proliferate (CR 701.34a): choose any number of permanents and/or players that have a counter, then
      # give each one another counter of each kind it already has. "Proliferate X times" repeats it.
      class Proliferate < ChoiceEffect
        primitive :effect, :proliferate,
                  description: "You choose any number of permanents and/or players that have counters (one at a time, " \
                               "then done); each gets one more counter of each kind already on it. `amount` (default " \
                               "1): how many times to proliferate.",
                  rules: %w[701.34a 122.1 122.6],
                  params: { "amount" => "amount (default 1)" },
                  example: { "proliferate" => {} }

        def self.keys = %w[amount if]
        def self.default_to = "you"

        def initialize(to:, params:, errors:, path:, targets_count: 0, results_count: 0)
          params = params.transform_keys(&:to_s)
          params["amount"] = 1 unless params.key?("amount")
          super
        end

        def to_s = "proliferate#{" #{amount} times" if amount != 1}"

        # Each round asks until "done" (or nothing is left to choose), then gives the counters.
        def run(engine, ctx, locals)
          unless locals["times"]
            return :done unless condition.nil? || condition.true?(engine, ctx)

            locals["times"] = amount_for(engine, ctx)
          end
          while locals["times"].positive?
            chosen = answers(locals).reject { it["type"] == "done" }.map { it["object"] }
            options = answers(locals).any? { it["type"] == "done" } ? [] : candidates(engine, chosen)
            return ask(engine, locals, ctx.controller, "Proliferate: choose a permanent or player", options + DONE) unless options.empty?

            chosen.each { give!(engine, ctx, it) }
            locals["times"] -= 1
            locals.delete("answers")
          end
          :done
        end

        DONE = [{ "type" => "done" }].freeze

        private

        # Permanents with a counter (battlefield order), then players with one (seat order).
        def candidates(engine, chosen)
          permanents = engine.state.battlefield.select { engine.object(it).counters.any? { |_, n| n.positive? } }
          players = engine.state.players.each_index.select { engine.player_counters(it).any? { |_, n| n.positive? } }
                          .map { Filters.player_ref(engine, it) }
          (permanents + players - chosen).map { { "type" => "choose", "object" => it } }
        end

        def give!(engine, ctx, ref)
          if (index = Filters.player_index(engine, ref))
            return engine.player_counters(index).each { |kind, n| engine.add_player_counters!(index, kind, 1) if n.positive? }
          end

          obj = engine.state.objects[ref]
          return unless obj&.zone == :battlefield

          obj.counters.select { |_, n| n.positive? }.each_key { engine.add_counters!(obj, it, 1, by_player: ctx.controller) }
        end
      end
    end
  end
end
