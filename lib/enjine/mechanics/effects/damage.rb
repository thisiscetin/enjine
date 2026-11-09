# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Deal N damage (CR 120).
      class DealDamage < Effect
        primitive :effect, :deal_damage,
                  description: "Deal `amount` damage to each referenced creature, planeswalker or player. Damage to a " \
                               "player causes life loss; to a planeswalker removes loyalty counters; to a creature " \
                               "is marked until cleanup. {\"this_way\": n} naming it is the excess damage it dealt " \
                               "(beyond lethal damage, or a planeswalker's loyalty).",
                  rules: %w[120.3a 120.3c 120.3e 120.6 120.4a 120.10],
                  params: { "amount" => "integer", "to" => "selector" },
                  example: { "deal_damage" => { "amount" => 3, "to" => { "target" => 0 } } }

        # The excess damage it deals (beyond lethal damage to a creature, or a planeswalker's loyalty) is
        # what {"this_way": n} reads ("if excess damage was dealt this way", CR 120.4a, 120.10).
        def apply(engine, ctx)
          n = amount_for(engine, ctx)
          source = ctx.source || ctx.object
          refs(engine, ctx).each do |ref|
            lethal = engine.lethal_damage(source, ref)
            engine.record_amount!(engine.excess_damage(lethal, engine.deal_damage!(source, ref, n)))
          end
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
