# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # Cycling and typecycling (CR 702.29): activated abilities that function only while the card
      # is in its owner's hand.
      #   {"cycling": {"cost": "{2}"}}                                   [cost], discard this card: draw a card
      #   {"cycling": {"cost": "{2}", "for": {"subtypes": ["swamp"]}}}  ...: search for a Swamp card (typecycling)
      #   {"cycling": {"cost": "{2}", "for": {"supertypes": ["basic"], "types": ["land"]}}}   basic landcycling
      class Cycling < ActivatedAbility
        primitive :ability, :cycling,
                  description: "Cycling: pay `cost` and discard this card from your hand to draw a card. With `for` " \
                               "it is typecycling: instead search your library for a card matching `for`, reveal " \
                               "it, put it into your hand, then shuffle.",
                  rules: %w[702.29a 702.29b 702.29e 702.29f 113.6m 602.2a],
                  params: { "cost" => "mana cost string, e.g. \"{2}\"",
                            "for" => "optional card spec for typecycling (see search_library)" },
                  example: { "cycling" => { "cost" => "{2}", "for" => { "supertypes" => ["basic"], "types" => ["land"] } } }

        attr_reader :spec

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost for], errors, path)
          raw = Mechanics.fetch_param(params, :cost)
          mana = raw.nil? ? ((errors << "#{path}.cost: required") && "{0}") : raw
          costs = [Costs::ManaPayment.build(mana, errors, "#{path}.cost"), Costs::DiscardSelf::INSTANCE].freeze
          spec_data = Mechanics.fetch_param(params, :for)
          spec = spec_data.nil? ? nil : CardSpec.build(spec_data, errors, "#{path}.for")
          new(targets: [].freeze, effects: [effect_for(spec_data)].compact.freeze, costs: costs, sorcery: false, spec: spec)
        end

        # The ability's effect as card data, built like any other effect (errors in `for` are reported above).
        def self.effect_for(spec_data)
          data = if spec_data.nil?
                   { "draw" => { "amount" => 1 } }
                 else
                   { "search_library" => { "for" => spec_data, "reveal" => true } }
                 end
          Mechanics.build_entry(:effect, data, [], "cycling")
        end

        def initialize(spec:, **)
          @spec = spec
          super(**)
        end

        # CR 702.29f: typecycling abilities are cycling abilities.
        def cycling? = true

        def to_s
          name = spec ? "#{spec.to_s.delete_suffix(" card").capitalize}cycling" : "Cycling"
          "#{name} #{costs.first}"
        end
      end
    end
  end
end
