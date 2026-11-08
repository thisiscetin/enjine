# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Moves each referenced permanent, or card in one of the class's other zones (a target card in a
      # graveyard, a card chosen from a hand), to a zone. A card that has left the zone it was in
      # (CR 400.7, 608.2b) isn't found any more, so it isn't moved.
      class ZoneEffect < Effect
        def self.keys = %w[to if]
        def self.zone = raise(NotImplementedError)
        def self.reason = name.split("::").last.downcase
        def self.from_zones = %i[battlefield graveyard]

        def apply(engine, ctx)
          movable(engine, ctx).each { move(engine, ctx, it) }
        end

        # The referenced objects that are permanents or cards in the zones this effect moves cards from.
        def movable(engine, ctx)
          refs(engine, ctx).select do |id|
            obj = engine.state.objects[id]
            obj && !obj.ability? && self.class.from_zones.include?(obj.zone)
          end
        end

        def move(engine, ctx, id)
          Linked.remember!(engine, ctx, id)
          engine.move!(id, self.class.zone, reason: self.class.reason)
        end
      end

      # Exile (CR 406, 701.13). `link`: the card is "exiled with" the source, for its linked abilities
      # (CR 607.2a). `until_source_leaves`: it returns once the source leaves the battlefield (CR 610.3).
      class Exile < ZoneEffect
        primitive :effect, :exile,
                  description: "Exile each referenced permanent, or card in a graveyard or hand. `link: true`: the cards " \
                               "are exiled with the source, for its \"exiled with\" abilities (the `exiled_with` selector). " \
                               "`until_source_leaves: true`: they return to the battlefield under their owners' control " \
                               "when the source leaves the battlefield; if it already has, nothing is exiled.",
                  rules: %w[406.1 701.13a 607.2a 406.6 610.3 610.3a 610.3b 610.3c],
                  params: { "to" => "selector", "link" => "boolean", "until_source_leaves" => "boolean" },
                  example: { "exile" => { "to" => { "target" => 0 } } }

        attr_reader :link, :until_leaves

        def self.keys = %w[to link until_source_leaves if]
        def self.zone = :exile
        def self.from_zones = %i[battlefield graveyard hand]

        def setup(params, errors, path)
          @link = Linked.flag(params, "link", errors, path)
          @until_leaves = Linked.flag(params, "until_source_leaves", errors, path)
        end

        def to_s = "exile#{" until the source leaves" if until_leaves}#{" (linked)" if link} → #{to}"

        # CR 610.3a-b: if the source has already left the battlefield, the object doesn't move.
        def apply(engine, ctx)
          return if until_leaves && !engine.state.battlefield.include?(ctx.source)

          super
        end

        def move(engine, ctx, id)
          fresh = super or return
          engine.link_exiled!(ctx.source, fresh.id) if link || until_leaves
          return unless until_leaves

          (engine.object(ctx.source).memory[Linked::UNTIL_LEAVES] ||= []) << fresh.id
        end
      end

      # Return to its owner's hand (CR 400.6).
      class ReturnToHand < ZoneEffect
        primitive :effect, :return_to_hand,
                  description: "Return each referenced permanent, or card in a graveyard or exile (\"target creature " \
                               "card from your graveyard\"), to its owner's hand.",
                  rules: %w[400.6 404.1 608.2b], params: { "to" => "selector" },
                  example: { "return_to_hand" => { "to" => { "target" => 0 } } }
        def self.zone = :hand
        def self.reason = "bounce"
        def self.from_zones = %i[battlefield graveyard exile]
      end

      # Tap permanents (CR 701.26).
      class TapEffect < Effect
        primitive :effect, :tap, description: "Tap each referenced permanent.", rules: %w[701.26a],
                                 params: { "to" => "selector" }, example: { "tap" => { "to" => { "target" => 0 } } }
        def self.keys = %w[to if]
        def apply(engine, ctx) = objects(engine, ctx).each { engine.tap!(engine.object(it)) unless engine.object(it).tapped }
      end

      # Untap permanents (CR 701.26).
      class UntapEffect < Effect
        primitive :effect, :untap, description: "Untap each referenced permanent.", rules: %w[701.26b],
                                   params: { "to" => "selector" }, example: { "untap" => { "to" => "self" } }
        def self.keys = %w[to if]
        def apply(engine, ctx) = objects(engine, ctx).each { engine.untap!(engine.object(it)) }
      end

      # Mill N cards (CR 701.17).
      class Mill < Effect
        primitive :effect, :mill, description: "Each referenced player puts the top `amount` cards of their library " \
                                               "into their graveyard (default: you).",
                                  rules: %w[701.17a], params: { "amount" => "integer", "to" => "selector" },
                                  example: { "mill" => { "amount" => 2, "to" => "each_opponent" } }
        def self.default_to = "you"

        def apply(engine, ctx)
          players(engine, ctx).each do |index|
            engine.player(index).library.first(amount_for(engine, ctx)).each { engine.move!(it, :graveyard, reason: "mill") }
          end
        end
      end

      # Base for effects that ask the controller (or a referenced player) questions while resolving.
      # Progress lives in `locals` (plain data in the resolve frame), so they survive export/import.
      class ChoiceEffect < Effect
        def ask(engine, locals, player, prompt, choices)
          locals["asked"] = true
          engine.ask!("kind" => "effect_choice", "player" => player, "prompt" => prompt, "choices" => choices)
          :wait
        end

        def answers(locals) = locals["answers"] ||= []
      end

      # Scry N / surveil N (CR 701.22, 701.25): look at the top N, put each on the top or away
      # (bottom / graveyard), then order the ones kept on top.
      class LookAtTop < ChoiceEffect
        def self.default_to = "you"
        def self.away = raise(NotImplementedError)

        def run(engine, ctx, locals)
          index = ctx.controller
          seen = (locals["seen"] ||= engine.player(index).library.first(amount_for(engine, ctx)))
          decided = answers(locals).reject { it["type"] == "order" }
          if decided.size < seen.size
            card = seen[decided.size]
            return ask(engine, locals, index, "#{self.class.primitive_name}: keep on top or #{self.class.away}?",
                       [{ "type" => "top", "object" => card }, { "type" => self.class.away, "object" => card }])
          end
          tops = decided.select { it["type"] == "top" }.map { it["object"] }
          order = answers(locals).select { it["type"] == "order" }.map { it["object"] }
          if tops.size - order.size > 1
            return ask(engine, locals, index, "Choose the next card to put on top (the first chosen ends up on top)",
                       (tops - order).map { { "type" => "order", "object" => it } })
          end
          place(engine, index, order + (tops - order), decided.reject { it["type"] == "top" }.map { it["object"] })
          :done
        end
      end

      # Scry N (CR 701.22).
      class Scry < LookAtTop
        primitive :effect, :scry, description: "Look at the top `amount` cards of your library; put any number on the " \
                                               "bottom and the rest on top in any order.",
                                  rules: %w[701.22a], params: { "amount" => "integer" }, example: { "scry" => { "amount" => 2 } }
        def self.away = "bottom"

        def place(engine, index, tops, bottoms)
          library = engine.player(index).library
          library.replace(tops + (library - tops - bottoms) + bottoms)
          engine.emit Events::LibraryReordered.new(player: engine.name(index), top: tops.size, bottom: bottoms.size)
        end
      end

      # Surveil N (CR 701.25).
      class Surveil < LookAtTop
        primitive :effect, :surveil, description: "Look at the top `amount` cards of your library; put any number into " \
                                                  "your graveyard and the rest on top in any order.",
                                     rules: %w[701.25a], params: { "amount" => "integer" },
                                     example: { "surveil" => { "amount" => 2 } }
        def self.away = "graveyard"

        def place(engine, index, tops, gone)
          library = engine.player(index).library
          library.replace(tops + (library - tops))
          gone.each { engine.move!(it, :graveyard, reason: "surveil") }
          engine.emit Events::LibraryReordered.new(player: engine.name(index), top: tops.size, bottom: 0)
        end
      end

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
