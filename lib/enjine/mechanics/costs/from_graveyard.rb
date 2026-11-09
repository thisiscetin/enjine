# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # "Exile this card from your graveyard" / "Put this card from your graveyard on the bottom of your
      # library" as a cost: the ability functions only from the graveyard (CR 113.6m).
      class FromGraveyard < Primitive
        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          new
        end

        def mana? = false
        def zone = :graveyard
        def uses_source? = true
        def payable?(engine, object) = engine.player(object.owner).graveyard.include?(object.id)
      end

      # Exile this card from your graveyard (CR 406, 113.6m).
      class ExileSelfFromGraveyard < FromGraveyard
        primitive :cost, :exile_self_from_graveyard,
                  description: "Exile this card from your graveyard. An ability with this cost is activated from " \
                               "your graveyard.",
                  rules: %w[406.1 113.6m 602.2b 118.3],
                  example: "exile_self_from_graveyard"

        def pay!(engine, object) = engine.move!(object.id, :exile, reason: "cost")
        def to_s = "Exile this card from your graveyard"
      end

      # Put this card from your graveyard on the bottom of your library (CR 401, 113.6m).
      class BottomSelfFromGraveyard < FromGraveyard
        primitive :cost, :bottom_self_from_graveyard,
                  description: "Put this card from your graveyard on the bottom of your library. An ability with " \
                               "this cost is activated from your graveyard.",
                  rules: %w[401.1 113.6m 602.2b 118.3],
                  example: "bottom_self_from_graveyard"

        def pay!(engine, object) = engine.move!(object.id, :library, position: :bottom, reason: "cost")
        def to_s = "Put this card from your graveyard on the bottom of your library"
      end
    end
  end
end
