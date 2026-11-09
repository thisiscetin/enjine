# frozen_string_literal: true

module Enjine
  module Mechanics
    module Filters
      # A card in a graveyard (CR 404): "target creature card from a graveyard" is
      # {"graveyard_card": {"any_of": ["creature"]}}; add "controller": "you" for "from your graveyard".
      class GraveyardCard < Filter
        primitive :filter, :graveyard_card,
                  description: "A card in a graveyard (any player's, in seat order; restrict with " \
                               "`controller` for its owner and `any_of`/`not` for its card types).",
                  rules: %w[404.1 115.1], example: { "graveyard_card" => { "any_of" => ["creature"] } }

        def self.zone = :graveyard
        def self.match_object?(_engine, object, _controller) = object.kind == "card"

        def self.candidates(engine, _controller)
          engine.state.players.flat_map(&:graveyard)
        end
      end
    end
  end
end
