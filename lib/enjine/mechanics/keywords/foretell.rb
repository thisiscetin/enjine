# frozen_string_literal: true

require_relative "alternative_costs"

module Enjine
  module Mechanics
    module Abilities
      # Foretell (CR 702.143a-b): any time its owner has priority during their turn, they may pay {2} and exile
      # the card from their hand face down (a special action, `{type: "special_action", object: id, ability:
      # ref}`, CR 116.2h). They may look at it while it remains exiled, and cast it after that turn has ended by
      # paying its foretell cost rather than its mana cost (cast option `via: "alt:<ref>"`, an alternative cost).
      class Foretell < AlternativeCost
        primitive :ability, :foretell,
                  description: "Foretell: during your turn, you may pay {2} and exile this card from your hand face down " \
                               "(special action `{type: \"special_action\"}`). After that turn you may cast it from " \
                               "exile by paying `cost` rather than its mana cost (cast option `via: \"alt:<ref>\"`). " \
                               "`{\"cast_with\": \"foretell\"}` reads it.",
                  rules: %w[702.143a 702.143b 702.143c 116.2h 406.3 118.9 601.2b 601.2f 601.2h],
                  params: { "cost" => "mana cost string, or a list of costs" },
                  example: { "foretell" => { "cost" => "{2}{R}" } }

        FORETELL_COST = Mana::Cost.parse("{2}")

        def zone = :exile

        # CR 702.143a: a card foretold on an earlier turn (the exiled card remembers the turn).
        def functions?(engine, obj, _index)
          turn = obj.zone == :exile && obj.memory["foretold"]
          turn ? engine.state.turn > turn : false
        end

        # ---- the special action (Actions::SpecialAction) ----

        def special_cost = FORETELL_COST
        def special_allowed?(engine, obj, index) = obj.zone == :hand && engine.state.active == index

        # Exiled face down; its owner may look at it (CR 702.143a, 406.3).
        def special!(engine, obj, index)
          fresh = engine.move!(obj.id, :exile, reason: "foretell", face_down: [index])
          fresh.memory["foretold"] = engine.state.turn if fresh
        end
      end
    end
  end
end
