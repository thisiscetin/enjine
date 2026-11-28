# frozen_string_literal: true

require_relative "../costs/discard"

module Enjine
  module Mechanics
    module Costs
      # Cycling's "discard this card" (CR 702.29a): discards it like `discard_self` (a cycled card is discarded,
      # CR 702.29d), and the card in the graveyard remembers which hand object it was, so its own "when you cycle
      # this card" ability (the `cycles` trigger with `self: true`, CR 702.29c) knows it was the one cycled.
      class CycleSelf < DiscardSelf
        INSTANCE = new.freeze

        def pay!(engine, object)
          fresh = super
          fresh.memory["cycled_from"] = object.id if fresh
          fresh
        end
      end
    end

    module Abilities
      # Cycling and typecycling (CR 702.29): activated abilities that function only while the card
      # is in its owner's hand.
      #   {"cycling": {"cost": "{2}"}}                                   [cost], discard this card: draw a card
      #   {"cycling": {"cost": "{X}{G}{G}"}}                             X is announced as it's activated (CR 107.3)
      #   {"cycling": {"cost": [{"pay_life": 2}]}}                       a cost list: "Cycling—Pay 2 life"
      #   {"cycling": {"cost": "{2}", "for": {"subtypes": ["swamp"]}}}  ...: search for a Swamp card (typecycling)
      #   {"cycling": {"cost": "{2}", "for": {"supertypes": ["basic"], "types": ["land"]}}}   basic landcycling
      class Cycling < ActivatedAbility
        primitive :ability, :cycling,
                  description: "Cycling: pay `cost` and discard this card from your hand to draw a card. With `for` " \
                               "it is typecycling: instead search your library for a card matching `for`, reveal " \
                               "it, put it into your hand, then shuffle. `cost` is a mana cost string (it may hold " \
                               "{X}, announced as it's activated) or a list of costs (`[{\"pay_life\": 2}]`). \"When " \
                               "you cycle this card\" is a triggered ability with `zone: \"graveyard\"` and the trigger " \
                               "`{\"cycles\": {\"self\": true}}`; its X is the cycling ability's.",
                  rules: %w[702.29a 702.29b 702.29c 702.29d 702.29e 702.29f 113.6m 602.2a 107.3],
                  params: { "cost" => "mana cost string, e.g. \"{2}\" or \"{X}{G}{G}\", or a list of costs",
                            "for" => "optional card spec for typecycling (see search_library)" },
                  example: { "cycling" => { "cost" => "{2}", "for" => { "supertypes" => ["basic"], "types" => ["land"] } } }

        attr_reader :spec

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost for], errors, path)
          costs = (read_costs(Mechanics.fetch_param(params, :cost), errors, path) + [Costs::CycleSelf::INSTANCE]).freeze
          spec_data = Mechanics.fetch_param(params, :for)
          spec = spec_data.nil? ? nil : CardSpec.build(spec_data, errors, "#{path}.for")
          new(targets: [].freeze, effects: [effect_for(spec_data)].compact.freeze, costs: costs, sorcery: false, spec: spec)
        end

        # A mana cost string, or a list of costs that are paid from the hand along with the discard (no tapping,
        # sacrificing or exiling a permanent: the card is in the hand, CR 602.2b).
        def self.read_costs(raw, errors, path)
          case raw
          when nil then (errors << "#{path}.cost: required") && [Costs::ManaPayment.build("{0}", errors, "#{path}.cost")]
          when String then [Costs::ManaPayment.build(raw, errors, "#{path}.cost")]
          when Array
            errors << "#{path}.cost: must be a non-empty list of costs" if raw.empty?
            costs = StackAbility.parse_costs({ "cost" => raw }, errors, path)
            costs.each_with_index do |cost, i|
              next unless cost.is_a?(Costs::Tap) || Costs::LEAVING_SELF.include?(cost.class) || cost.respond_to?(:zone)

              errors << "#{path}.cost[#{i}]: can't be paid while this card is in your hand"
            end
            costs
          else (errors << "#{path}.cost: must be a mana cost string or a list of costs") && []
          end
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
          "#{name} #{costs[0...-1].join(", ")}"
        end
      end
    end
  end
end
