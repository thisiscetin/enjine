# frozen_string_literal: true

require_relative "crew"
require_relative "kicker"

module Enjine
  module Mechanics
    module Costs
      # The cost of teamwork N (CR 702.194a): "tap any number of creatures you control with total power N or
      # more", chosen like crew's (one `choose_cost` decision per creature, `done` once the total is enough).
      class Teamwork < Crew
        def to_s = "Tap any number of untapped creatures you control with total power #{power} or greater"
        def pay_chosen!(_engine, _object, _entries) = nil
      end
    end

    module Abilities
      # Teamwork N (CR 702.194a): "As an additional cost to cast this spell, you may tap any number of creatures
      # you control with total power N or more." It is announced like kicker (the `choose_kicker` decision) and
      # paid like additional costs (CR 601.2b, 601.2f-h). "If this spell was cast using teamwork" is the condition
      # `{"cast_with": "teamwork"}` (CR 702.194b); targets only for teamwork are `kicked_targets` (CR 702.194c).
      class Teamwork < Kicker
        primitive :ability, :teamwork,
                  description: "Teamwork N: as you cast this spell you may also tap any number of untapped creatures " \
                               "you control with total power N or more (the `choose_kicker` decision, then one " \
                               "`choose_cost` per creature). `{\"cast_with\": \"teamwork\"}` holds if you did; " \
                               "`kicked_targets` are its targets then.",
                  rules: %w[702.194a 702.194b 702.194c 601.2b 601.2f 601.2h],
                  params: { "power" => "integer >= 1 (the N of teamwork N)" },
                  example: { "teamwork" => { "power" => 4 } }

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[power], errors, path)
          new([Costs::Teamwork.new(Mechanics.integer_param(params, :power, errors, path, min: 1).to_i)].freeze)
        end

        def to_s = "Teamwork #{costs.first.power}"
      end
    end
  end
end
