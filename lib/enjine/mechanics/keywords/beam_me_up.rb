# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # Beam me up [cost] (CR 702.196a): "You may cast this card from your graveyard if the
      # resulting spell is an instant or sorcery spell by paying [cost] and returning a creature you control
      # to its owner's hand rather than paying its mana cost" and "If the beam me up cost was paid, exile this
      # card instead of putting it anywhere else any time it would leave the stack." The creature is chosen
      # while casting (a `choose_cost` decision) and returned as the spell becomes cast (CR 601.2h).
      class BeamMeUp < Primitive
        primitive :ability, :beam_me_up,
                  description: "You may cast this instant or sorcery card from your graveyard for `cost` plus " \
                               "returning a creature you control to its owner's hand, instead of its mana cost. " \
                               "If you do, it's exiled whenever it would leave the stack. Offered as a cast option " \
                               "with `via: \"beam:<ref>\"`.",
                  rules: %w[702.196a 702.196b 118.9 601.2b 601.2f 601.2h],
                  params: { "cost" => "mana cost string, e.g. \"{3}{W}\"" },
                  example: { "beam_me_up" => { "cost" => "{3}{W}" } }

        attr_reader :cost

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost], errors, path)
          new(Mana.parse_cost(Mechanics.fetch_param(params, :cost), errors, "#{path}.cost") || Mana::Cost.new(generic: 0, colored: {}))
        end

        def initialize(cost)
          super()
          @cost = cost
          freeze
        end

        def kind = :beam_me_up
        def mana_ability? = false
        def allowed_types = %i[instant sorcery]
        def try_effects = []
        def to_s = "Beam me up #{cost}"
      end

      # A static ability of a permanent giving beam me up (CR 702.196a), during its controller's main phase,
      # to the instant and sorcery cards with a mana cost in their graveyard, each card's mana cost being its
      # beam me up cost. The permanent itself can't be returned to cast a spell this way (CR 702.196b).
      class GrantsBeamMeUp < Primitive
        primitive :ability, :grants_beam_me_up,
                  description: "While this permanent is on the battlefield, during your main phase each instant and " \
                               "sorcery card in your graveyard has beam me up with its mana cost as the beam me up " \
                               "cost; this permanent can't be the creature returned to cast a spell this way. " \
                               "Offered as a cast option with `via: \"beam_granted:<permanent>:<ref>\"`.",
                  rules: %w[702.196a 702.196b 604.1 611.3a],
                  example: "grants_beam_me_up"

        INSTANCE = new.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          INSTANCE
        end

        def kind = :grants_beam_me_up
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        def to_s = "During your main phase, each card in your graveyard has beam me up (its mana cost)"
      end
    end

    module Keywords
      # CR 702.196b: "If a creature can't be beamed up, its controller can't return it to its owner's hand to
      # pay the portion of a beam me up cost that requires them to return a creature." A flag like a keyword.
      class CantBeBeamedUp < Primitive
        primitive :keyword, :cant_be_beamed_up,
                  description: "This creature can't be returned to its owner's hand to pay a beam me up cost.",
                  rules: %w[702.196b], example: { "keywords" => ["cant_be_beamed_up"] }
      end
    end
  end
end
