# frozen_string_literal: true

module Enjine
  class Engine
    # Waterbend (CR 701.67, Costs::Waterbend): while a waterbend cost is part of what is being paid, each
    # untapped artifact or creature its payer controls may be tapped to pay {1} of it. Only the waterbend
    # cost's own generic mana can be paid that way (CR 701.67b), so the payment frame keeps how much is
    # left ("waterbend"), and affordability counts at most that many permanents (as generic-only mana units,
    # see ManaSources#mana_units). A purpose ({"spell" => id} or {"ability" => id}) carries the same number
    # under "waterbend". Paying the cost, however it was paid, is waterbending (CR 701.67c).
    module Waterbending
      WATERBEND = Mechanics::Costs::Waterbend

      # The generic mana tapping may pay among `costs`, with X announced.
      def waterbend_generic(costs, x_value = 0) = costs.grep(WATERBEND).sum { it.generic(x_value) }

      # A purpose's waterbend part for `costs` ({} when there is none).
      def waterbend_purpose(costs, x_value = 0)
        n = waterbend_generic(costs, x_value)
        n.positive? ? { "waterbend" => n } : {}
      end

      # The waterbend part of a spell's additional costs (and kicker's when kicked).
      def spell_waterbend(obj, kicked) = waterbend_purpose(spell_cost_list(obj, kicked))

      def spell_cost_list(obj, kicked)
        abilities = spell_cost_abilities(obj, :additional_cost)
        abilities += spell_cost_abilities(obj, :kicker) if kicked
        abilities.flat_map(&:costs)
      end

      # CR 601.2f: as the total cost is locked in, so is the waterbend cost's generic part.
      def lock_waterbend!(ctx)
        costs = case ctx["kind"]
                when "ability" then stack_ability(object(ctx["object"])).costs
                when "spell" then spell_cost_list(object(ctx["object"]), ctx["kicked"])
                else []
                end
        ctx["waterbend"] = waterbend_generic(costs, ctx["x"].to_i) if costs.any?(WATERBEND)
      end

      def waterbend_candidates(index, excluded = [])
        state.battlefield.select do |id|
          obj = object(id)
          c = chars(obj)
          obj.controller == index && !obj.tapped && !excluded.include?(id) && (c.creature? || c.type?(:artifact))
        end
      end

      # Generic-only mana units (an empty list of types) for the permanents that could be tapped, capped at the
      # waterbend generic. Mana sources are counted as sources instead.
      def waterbend_units(index, purpose, excluded = [])
        n = purpose&.[]("waterbend").to_i
        return [] unless n.positive?

        sources = all_mana_sources(index).map(&:first)
        Array.new([waterbend_candidates(index, excluded).count { !sources.include?(it) }, n].min) { [] }
      end

      # pay_cost options: `{type: "waterbend", object: id}` while generic mana of the waterbend cost is left.
      def waterbend_options
        frame = payment
        return [] unless frame["waterbend"].to_i.positive? && frame["remaining"]["generic"].positive?

        reserved = payment_reserved(frame)
        waterbend_candidates(frame["player"], reserved + [payment_excluded_source(frame)]).filter_map do |id|
          { type: "waterbend", object: id } if !frame["irreversible"] || waterbend_keeps_payable?(frame, reserved, id)
        end
      end

      def waterbend_keeps_payable?(frame, reserved, id)
        pl = player(frame["player"])
        payable_with?(frame.merge("waterbend" => frame["waterbend"] - 1), remaining_cost(after_paying(frame["remaining"], [:generic])),
                      pl.mana_pool.dup, reserved + [id], restricted: pl.restricted_mana)
      end

      # CR 701.67a: tapping the permanent pays {1}; cancelling untaps it.
      def waterbend!(id)
        frame = payment
        frame["remaining"] = after_paying(frame["remaining"], [:generic])
        frame["waterbend"] -= 1
        tap!(object(id))
        frame["tapped"] << id
        ask!(nil)
      end

      # CR 701.67c: paying a waterbend cost is waterbending, however it was paid.
      def waterbent!(frame)
        return unless frame.key?("waterbend")

        emit Events::KeywordAction.new(player: name(frame["player"]), action: "waterbend", amount: nil)
      end
    end

    include Waterbending
  end
end
