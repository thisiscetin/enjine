# frozen_string_literal: true

module Enjine
  class Engine
    # The total cost of a spell or ability (CR 601.2f, 602.2b): the mana cost with X announced
    # (CR 107.3a, 601.2b), plus cost increases, minus cost reductions. It is determined after
    # targets are chosen and then locked in for payment.
    module Costs
      # The mana cost with X announced (CR 107.3a), plus cost increases, minus cost reductions.
      # Changes affect only the generic part (CR 118.7a) and can't take it below {0}. `targets`
      # nil means "not chosen yet": conditions about targets then count as met, so the result
      # is a lower bound on what casting can cost (an upper bound on affordability).
      def total_cost(index, cost, spell: nil, ability: nil, source: nil, x_value: 0, targets: nil)
        return nil if cost.nil?

        cost = cost.with_x(x_value)
        change = cost_change(index, spell, ability, source, targets)
        change.zero? ? cost : cost.with(generic: [cost.generic + change, 0].max)
      end

      # Net generic change: + increases - reductions, from the spell's own abilities ("this spell
      # costs {1} less"), the activated ability's own reduction, and static abilities of
      # permanents ("spells you cast cost {1} less").
      def cost_change(index, spell, ability, source, targets)
        if spell
          ctx = Mechanics::EffectContext.new(index, spell.id, spell.id, targets)
          own = chars(spell).abilities.sum do |inst|
            inst.ability.kind == :cost_reduction ? -inst.ability.reduction(self, ctx) : 0
          end
          own + cost_modifiers.sum { |perm, modifier| modifier.change_for(self, perm, spell, index) }
        elsif ability.respond_to?(:cost_reduction) && ability.cost_reduction
          -ability.cost_reduction.reduction(self, Mechanics::EffectContext.new(index, source, nil, targets))
        else
          0
        end
      end

      # [[permanent, CostModifier], ...] on the battlefield.
      def cost_modifiers
        state.battlefield.flat_map do |id|
          obj = object(id)
          chars(obj).abilities.filter_map { [obj, it.ability] if it.ability.kind == :cost_modifier }
        end
      end

      # The mana cost being paid, before X and cost changes (nil for a triggered ability).
      def base_cost(ctx)
        obj = object(ctx["object"])
        case ctx["kind"]
        when "spell" # plus additional costs and kicker (CR 601.2f); alternative costs (CR 118.9, Permissions)
          cost = ctx["method"] ? alternative_base_cost(ctx) : chars(obj).mana_cost
          cost && Mana.sum_costs([cost, *spell_extra_mana(obj, ctx["kicked"])])
        when "ability" then stack_ability(obj).mana_cost
        end
      end

      def frame_total_cost(ctx, x_value: ctx["x"].to_i, targets: ctx["targets"])
        obj = object(ctx["object"])
        spell = ctx["kind"] == "spell" ? obj : nil
        ability = ctx["kind"] == "ability" ? stack_ability(obj) : nil
        total = total_cost(ctx["player"], base_cost(ctx), spell: spell, ability: ability, source: ctx["source"],
                                                          x_value: x_value, targets: targets)
        harmonize_reduced(total, frame_harmonize_power(ctx)) # CR 702.180a (Engine::AltCasting)
      end

      # CR 601.2f: the total cost is determined once and locked in.
      def lock_total_cost!(ctx)
        ctx["remaining"] = remaining_hash(frame_total_cost(ctx))
      end

      # CR 601.2b: X is announced (once) before targets are chosen. True while waiting for it.
      def ask_x!(ctx)
        return false unless ctx["x"].nil? && base_cost(ctx)&.x_symbols.to_i.positive?

        ask!("kind" => "choose_x", "player" => ctx["player"], "max" => x_limit(ctx))
        true
      end

      # A {T} ability's own source can't pay for it.
      def payment_excluded_source(ctx)
        ctx["type"] == "cast" && ctx["kind"] == "ability" && needs_tap?(casting_ability) ? ctx["source"] : nil
      end

      # The largest X the player could pay for: the mana available beyond the rest of the cost.
      def x_limit(ctx)
        cost = frame_total_cost(ctx, x_value: 0, targets: nil)
        spare = mana_units(ctx["player"], payment_excluded_source(ctx), payment_purpose(ctx)).size - cost.mana_value
        [spare, 0].max / base_cost(ctx).x_symbols
      end

      # CR 601.2b / 107.3a: the value of X is announced; the spell or ability keeps it on the stack.
      def announce_x!(value)
        ctx = casting
        ctx["x"] = value
        object(ctx["object"]).x = value
        emit Events::XAnnounced.new(player: name(ctx["player"]), object: ctx["object"], value: value)
        ask!(nil)
      end
    end
    include Costs
  end
end
