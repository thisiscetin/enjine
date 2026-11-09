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

      # "Deals 3 damage divided as you choose among one, two, or three targets" (CR 601.2d): the division was
      # announced as the spell or ability was put on the stack (its `divide` amount, at least one per target);
      # each target that is still legal is dealt its share (CR 608.2b).
      class DistributeDamage < Effect
        primitive :effect, :distribute_damage,
                  description: "Deal each legal target the damage assigned to it as the spell or ability was cast or " \
                               "put on the stack (its `divide` amount, at least one per target). {\"this_way\": n} " \
                               "naming it is the excess damage dealt.",
                  rules: %w[601.2d 608.2b 120.3 120.4a],
                  params: {},
                  example: { "distribute_damage" => {} }

        def self.keys = %w[if]
        def self.default_to = "you"

        def to_s = "deal the divided damage to the targets"

        def apply(engine, ctx)
          source = ctx.source || ctx.object
          excess = engine.object(ctx.object).memory.fetch("division", {}).sum do |ref, n|
            next 0 unless ctx.targets.flatten.include?(ref) # still a legal target (CR 608.2b)

            engine.excess_damage(engine.lethal_damage(source, ref), engine.deal_damage!(source, ref, n))
          end
          engine.record_amount!(excess)
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
