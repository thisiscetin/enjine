# frozen_string_literal: true

module Enjine
  module Mechanics
    module Keywords
      # Power-up (CR 702.193): "Power-up — [Cost]: [Effect]" is an activated ability written with
      # `"power_up": true` (Abilities::ActivatedAbility). It can be activated only once, and if its permanent
      # entered this turn its cost is reduced by the permanent's mana cost (CR 702.193a). Generic mana reduces
      # generic mana; colored and colorless mana reduce mana of the same type, and any excess reduces generic
      # mana (CR 702.193b, 118.7b-d). A hybrid symbol reduces by one of its halves (CR 118.7e): the half the cost
      # needs (a matching colored symbol, then a hybrid symbol that half can pay), otherwise one generic mana.
      module PowerUp
        module_function

        # The total cost of `ability` of `source` after the power-up reduction.
        def reduced(engine, cost, ability, source)
          return cost unless ability.respond_to?(:power_up?) && ability.power_up?

          obj = engine.state.objects[source]
          return cost unless obj && engine.entered_this_turn?(obj)

          mana_cost = engine.chars(obj).mana_cost
          mana_cost ? reduce(cost, mana_cost) : cost
        end

        # `cost` reduced by the mana cost `reduction` (CR 118.7).
        def reduce(cost, reduction)
          colored = cost.colored.dup
          hybrid = cost.hybrid.dup
          generic = cost.generic
          halves = reduction.colored.flat_map { |type, n| Array.new(n) { [type] } } + reduction.hybrid
          halves.each { generic -= 1 unless reduce_symbol!(colored, hybrid, it) }
          cost.with(generic: [generic - reduction.generic, 0].max, colored: colored.reject { |_, n| n.zero? }.freeze,
                    hybrid: hybrid.freeze)
        end

        # Takes one mana of one of `types` off the colored part, else a hybrid symbol one of them pays.
        def reduce_symbol!(colored, hybrid, types)
          type = types.find { colored.fetch(it, 0).positive? }
          return colored[type] -= 1 if type

          index = hybrid.index { it.intersect?(types) }
          index && hybrid.delete_at(index)
        end
      end
    end
  end
end
