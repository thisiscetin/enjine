# frozen_string_literal: true

module Enjine
  class Engine
    # Choosing between costs (Costs::OneOf, CR 601.2b): which of the listed costs will be paid is announced
    # while casting or activating, before X and the total cost (CR 601.2f, 602.2b). The cast frame keeps the
    # option chosen for each one_of, in order ("cost_options"); from then on the chosen cost stands in its place.
    # Before the cast begins, every combination is tried (`cost_variants`).
    module CostOptions
      ONE_OF = Mechanics::Costs::OneOf

      # Every way to pay `costs`: each one_of replaced by one of its options.
      def cost_variants(costs)
        costs.reduce([[]]) do |variants, cost|
          cost.is_a?(ONE_OF) ? variants.product(cost.options).map { |v, o| v + [o] } : variants.map { it + [cost] }
        end
      end

      # `costs` with the n-th one_of replaced by its option chosen[n]; one_ofs not announced yet are left out.
      def with_cost_options(costs, chosen)
        n = -1
        costs.filter_map do |cost|
          next cost unless cost.is_a?(ONE_OF)

          option = chosen[n += 1]
          option && cost.options[option]
        end
      end

      # The mana parts of a cost list, as one mana cost.
      def costs_mana(costs) = Mana.sum_costs(costs.select(&:mana?).map(&:mana_cost))

      # Whether some way of paying `costs` (on top of the mana cost `base`) is open to `index`: its other parts
      # payable for `payer` (CR 118.3) and the total cost affordable (CR 601.2f). The block turns the mana to pay
      # into the total cost.
      def cost_variant_affordable?(index, costs, payer, base, excluded, purpose)
        cost_variants(costs).any? do |variant|
          variant.reject(&:mana?).all? { it.payable?(self, payer) } &&
            affordable?(index, yield(Mana.sum_costs([base, costs_mana(variant)].compact)), excluded,
                        { **purpose, **waterbend_purpose(variant) })
        end
      end

      # The cost list of a cast frame, before the announced options are applied: an ability's costs, a spell's
      # additional costs (and kicker's when kicked).
      def frame_cost_list(ctx)
        case ctx["kind"]
        when "ability" then stack_ability(object(ctx["object"])).costs
        when "spell" then spell_cost_list(object(ctx["object"]), ctx["kicked"])
        else []
        end
      end

      def frame_costs(ctx) = with_cost_options(frame_cost_list(ctx), ctx["cost_options"] || [])

      # CR 601.2b: true while waiting for the choice of the next one_of.
      def ask_cost_option!(ctx)
        one_of = pending_one_of(ctx) or return false
        ask!("kind" => "choose_cost_option", "player" => ctx["player"], "costs" => one_of.option_texts)
        true
      end

      def pending_one_of(ctx) = frame_cost_list(ctx).grep(ONE_OF)[ctx.fetch("cost_options", []).size]

      # `{type: "cost_option", option: i}` for each option that could be paid: its own part payable (CR 118.3)
      # and the total cost with it affordable (CR 601.2f).
      def cost_option_options
        ctx = casting
        chosen = ctx.fetch("cost_options", [])
        pending_one_of(ctx).options.each_with_index.filter_map do |cost, i|
          { type: "cost_option", option: i } if cost_option_payable?(ctx.merge("cost_options" => chosen + [i]), cost)
        end
      end

      def cost_option_payable?(trial, cost)
        return false unless cost.mana? || cost.payable?(self, cost_payer(trial))

        bend = waterbend_generic(frame_costs(trial))
        purpose = payment_purpose(bend.positive? ? trial.merge("waterbend" => bend) : trial)
        affordable?(trial["player"], frame_total_cost(trial, x_value: 0, targets: nil), payment_excluded_source(trial), purpose)
      end

      def choose_cost_option!(option)
        ctx = casting
        (ctx["cost_options"] ||= []) << option
        ask!(nil)
      end
    end

    include CostOptions
  end
end
