# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # "Whenever you draw a card" (CR 121.2): once for each card drawn.
      class Draws < PlayerTrigger
        primitive :trigger, :draws,
                  description: "A player draws a card; triggers once per card (draws happen one at a time). " \
                               "`controller`: you (default) | opponent | any.",
                  rules: %w[121.1 121.2],
                  params: { "controller" => PLAYERS.join(" | ") },
                  example: { "draws" => { "controller" => "you" } }

        def event_class = Events::ZoneChanged

        def match?(engine, event, source)
          event.from == "library" && event.to == "hand" && event.reason == "draw" && player_ok?(engine, event.owner, source)
        end

        def to_s = "Whenever #{who} draw#{"s" unless @controller == "you"} a card"
      end

      # "Whenever you discard a card" / "one or more cards" (CR 701.9a). A cycled card is discarded too
      # (CR 702.29d).
      class Discards < PlayerTrigger
        include Batched
        include CardMatch

        primitive :trigger, :discards,
                  description: "A player (`controller`: you (default) | opponent | any) discards a card (optional `card` " \
                               "filter). `batched: true`: \"one or more cards\", once per event batch; then \"that many\" " \
                               "is how many were discarded.",
                  rules: %w[701.9a 603.2c 702.29d],
                  params: { "controller" => PLAYERS.join(" | "), "card" => "card filter", "batched" => "true | false" },
                  example: { "discards" => { "controller" => "you", "batched" => true } }

        def self.keys = %w[controller card batched]
        def event_class = Events::ZoneChanged

        def setup(params, errors, path)
          super
          setup_batched(params, errors, path)
          setup_card(params, errors, path)
        end

        def match?(engine, event, source)
          event.reason == "discard" && event.from == "hand" && player_ok?(engine, event.owner, source) && card_ok?(engine, event.card)
        end

        def to_s
          "Whenever #{who} discard#{"s" unless @controller == "you"} #{@batched ? "one or more #{card_words}s" : "a #{card_words}"}"
        end
      end

      # "Whenever you cycle a card" (CR 702.29a): a player activates a cycling (or typecycling) ability.
      class Cycles < PlayerTrigger
        include CardMatch

        primitive :trigger, :cycles,
                  description: "A player (`controller`: you (default) | opponent | any) cycles a card (activates its " \
                               "cycling or typecycling ability; optional `card` filter). `self: true`: \"when you " \
                               "cycle this card\", an ability of the card with `zone: \"graveyard\"` (where the cycled " \
                               "card is); its X is the cycling ability's X.",
                  rules: %w[702.29a 702.29c 702.29e 113.6k],
                  params: { "controller" => PLAYERS.join(" | "), "card" => "card filter", "self" => "true" },
                  example: { "cycles" => { "controller" => "you" } }

        def self.keys = %w[controller card self]
        def event_class = Events::AbilityActivated

        def setup(params, errors, path)
          super
          setup_card(params, errors, path)
          @self = params["self"] == true
          errors << "#{path}.self: must be true" unless params["self"].nil? || @self
        end

        def match?(engine, event, source)
          ability = engine.catalog.fetch(event.card).ability(event.ability)
          ability.respond_to?(:cycling?) && ability.cycling? && player_ok?(engine, event.player, source) &&
            card_ok?(engine, event.card) && (!@self || cycled_self?(engine, event, source))
        end

        # CR 702.29c: the source is the very card cycled (Costs::CycleSelf remembers the hand object it was).
        def cycled_self?(engine, event, source)
          engine.state.objects[source["id"]]&.memory&.[]("cycled_from") == event.source
        end

        def to_s
          return "When you cycle this card" if @self

          "Whenever #{who} cycle#{"s" unless @controller == "you"} a #{card_words}"
        end
      end
    end
  end
end
