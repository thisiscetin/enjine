# frozen_string_literal: true

module Enjine
  module Mechanics
    module Supertypes
      # Basic (CR 205.4c). Exempt from the four-copy deck limit.
      class Basic < Primitive
        primitive :supertype, :basic,
                  description: "Basic cards are exempt from the four-copies deck construction limit.",
                  rules: %w[205.4c 100.2a],
                  example: { "supertypes" => ["basic"] }

        def self.deck_limit_exempt? = true
      end
    end
  end
end
