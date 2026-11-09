# frozen_string_literal: true

module Enjine
  module Mechanics
    module Keywords
      # Extort (CR 702.101a): "Whenever you cast a spell, you may pay {W/B}. If you do, each opponent loses 1 life
      # and you gain life equal to the total life lost this way." Each instance triggers separately (CR 702.101b).
      # The life lost inside the payment is recorded on the payment (effect 0), so the gain reads it.
      class Extort < Primitive
        primitive :keyword, :extort,
                  description: "Whenever you cast a spell, you may pay {W/B}. If you do, each opponent loses 1 life " \
                               "and you gain life equal to the total life lost this way.",
                  rules: %w[702.101a 702.101b 118.12], example: { "keywords" => ["extort"] }

        ABILITY = { "triggered" => {
          "when" => { "cast" => { "controller" => "you" } },
          "effects" => [{ "pay" => { "mana" => "{W/B}",
                                     "then" => [{ "lose_life" => { "amount" => 1, "to" => "each_opponent" } }] } },
                        { "gain_life" => { "amount" => { "this_way" => 0 } } }]
        } }.freeze

        def self.intrinsic_abilities = @intrinsic_abilities ||= [Keywords.ability_from_data(ABILITY, "extort")].freeze
      end
    end
  end
end
