# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Discard N cards of the player's choice (CR 701.9), or at random (CR 701.9b).
      class Discard < ChoiceEffect
        primitive :effect, :discard, description: "Each referenced player discards `amount` cards of their choice " \
                                                  "(default: you). `random: true`: the cards are chosen at random " \
                                                  "(the game's random number generator), with no decision.",
                                     rules: %w[701.9a 701.9b], params: { "amount" => "integer", "to" => "selector",
                                                                         "random" => "boolean" },
                                     example: { "discard" => { "amount" => 1, "to" => "each_opponent" } }
        def self.keys = %w[amount to if random]
        def self.default_to = "you"

        def setup(params, errors, path) = @random = Mechanics.flag_param(params, :random, errors, path)
        def to_s = "#{super}#{" at random" if @random}"

        # CR 118.3: "you may discard a card" needs a card to discard.
        def possible?(engine, ctx) = players(engine, ctx).all? { engine.player(it).hand.size >= amount_for(engine, ctx) }

        def run(engine, ctx, locals)
          return discard_at_random(engine, ctx) if @random

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

        # CR 701.9b: no one chooses; each card is picked by the game's RNG (so a replay picks the same ones).
        def discard_at_random(engine, ctx)
          return :done unless condition.nil? || condition.true?(engine, ctx)

          n = amount_for(engine, ctx)
          players(engine, ctx).each do |index|
            hand = engine.player(index).hand
            picked = engine.state.rng.shuffle!(hand.dup).first(n)
            picked.each { engine.move!(it, :graveyard, reason: "discard") }
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
