# frozen_string_literal: true

require_relative "prowess"

module Enjine
  module Mechanics
    module Keywords
      # Persist (CR 702.79a): "When this permanent is put into a graveyard from the battlefield, if it had no -1/-1
      # counters on it, return it to the battlefield under its owner's control with a -1/-1 counter on it."
      # Undying (CR 702.93a) is the same with +1/+1 counters. The keyword stands for that triggered ability, so a
      # static or an effect granting it grants the ability too (CR 613.1f), and it looks back at the permanent as
      # it last existed (CR 603.10a: its counters then, and whether it had the keyword).
      class Persist < Primitive
        primitive :keyword, :persist,
                  description: "When this permanent dies, if it had no -1/-1 counters on it, return it to the " \
                               "battlefield under its owner's control with a -1/-1 counter on it.",
                  rules: %w[702.79a 603.10a 603.4], example: { "keywords" => ["persist"] }

        def self.counter = "-1/-1"

        def self.ability_data
          { "triggered" => { "when" => { "dies" => {} },
                             "if" => { "amount" => { "counters" => { "of" => "self", "kind" => counter } }, "at_most" => 0 },
                             "effects" => [{ "return_to_battlefield" => { "to" => { "triggering" => "object" },
                                                                          "counters" => { counter => 1 } } }] } }
        end

        def self.intrinsic_abilities = @intrinsic_abilities ||= [Keywords.ability_from_data(ability_data, primitive_name)].freeze
      end

      # Undying (CR 702.93a): persist's twin with +1/+1 counters.
      class Undying < Persist
        primitive :keyword, :undying,
                  description: "When this permanent dies, if it had no +1/+1 counters on it, return it to the " \
                               "battlefield under its owner's control with a +1/+1 counter on it.",
                  rules: %w[702.93a 603.10a 603.4], example: { "keywords" => ["undying"] }

        def self.counter = "+1/+1"
      end
    end
  end
end
