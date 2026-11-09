# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Return to its owner's hand (CR 400.6).
      class ReturnToHand < ZoneEffect
        primitive :effect, :return_to_hand,
                  description: "Return each referenced permanent, spell (\"return target spell to its owner's hand\"), or " \
                               "card in a graveyard or exile (\"target creature " \
                               "card from your graveyard\"), to its owner's hand.",
                  rules: %w[400.6 404.1 608.2b], params: { "to" => "selector" },
                  example: { "return_to_hand" => { "to" => { "target" => 0 } } }
        def self.zone = :hand
        def self.reason = "bounce"
        def self.from_zones = %i[battlefield graveyard exile stack]
      end
    end
  end
end
