# frozen_string_literal: true

module Enjine
  module Mechanics
    module Supertypes
      # Legendary (CR 205.4d). Subject to the legend rule (CR 704.5j).
      class Legendary < Primitive
        primitive :supertype, :legendary,
                  description: "If a player controls two or more legendary permanents with the same name, they choose " \
                               "one and put the rest into their owners' graveyards (the legend rule).",
                  rules: %w[205.4d 704.5j],
                  example: { "supertypes" => ["legendary"] }

        def self.deck_limit_exempt? = false
      end
    end
  end
end
