# frozen_string_literal: true

require_relative "alternative_costs"

module Enjine
  module Mechanics
    module Abilities
      # Impending N—[cost] (CR 702.176a): "You may choose to pay [cost] rather than pay this spell's mana cost",
      # "If you chose to pay this permanent's impending cost, it enters with N time counters on it", "As long as
      # this permanent's impending cost was paid and it has a time counter on it, it's not a creature" and "At the
      # beginning of your end step, remove a time counter from this permanent". The alternative cost is a cast
      # option (`via: "alt:<ref>"`) that enters with the counters (the method's `enters_with`); the end step
      # trigger comes with the keyword; not being a creature is a layer 4 change of the permanent itself
      # (Engine::Characteristics#own_layers, CR 613.1d), which keeps applying even if it loses its abilities
      # later in the layer order (CR 613.6). `{"cast_with": "impending"}` holds for it.
      class Impending < AlternativeCost
        primitive :ability, :impending,
                  description: "Impending `amount`—`cost`: you may cast this card by paying `cost` rather than its " \
                               "mana cost. If you do, it enters with `amount` time counters, and while its impending " \
                               "cost was paid and it has a time counter on it, it isn't a creature. At the beginning of " \
                               "your end step, remove a time counter from it (a triggered ability that comes with the " \
                               "keyword). Cast option `via: \"alt:<ref>\"`; `{\"cast_with\": \"impending\"}` reads it.",
                  rules: %w[702.176a 118.9 601.2b 601.2f 601.2h 613.1d 613.6 122.6],
                  params: { "amount" => "integer >= 1: the time counters", "cost" => "mana cost string, or a list of costs" },
                  example: { "impending" => { "amount" => 4, "cost" => "{1}{G}{G}" } }

        END_STEP = { "triggered" => { "when" => { "step_begins" => { "step" => "end", "whose" => "your" } },
                                      "effects" => [{ "remove_counters" => { "counter" => "time", "amount" => 1,
                                                                             "to" => "self" } }] } }.freeze

        attr_reader :amount, :linked_abilities

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[amount cost], errors, path)
          amount = Mechanics.fetch_param(params, :amount)
          unless amount.is_a?(Integer) && amount.positive?
            errors << "#{path}.amount: must be a positive integer"
            amount = 1
          end
          new(read_costs(Mechanics.fetch_param(params, :cost), errors, path), path, errors, amount: amount)
        end

        # Whether `obj` is a permanent whose impending cost was paid and that has a time counter (CR 702.176a).
        def self.not_creature?(obj)
          obj.zone == :battlefield && obj.memory["cast_with"] == "impending" && obj.counters.fetch("time", 0).positive?
        end

        # "It's not a creature" as the permanent's own layer 4 change (Engine::Characteristics#own_layers, CR 613.1d),
        # applied before resolved effects that change its types: its card types without creature (losing its
        # creature types, CR 205.1a). Empty unless `not_creature?`.
        def self.effects(engine, obj)
          return [] unless not_creature?(obj)

          types = engine.catalog.fetch(obj.card).types - [:creature] # printed: this is the layer pass itself
          [{ "kind" => "set_types", "types" => types.map(&:to_s), "affected" => [obj.id] }]
        end

        def initialize(costs, path, errors, amount: 1)
          @amount = amount
          @linked_abilities = [Mechanics.build_entry(:ability, END_STEP, errors, "#{path}.end_step")].compact.freeze
          super(costs, path, errors)
        end

        def allowed_types = %i[artifact creature enchantment planeswalker]

        def method_for(ref, **)
          method = super
          method&.merge("enters_with" => { "time" => amount })
        end

        def to_s = "Impending #{amount}—#{costs.join(", ")}"
      end
    end
  end
end
