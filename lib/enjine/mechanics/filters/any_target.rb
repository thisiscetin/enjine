# frozen_string_literal: true

module Enjine
  module Mechanics
    module Filters
      # "Any target": a creature, player or planeswalker (CR 115.4).
      class AnyTarget < Filter
        primitive :filter, :any_target, description: "A creature, player or planeswalker (battles: later).",
                                        rules: %w[115.4], example: "any_target"
        def self.players?(_engine, index, _controller) = !index.nil?
        def self.match_object?(engine, object, controller) = CreatureOrPlaneswalker.match_object?(engine, object, controller)
      end
    end
  end
end
