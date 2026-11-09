# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # "Exile a card from your hand" / "Exile two cards from your hand" as a cost (CR 406.1, 601.2h,
      # 602.2b). The cards are chosen while casting or activating and exiled as it becomes cast; never the
      # card the ability belongs to.
      class ExileFromHand < CardsCost
        primitive :cost, :exile_from_hand,
                  description: "Exile `count` cards from your hand (default 1), chosen while casting or activating, " \
                               "exiled as the spell or ability becomes cast. `card` (a card spec) restricts which.",
                  rules: %w[406.1 601.2h 602.2b 118.3],
                  params: { "count" => "integer (default 1), or \"X\": the X announced",
                            "card" => "card spec, e.g. {\"types\": [\"creature\"]}" },
                  example: { "exile_from_hand" => { "count" => 1 } }

        def self.zone = :hand
        def to_s = "Exile #{cards_text} from your hand"
      end

      # "Exile a creature card from your graveyard" / "Exile two cards from your graveyard" as a cost (CR 406.1,
      # 601.2h): cards other than the one the ability belongs to, chosen while casting or activating.
      class ExileFromGraveyard < CardsCost
        primitive :cost, :exile_from_graveyard,
                  description: "Exile `count` cards from your graveyard (default 1), never this card, chosen while " \
                               "casting or activating and exiled as the spell or ability becomes cast. `card` (a card " \
                               "spec) restricts which.",
                  rules: %w[406.1 601.2h 602.2b 118.3],
                  params: { "count" => "integer (default 1), or \"X\": the X announced",
                            "card" => "card spec, e.g. {\"types\": [\"creature\"]}" },
                  example: { "exile_from_graveyard" => { "count" => 2 } }

        def self.zone = :graveyard
        def to_s = "Exile #{cards_text} from your graveyard"
      end
    end
  end
end
