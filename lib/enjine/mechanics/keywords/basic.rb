# frozen_string_literal: true

module Enjine
  module Mechanics
    module Keywords
      # Flash (CR 702.8): may be cast any time its controller could cast an instant.
      class Flash < Primitive
        primitive :keyword, :flash,
                  description: "You may cast this spell any time you could cast an instant.",
                  rules: %w[702.8a], example: { "keywords" => ["flash"] }
      end

      # Haste (CR 702.10): can attack and {T} the turn it comes under your control.
      class Haste < Primitive
        primitive :keyword, :haste,
                  description: "This creature can attack and use {T} abilities even if it hasn't been under your " \
                               "control continuously since your most recent turn began.",
                  rules: %w[702.10a 302.6], example: { "keywords" => ["haste"] }
      end
    end
  end
end
