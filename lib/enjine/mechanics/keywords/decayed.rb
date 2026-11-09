# frozen_string_literal: true

require_relative "prowess"

module Enjine
  module Mechanics
    module Keywords
      # Decayed (CR 702.147a): "This creature can't block" (Engine::Combat#eligible_blockers) and "When this
      # creature attacks, sacrifice it at end of combat." A decayed counter gives it too (CR 122.1b).
      class Decayed < Primitive
        primitive :keyword, :decayed,
                  description: "This creature can't block. When it attacks, sacrifice it at end of combat.",
                  rules: %w[702.147a 122.1b], example: { "keywords" => ["decayed"] }

        ABILITY = { "triggered" => { "when" => { "attacks" => {} },
                                     "effects" => [{ "delayed_trigger" => {
                                       "when" => { "step_begins" => { "step" => "end_of_combat", "whose" => "each" } },
                                       "watch" => "self", "effects" => [{ "sacrifice" => { "to" => "watched" } }]
                                     } }] } }.freeze

        def self.intrinsic_abilities = @intrinsic_abilities ||= [Keywords.ability_from_data(ABILITY, "decayed")].freeze
      end
    end
  end
end
