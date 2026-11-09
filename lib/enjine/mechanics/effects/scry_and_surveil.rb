# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Scry N / surveil N (CR 701.22, 701.25): look at the top N, put each on the top or away
      # (bottom / graveyard), then order the ones kept on top.
      class LookAtTop < ChoiceEffect
        def self.default_to = "you"
        def self.away = raise(NotImplementedError)

        def run(engine, ctx, locals)
          index = ctx.controller
          locals["amount"] ||= amount_for(engine, ctx)
          seen = (locals["seen"] ||= engine.player(index).library.first(locals["amount"]))
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
          performed!(engine, index, locals["amount"])
          :done
        end

        # CR 701.22b, 701.25c-d: scry or surveil N > 0 is an event once it's complete, even if the library
        # had fewer cards; "whenever you scry" triggers on it.
        def performed!(engine, index, amount)
          return unless amount.positive?

          engine.emit Events::KeywordAction.new(player: engine.name(index), action: self.class.primitive_name.to_s,
                                                amount: amount)
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
    end
  end
end
