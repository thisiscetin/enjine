# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Deal N damage (CR 120).
      class DealDamage < Effect
        primitive :effect, :deal_damage,
                  description: "Deal `amount` damage to each referenced creature, planeswalker or player. Damage to a " \
                               "player causes life loss; to a planeswalker removes loyalty counters; to a creature " \
                               "is marked until cleanup.",
                  rules: %w[120.3a 120.3c 120.3e 120.6],
                  params: { "amount" => "integer", "to" => "selector" },
                  example: { "deal_damage" => { "amount" => 3, "to" => { "target" => 0 } } }

        def apply(engine, ctx)
          n = amount_for(engine, ctx)
          refs(engine, ctx).each { engine.deal_damage!(ctx.source || ctx.object, it, n) }
        end
      end

      # "All damage already dealt to it is healed" / "remove all damage from it" (CR 120.6, 514.2).
      class RemoveDamage < Effect
        primitive :effect, :remove_damage,
                  description: "Remove all damage marked on each referenced permanent.",
                  rules: %w[120.6 514.2],
                  params: { "to" => "selector" },
                  example: { "remove_damage" => { "to" => { "target" => 0 } } }

        def self.keys = %w[to if]

        def apply(engine, ctx) = objects(engine, ctx).each { engine.remove_damage!(engine.object(it)) }
        def to_s = "remove all damage → #{to}"
      end
    end
  end
end
