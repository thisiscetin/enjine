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

      # "Discard a card" / "Discard two cards" / "Discard a creature card" / "Discard a card at random" as a
      # cost (CR 701.9a-b, 601.2h): cards from your hand other than this one, chosen while casting or activating
      # and discarded as the spell or ability becomes cast. Random discards are paid last (CR 601.2h).
      class Discard < CardsCost
        primitive :cost, :discard,
                  description: "Discard `count` cards (default 1) from your hand, never this card, matching the card " \
                               "spec `card` if given: chosen while casting or activating and discarded as the spell " \
                               "or ability becomes cast. `random: true` discards them at random instead.",
                  rules: %w[701.9a 701.9b 601.2h 602.2b 118.3],
                  params: { "count" => "integer (default 1)", "card" => "card spec, e.g. {\"types\": [\"land\"]}",
                            "random" => "true: at random (CR 701.9b)" },
                  example: { "discard" => { "count" => 1 } }

        def self.keys = %w[count card random]
        def self.zone = :hand

        def initialize(filter, count, other, params, errors, path)
          @random = Mechanics.flag_param(params, :random, errors, path)
          super
        end

        def choices_needed = @random ? 0 : count

        def pay_chosen!(engine, object, entries)
          return super unless @random

          left = candidates(engine, object)
          [count, left.size].min.times { pay_card!(engine, left.delete_at(engine.state.rng.rand(left.size))) }
        end

        def pay_card!(engine, id) = engine.move!(id, :graveyard, reason: "discard")
        def to_s = "Discard #{cards_text}#{" at random" if @random}"
      end
    end
  end
end
