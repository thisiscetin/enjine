# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Discard N cards of the player's choice (CR 701.9).
      class Discard < ChoiceEffect
        primitive :effect, :discard, description: "Each referenced player discards `amount` cards of their choice " \
                                                  "(default: you).",
                                     rules: %w[701.9a 701.9b], params: { "amount" => "integer", "to" => "selector" },
                                     example: { "discard" => { "amount" => 1, "to" => "each_opponent" } }
        def self.default_to = "you"

        # CR 118.3: "you may discard a card" needs a card to discard.
        def possible?(engine, ctx) = players(engine, ctx).all? { engine.player(it).hand.size >= amount_for(engine, ctx) }

        def run(engine, ctx, locals)
          queue = (locals["players"] ||= players(engine, ctx).flat_map { |i| [i] * amount_for(engine, ctx) })
          chosen = answers(locals)
          apply_answers(engine, locals, chosen)
          while chosen.size < queue.size
            index = queue[chosen.size]
            hand = engine.player(index).hand
            return ask(engine, locals, index, "Discard a card", hand.map { { "type" => "discard", "object" => it } }) unless hand.empty?

            chosen << { "type" => "none" } # nothing left to discard
            locals["applied"] = chosen.size
          end
          :done
        end

        # Performs the discards chosen since the last step.
        def apply_answers(engine, locals, chosen)
          (locals["applied"] ||= 0).upto(chosen.size - 1) do |i|
            answer = chosen[i]
            engine.move!(answer["object"], :graveyard, reason: "discard") if answer["type"] == "discard"
          end
          locals["applied"] = chosen.size
        end
      end
    end
  end
end
