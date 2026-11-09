# frozen_string_literal: true

require_relative "../abilities/chosen_values"

module Enjine
  module Mechanics
    module Abilities
      # Riot's "as this enters" choice (CR 702.136a): "counter" (it enters with an additional +1/+1 counter) or
      # "haste". The choice is remembered like choose_option's ({"chosen": "haste"}).
      class RiotChoice < ChooseOption
        INSTANCE = new(%w[counter haste].freeze)

        def to_s = "as this enters, choose a +1/+1 counter or haste"
        def enters_for(answer) = answer[:option] == "counter" ? super.merge("counters" => { "+1/+1" => 1 }) : super
      end
    end

    module Keywords
      # Riot (CR 702.136a): "You may have this permanent enter with an additional +1/+1 counter on it. If you
      # don't, it gains haste." Only one "as this enters" choice of a permanent is supported.
      class Riot < Primitive
        primitive :keyword, :riot,
                  description: "As this permanent enters, its controller chooses an additional +1/+1 counter or haste " \
                               "(an enter_choice: `{type: \"option\", option: \"counter\" | \"haste\"}`).",
                  rules: %w[702.136a 614.12], example: { "keywords" => ["riot"] }

        HASTE = { "static" => { "affects" => "self", "if" => { "chosen" => "haste" }, "keywords" => ["haste"] } }.freeze

        def self.intrinsic_abilities
          @intrinsic_abilities ||= [Abilities::RiotChoice::INSTANCE, Keywords.ability_from_data(HASTE, "riot")].freeze
        end
      end
    end
  end
end
