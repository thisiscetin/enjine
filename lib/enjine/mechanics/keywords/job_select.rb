# frozen_string_literal: true

module Enjine
  module Mechanics
    module Keywords
      # Job select (CR 702.182a): "When this Equipment enters, create a 1/1 colorless Hero creature token,
      # then attach this Equipment to it."
      class JobSelect < Primitive
        primitive :keyword, :job_select,
                  description: "When this Equipment enters, create a 1/1 colorless Hero creature token, then " \
                               "attach this Equipment to it.",
                  rules: %w[702.182a], example: { "keywords" => ["job_select"] }

        HERO = { "name" => "Hero", "types" => ["creature"], "subtypes" => ["hero"], "colors" => [], "power" => 1,
                 "toughness" => 1 }.freeze
        ABILITY = { "triggered" => { "when" => { "enters" => {} },
                                     "effects" => [{ "create_token" => { "token" => HERO } },
                                                   { "attach" => { "to" => { "result" => 0 } } }] } }.freeze

        def self.intrinsic_abilities = @intrinsic_abilities ||= [Keywords.ability_from_data(ABILITY, "job_select")].freeze

        # CR 702.182a: only an Equipment can be attached this way.
        def self.validate(card, errors)
          errors << "keywords: job_select is only for Equipment" unless Array(card["subtypes"]).include?("equipment")
        end
      end
    end
  end
end
