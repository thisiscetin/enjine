# frozen_string_literal: true

module Enjine
  module Mechanics
    module Filters
      # A creature on the battlefield.
      class Creature < Filter
        primitive :filter, :creature, description: "A creature on the battlefield.", rules: %w[115.1], example: "creature"
        def self.match_object?(engine, object, _controller) = type?(engine, object, :creature)
        def self.card_types = [:creature]
      end

      # A planeswalker on the battlefield.
      class Planeswalker < Filter
        primitive :filter, :planeswalker, description: "A planeswalker on the battlefield.", rules: %w[115.1],
                                          example: "planeswalker"
        def self.match_object?(engine, object, _controller) = type?(engine, object, :planeswalker)
        def self.card_types = [:planeswalker]
      end

      # A creature or planeswalker on the battlefield.
      class CreatureOrPlaneswalker < Filter
        primitive :filter, :creature_or_planeswalker, description: "A creature or planeswalker on the battlefield.",
                                                      rules: %w[115.1], example: "creature_or_planeswalker"
        def self.match_object?(engine, object, _controller)
          type?(engine, object, :creature) || type?(engine, object, :planeswalker)
        end
      end

      # A land on the battlefield.
      class Land < Filter
        primitive :filter, :land, description: "A land on the battlefield.", rules: %w[115.1], example: "land"
        def self.match_object?(engine, object, _controller) = type?(engine, object, :land)
        def self.card_types = [:land]
      end

      # An artifact on the battlefield.
      class Artifact < Filter
        primitive :filter, :artifact, description: "An artifact on the battlefield.", rules: %w[115.1], example: "artifact"
        def self.match_object?(engine, object, _controller) = type?(engine, object, :artifact)
        def self.card_types = [:artifact]
      end

      # Any permanent.
      class Permanent < Filter
        primitive :filter, :permanent, description: "Any permanent on the battlefield.", rules: %w[110.1],
                                       example: "permanent"
        def self.match_object?(_engine, _object, _controller) = true
      end
    end
  end
end
