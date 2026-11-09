# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Discard N cards of the player's choice (CR 701.9), at random (CR 701.9b), or the whole hand.
      class Discard < ChoiceEffect
        primitive :effect, :discard, description: "Each referenced player discards `amount` cards of their choice " \
                                                  "(default: you). `random: true`: the cards are chosen at random " \
                                                  "(the game's random number generator), with no decision. " \
                                                  "`hand: true`: each discards their whole hand at once (\"discard " \
                                                  "your hand\"; how many is its amount {\"this_way\": n}).",
                                     rules: %w[701.9a 701.9b], params: { "amount" => "integer", "to" => "selector",
                                                                         "random" => "boolean",
                                                                         "hand" => "true: the whole hand" },
                                     example: { "discard" => { "amount" => 1, "to" => "each_opponent" } }
        def self.keys = %w[amount to if random hand]
        def self.amount_optional?(params) = Mechanics.fetch_param(params, :hand) == true
        def self.default_to = "you"

        def setup(params, errors, path)
          @random = Mechanics.flag_param(params, :random, errors, path)
          @hand = Mechanics.flag_param(params, :hand, errors, path)
          errors << "#{path}: hand and random can't be combined" if @hand && @random
        end

        def to_s = @hand ? "discard the whole hand → #{to}" : "#{super}#{" at random" if @random}"

        # CR 118.3: "you may discard a card" needs a card to discard; a hand can always be discarded.
        def possible?(engine, ctx) = @hand || players(engine, ctx).all? { engine.player(it).hand.size >= amount_for(engine, ctx) }

        def run(engine, ctx, locals)
          return discard_at_random(engine, ctx) if @random
          return discard_hands(engine, ctx) if @hand

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

        # "Discard your hand" (CR 701.9a): all at once, no choice; how many were discarded is its amount.
        def discard_hands(engine, ctx)
          return :done unless condition.nil? || condition.true?(engine, ctx)

          players(engine, ctx).each do |index|
            cards = engine.player(index).hand.dup
            cards.each { engine.move!(it, :graveyard, reason: "discard") }
            engine.record_amount!(cards.size)
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
