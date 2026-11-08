# frozen_string_literal: true

module Enjine
  module Mechanics
    module Types
      # Land (CR 305). Played as a special action, never cast; one per turn.
      class Land < Primitive
        primitive :type, :land,
                  description: "A permanent played with the special action \"play a land\" (one per turn, " \
                               "main phase, empty stack). It has no mana cost.",
                  rules: %w[305.1 305.2 305.3 202.1a],
                  example: { "name" => "Forest", "types" => ["land"], "supertypes" => ["basic"],
                             "subtypes" => ["forest"] }

        def self.permanent? = true
        def self.playable_as_land? = true

        def self.validate(card, errors)
          errors << "mana_cost: lands have no mana cost (CR 202.1a)" if card.key?("mana_cost")
        end
      end
    end
  end
end
