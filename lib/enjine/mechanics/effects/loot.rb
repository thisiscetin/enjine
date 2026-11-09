# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "Draw N cards, then discard N cards; then something for the nonland cards discarded": the shared
      # shape of connive (CR 701.50) and recruit (CR 701.70). The player draws, then chooses the discards one
      # `effect_choice` at a time (fewer if their hand runs out); the reward counts the nonland cards among
      # them by their card types as they were discarded.
      class Loot < ChoiceEffect
        def run(engine, ctx, locals)
          return :done unless locals.key?("queue") || condition.nil? || condition.true?(engine, ctx)

          queue = (locals["queue"] ||= loot_queue(engine, ctx))
          while (entry = queue.first)
            return :wait if loot(engine, locals, entry) == :wait

            reward(engine, ctx, entry, locals["nonland"])
            queue.shift
            %w[drawn nonland applied answers asked].each { locals.delete(it) }
          end
          :done
        end

        private

        def loot(engine, locals, entry)
          index = entry["player"]
          unless locals["drawn"]
            entry["n"].times { engine.draw!(index) }
            locals.merge!("drawn" => true, "nonland" => 0, "applied" => 0)
          end
          chosen = answers(locals)
          chosen.drop(locals["applied"]).each do |answer|
            locals["nonland"] += 1 unless engine.chars(answer["object"]).land?
            engine.move!(answer["object"], :graveyard, reason: "discard")
          end
          locals["applied"] = chosen.size
          hand = engine.player(index).hand
          return :done if chosen.size >= entry["n"] || hand.empty?

          ask(engine, locals, index, "Discard a card (#{entry["n"] - chosen.size} to go)",
              hand.map { { "type" => "discard", "object" => it } })
        end
      end

      # Connive / connive N (CR 701.50a, 701.50d): the permanent's controller draws N cards, then discards N
      # cards, then puts a +1/+1 counter on it for each nonland card discarded. A permanent that has left the
      # battlefield connives as it last existed: its last controller (here, the effect's controller) loots
      # and no counters are put (CR 701.50b). Connive 0 does nothing (CR 701.50e).
      class Connive < Loot
        primitive :effect, :connive,
                  description: "Each referenced permanent (default: this one) connives `amount` (default 1): its " \
                               "controller draws that many cards, then discards that many, then it gets a +1/+1 " \
                               "counter for each nonland card discarded.",
                  rules: %w[701.50a 701.50b 701.50d 701.50e],
                  params: { "amount" => "amount (default 1)", "to" => "selector of permanents (default self)" },
                  example: { "connive" => { "to" => "self" } }

        def self.default_to = "self"

        def initialize(to:, params:, errors:, path:, targets_count: 0, results_count: 0)
          params = params.transform_keys(&:to_s)
          params["amount"] = 1 unless params.key?("amount")
          super
        end

        def to_s = "connive #{amount} → #{to}"

        private

        def loot_queue(engine, ctx)
          n = amount_for(engine, ctx)
          return [] unless n.positive?

          refs(engine, ctx).filter_map do |id|
            obj = engine.state.objects[id] or next
            { "player" => obj.zone == :battlefield ? obj.controller : ctx.controller, "n" => n, "object" => id }
          end
        end

        def reward(engine, _ctx, entry, nonland)
          perm = engine.state.objects[entry["object"]]
          engine.add_counters!(perm, "+1/+1", nonland, by_player: entry["player"]) if perm&.zone == :battlefield
        end
      end

      # Recruit (CR 701.70a): "Draw a card, then discard a card. If you discarded a nonland card this way,
      # create a 1/1 white Human Soldier creature token."
      class Recruit < Loot
        primitive :effect, :recruit,
                  description: "Each referenced player (default: you) recruits: draws a card, then discards a card; " \
                               "if a nonland card was discarded, they create a 1/1 white Human Soldier creature token.",
                  rules: %w[701.70a],
                  params: { "to" => "player selector (default you)" },
                  example: { "recruit" => {} }

        TOKEN = { "name" => "Human Soldier", "types" => ["creature"], "subtypes" => %w[human soldier], "colors" => ["W"],
                  "power" => 1, "toughness" => 1 }.freeze

        def self.keys = %w[to if]
        def self.default_to = "you"
        def self.token = @token ||= CardDefinition.token(TOKEN)

        def created_tokens = [Recruit.token]
        def to_s = "recruit → #{to}"

        private

        def loot_queue(engine, ctx) = players(engine, ctx).map { { "player" => it, "n" => 1 } }

        def reward(engine, _ctx, entry, nonland)
          engine.create_token!(Recruit.token, entry["player"]) if nonland.positive?
        end
      end
    end
  end
end
