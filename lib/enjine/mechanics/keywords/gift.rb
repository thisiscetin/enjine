# frozen_string_literal: true

require_relative "kicker"

module Enjine
  module Mechanics
    module Costs
      # The gift cost (CR 702.174a): "you may choose an opponent" — one `choose_cost` decision among the
      # opponents. As the spell becomes cast it remembers the chosen player ("gift"), who the gift goes to.
      class GiftOpponent
        def mana? = false
        def choices_needed = 1
        def payable?(engine, object) = !opponents(engine, object).empty?
        def opponents(engine, object) = engine.state.players.each_index.reject { it == object.controller }
        def choice_options(engine, object, _chosen) = opponents(engine, object).map { { object: Filters.player_ref(engine, it) } }
        def choose!(_engine, option) = { "object" => option[:object] }
        def pay_chosen!(_engine, object, entries) = object.memory["gift"] = entries.first&.fetch("object")
        def to_s = "Choose an opponent"
      end
    end

    module Abilities
      # Gift (CR 702.174a-b, k): "As an additional cost to cast this spell, you may choose an opponent." It is
      # announced like kicker (the `choose_kicker` decision), then the opponent is chosen (`choose_cost`). The
      # gift itself is ordinary card data: the effect, first in the spell's effects (CR 702.174j) or in an
      # "enters" trigger of a permanent, with `"if": {"cast_with": "gift"}` ("if the gift was promised") and the
      # selector "gift_recipient" for the chosen player. Targets only for a promised gift are `kicked_targets`
      # (CR 702.174m).
      class Gift < SpellCost
        primitive :ability, :gift,
                  description: "Gift: as you cast this spell you may promise a gift to an opponent you choose (the " \
                               "`choose_kicker` decision, then `choose_cost` for the opponent). `{\"cast_with\": " \
                               "\"gift\"}` holds if you did, and the selector \"gift_recipient\" is that player; write " \
                               "the gift as the spell's first effect (or an enters trigger) under that condition.",
                  rules: %w[702.174a 702.174b 702.174j 702.174k 702.174m 601.2b],
                  example: "gift"

        COST = Costs::GiftOpponent.new.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          new([COST].freeze)
        end

        def kind = :kicker
        def to_s = "Gift"
      end
    end
  end
end
