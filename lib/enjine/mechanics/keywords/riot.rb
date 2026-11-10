# frozen_string_literal: true

require_relative "../abilities/chosen_values"

module Enjine
  module Mechanics
    module Abilities
      # Riot's "as this enters" choice (CR 702.136a): "counter" (it enters with an additional +1/+1 counter) or
      # "haste": it gains haste as it enters (memory "riot_haste", see Engine::AbilityLayers), an effect that
      # stays when it later loses riot ("Other Spiders you control have riot" leaving).
      class RiotChoice < ChooseOption
        INSTANCE = new(%w[counter haste].freeze)

        def to_s = "as this enters, choose a +1/+1 counter or haste"

        def enters_for(answer)
          answer[:option] == "counter" ? { "counters" => { "+1/+1" => 1 } } : { "memory" => { "riot_haste" => true } }
        end
      end
    end

    module Keywords
      # Riot (CR 702.136a): "You may have this permanent enter with an additional +1/+1 counter on it. If you
      # don't, it gains haste." Each instance works separately (CR 702.136b); riot granted by a static ability
      # is chosen as the permanent enters too (CR 614.12, Engine::Entering#granted_entering_choices).
      class Riot < Primitive
        primitive :keyword, :riot,
                  description: "As this permanent enters, its controller chooses an additional +1/+1 counter or haste " \
                               "(an enter_choice: `{type: \"option\", option: \"counter\" | \"haste\"}`). Riot granted " \
                               "by a static ability (\"Other Spiders you control have riot\") is chosen as it enters too, " \
                               "and haste chosen this way stays if it later loses riot.",
                  rules: %w[702.136a 702.136b 614.12], example: { "keywords" => ["riot"] }

        def self.intrinsic_abilities = @intrinsic_abilities ||= [Abilities::RiotChoice::INSTANCE].freeze
      end
    end
  end
end
