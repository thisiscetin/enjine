# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # Activated mana ability (CR 605). Resolves immediately, never uses the stack.
      class ManaAbility < Primitive
        primitive :ability, :mana,
                  description: "An activated mana ability: pay the cost, add the mana to your mana pool " \
                               "immediately. It does not use the stack and can be activated whenever you " \
                               "have priority.",
                  rules: %w[605.1a 605.3a 605.3b 106.4],
                  params: { "cost" => "list of costs (e.g. [\"tap\"])",
                            "produce" => "mana symbols added, e.g. \"{G}\" or \"{C}{C}\"" },
                  example: { "mana" => { "cost" => ["tap"], "produce" => "{C}" } }

        attr_reader :costs, :produce

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost produce], errors, path)
          raw_costs = Mechanics.fetch_param(params, :cost)
          costs = if raw_costs.is_a?(Array) && !raw_costs.empty?
                    raw_costs.each_with_index.map { |c, i| Mechanics.build_entry(:cost, c, errors, "#{path}.cost[#{i}]") }
                  else
                    errors << "#{path}.cost: must be a non-empty list"
                    []
                  end
          produce = Mana.parse_produce(Mechanics.fetch_param(params, :produce), errors, "#{path}.produce")
          new(costs.compact.freeze, produce)
        end

        def initialize(costs, produce)
          super()
          @costs = costs
          @produce = produce
          freeze
        end

        def mana_ability? = true
        def try_effects = []
        def kind = :mana
        def allowed_types = nil

        def activatable?(engine, object) = costs.all? { |c| c.payable?(engine, object) }

        def to_s = "#{costs.join(", ")}: Add #{produce.map { "{#{it}}" }.join}."
      end
    end
  end
end
