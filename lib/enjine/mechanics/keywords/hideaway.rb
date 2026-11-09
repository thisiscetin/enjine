# frozen_string_literal: true

require_relative "mobilize_and_firebending"

module Enjine
  module Mechanics
    module Abilities
      # Hideaway N (CR 702.75a): "When this permanent enters, look at the top N cards of your library. Exile one
      # of them face down and put the rest on the bottom of your library in a random order." Only its controller
      # may look at the exiled card. It's linked to the permanent (CR 607.2a): another of its abilities names it
      # with the selector "exiled_with", e.g. `cast_free` with `play: true` ("you may play the exiled card
      # without paying its mana cost").
      class Hideaway < NumberedTrigger
        primitive :ability, :hideaway,
                  description: "Hideaway `amount`: when this permanent enters, look at the top N cards of your library, " \
                               "exile one face down (linked: \"exiled_with\") and put the rest on the bottom in a random order.",
                  rules: %w[702.75a 406.3 607.2a],
                  params: { "amount" => "amount" },
                  example: { "hideaway" => { "amount" => 4 } }

        def self.expansion(amount)
          { "when" => { "enters" => {} },
            "effects" => [{ "dig" => { "amount" => amount, "put" => "exile", "face_down" => true, "link" => true } }] }
        end
      end
    end
  end
end
