# frozen_string_literal: true

module Enjine
  module Mechanics
    module Keywords
      # Builds the ability a keyword stands for from its card-DSL form, so it behaves exactly like the same
      # ability printed on a card. The data is fixed, so an error here is a bug.
      def self.ability_from_data(data, keyword)
        errors = []
        ability = Mechanics.build_entry(:ability, data, errors, "keyword:#{keyword}")
        raise ArgumentError, errors.join("; ") unless errors.empty?

        ability
      end

      # Prowess (CR 702.108a): "Whenever you cast a noncreature spell, this creature gets +1/+1 until end of
      # turn." An effect that grants prowess grants this triggered ability too (layer 6, CR 613.1f).
      class Prowess < Primitive
        primitive :keyword, :prowess,
                  description: "Whenever you cast a noncreature spell, this creature gets +1/+1 until end of turn.",
                  rules: %w[702.108a], example: { "keywords" => ["prowess"] }

        ABILITY = { "triggered" => { "when" => { "cast" => { "controller" => "you", "spell" => "noncreature" } },
                                     "effects" => [{ "pump" => { "power" => 1, "toughness" => 1, "to" => "self" } }] } }.freeze

        def self.intrinsic_abilities = @intrinsic_abilities ||= [Keywords.ability_from_data(ABILITY, "prowess")].freeze
      end
    end
  end
end
