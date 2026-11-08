# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # "Discard this card" as a cost (CR 701.9a, 602.2b). It moves the card out of its owner's
      # hand, so an ability with this cost functions only from the hand (CR 113.6m).
      class DiscardSelf < Primitive
        primitive :cost, :discard_self,
                  description: "Discard the card the ability belongs to (it goes from your hand to your graveyard). " \
                               "An ability with this cost is activated from your hand.",
                  rules: %w[701.9a 602.2b 113.6m 118.3],
                  example: "discard_self"

        INSTANCE = new.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          INSTANCE
        end

        def mana? = false
        def zone = :hand
        def payable?(engine, object) = engine.player(object.owner).hand.include?(object.id)
        def pay!(engine, object) = engine.move!(object.id, :graveyard, reason: "discard")
        def to_s = "Discard this card"
      end
    end
  end
end
