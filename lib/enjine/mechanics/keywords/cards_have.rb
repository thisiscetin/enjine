# frozen_string_literal: true

require_relative "alternative_costs"

module Enjine
  module Mechanics
    module Abilities
      # "Creature cards in your graveyard have sneak {3}{B}. You may cast creature spells from your graveyard using
      # their sneak abilities." (CR 611.3a, 604.1, 118.9): while this permanent is on the battlefield, its
      # controller's cards in `zone` matching `cards` have the keyword alternative cost `ability`, and it works from
      # that zone. Each is a cast method of Engine::AltCasting with `via: "alt:cards_have:<permanent>:<ref>"`.
      # (`grants_beam_me_up` is the same idea for beam me up, whose cost is each card's own mana cost.)
      class CardsHave < Primitive
        ZONES = %w[graveyard hand exile].freeze
        GRANTABLE = %i[flashback harmonize mayhem web_slinging sneak miracle].freeze

        primitive :ability, :cards_have,
                  description: "While this permanent is on the battlefield, cards you own in `zone` (graveyard " \
                               "(default), hand or exile) matching `cards` have the keyword alternative cost `ability` " \
                               "(flashback, harmonize, mayhem, web_slinging, sneak or miracle) and may be cast with it from " \
                               "that zone. Cast option `via: \"alt:cards_have:<permanent>:<ref>\"`.",
                  rules: %w[611.3a 604.1 118.9 601.2b 702.190a],
                  params: { "zone" => ZONES.join(" | "), "cards" => "card spec",
                            "ability" => "a keyword alternative cost, e.g. {\"sneak\": {\"cost\": \"{3}{B}\"}}" },
                  example: { "cards_have" => { "cards" => { "types" => ["creature"] },
                                               "ability" => { "sneak" => { "cost" => "{3}{B}" } } } }

        attr_reader :zone, :cards, :granted

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[zone cards ability], errors, path)
          zone = Mechanics.fetch_param(params, :zone) || "graveyard"
          errors << "#{path}.zone: must be one of #{ZONES.join(", ")}" unless ZONES.include?(zone)
          raw = Mechanics.fetch_param(params, :ability)
          granted = raw && Mechanics.build_entry(:ability, raw, errors, "#{path}.ability")
          unless granted.is_a?(AlternativeCost) && GRANTABLE.include?(granted.keyword.to_sym)
            errors << "#{path}.ability: must be one of #{GRANTABLE.join(", ")}"
            granted = nil
          end
          new(zone.to_sym, CardSpec.build(Mechanics.fetch_param(params, :cards), errors, "#{path}.cards"), granted)
        end

        def initialize(zone, cards, granted)
          super()
          @zone = zone
          @cards = cards
          @granted = granted
          freeze
        end

        def kind = :cards_have
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        # A granted keyword's own triggered ability (miracle's, Abilities::Miracle) belongs to this permanent's card.
        def linked_abilities = granted.respond_to?(:linked_abilities) ? granted.linked_abilities : []

        # Whether the card `obj` (owned by `index`, who controls this permanent) may be cast with the granted ability now.
        def functions?(engine, obj, index)
          !granted.nil? && obj.zone == zone && cards.match?(engine, obj) && granted.usable?(engine, obj, index)
        end

        def to_s = "#{cards.to_s.capitalize}s in your #{zone} have #{granted}"
      end
    end
  end
end
