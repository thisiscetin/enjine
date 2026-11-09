# frozen_string_literal: true

module Enjine
  class Engine
    # Choices made while casting or activating, besides targets and mana (CR 601.2b-d, 601.2h, 602.2b):
    # kicker and other additional costs, how many modes, dividing an amount among targets, costs that
    # need a choice (tap or sacrifice a permanent, remove counters), and "activate only once each turn".
    module CastChoices
      # ---- additional costs of spells (CR 601.2b, 601.2f, 702.33) ----------------------------

      def spell_cost_abilities(obj, kind) = chars(obj).abilities.map(&:ability).select { it.kind == kind }

      # Mana the spell's additional costs add to its mana cost: mandatory ones, and kicker when kicked.
      def spell_extra_mana(obj, kicked)
        extra = spell_cost_abilities(obj, :additional_cost)
        extra += spell_cost_abilities(obj, :kicker) if kicked
        extra.map(&:mana_cost)
      end

      # CR 601.2f / 118.3: the spell's mandatory non-mana additional costs can be paid.
      def additional_costs_payable?(obj) = spell_cost_abilities(obj, :additional_cost).all? { it.payable?(self, obj) }

      # The costs being paid, in order: an ability's own costs; a spell's additional costs (and kicker's).
      def casting_costs(ctx)
        case ctx["kind"]
        when "ability" then stack_ability(object(ctx["object"])).costs
        when "spell"
          obj = object(ctx["object"])
          costs = spell_cost_abilities(obj, :additional_cost)
          costs += spell_cost_abilities(obj, :kicker) if ctx["kicked"]
          costs.flat_map(&:choosing_costs) + alt_cost_parts(obj, ctx["method"]) # Engine::AltCasting
        else []
        end
      end

      # CR 601.2b / 702.33a: true while waiting for the kicker announcement.
      def ask_kicker!(ctx)
        return false unless ctx["kind"] == "spell" && ctx["kicked"].nil?

        kicker = spell_cost_abilities(object(ctx["object"]), :kicker).first
        return ctx["kicked"] = false unless kicker

        ask!("kind" => "choose_kicker", "player" => ctx["player"], "cost" => kicker.costs.join(", "))
        true
      end

      # "Kick" when the kicked total could be paid (CR 118.3, 601.2f) and the kicked spell has targets;
      # "don't kick" when the spell has targets without it (CR 702.33g).
      def kicker_options
        ctx = casting
        obj = object(ctx["object"])
        spell = spell_ability_of(obj)
        kick = kicked_castable?(ctx["player"], obj)
        plain = ability_targetable?(spell, ctx["player"], obj.id)
        (kick ? [{ type: "kick" }] : []) + (plain ? [{ type: "no_kick" }] : [])
      end

      # Whether the spell could be cast kicked: kicker payable, the kicked total affordable and its
      # kicked targets (or normal ones) available.
      def kicked_castable?(index, obj)
        kicker = spell_cost_abilities(obj, :kicker).first or return false
        spell = spell_ability_of(obj)
        total = total_cost(index, Mana.sum_costs([chars(obj).mana_cost, *spell_extra_mana(obj, true)]), spell: obj)
        targetable = if spell.nil? || spell.modal?
                       ability_targetable?(spell, index,
                                           obj.id)
                     else
                       targets_available?(spell.targets_for([], kicked: true),
                                          index, obj.id)
                     end
        kicker.payable?(self, obj) && targetable && affordable?(index, total, nil, { "spell" => obj.id })
      end

      def announce_kicker!(kicked)
        casting["kicked"] = kicked
        ask!(nil)
      end

      # ---- modes (CR 700.2) ---------------------------------------------------------------------

      # [min, max], determined once as modes are first chosen.
      def mode_range(ctx, ability)
        ctx["choose"] ||= ability.choice_range(self, Mechanics::EffectContext.new(ctx["player"], ctx["source"] || ctx["object"],
                                                                                  ctx["object"], nil))
      end

      def modes_pending?(ctx, ability)
        min, max = mode_range(ctx, ability)
        chosen = ctx["modes"].size
        chosen < min || (chosen < max && !ctx["modes_done"] && !choosable_modes(ctx, ability).empty?)
      end

      # CR 601.2b / 700.2: modes still choosable (distinct, with legal targets, and for "choose one that
      # hasn't been chosen" not chosen before for this object).
      def choosable_modes(ctx, ability)
        modes = available_modes(ability, ctx["player"], ctx["object"], ctx["source"]) - ctx["modes"]
        modes - used_modes(ability, ctx["source"], ctx["ability"])
      end

      # Modes chosen before for this source's "choose one that hasn't been chosen" ability `ref`.
      def used_modes(ability, source, ref)
        return [] unless ability.extras.unchosen

        state.objects[source]&.memory&.dig("chosen_modes", ref) || []
      end

      def mode_options
        ctx = casting
        ability = casting_ability
        options = choosable_modes(ctx, ability).map { { type: "mode", mode: it } }
        ctx["modes"].size >= mode_range(ctx, ability).first ? options + [{ type: "done" }] : options
      end

      def choose_mode!(index)
        casting["modes"] << index
        ask!(nil)
      end

      def modes_done!
        casting["modes_done"] = true
        ask!(nil)
      end

      # ---- dividing among targets (CR 601.2d) ------------------------------------------------------

      # Each chosen target gets one; the rest is assigned one at a time when there's a choice.
      def ask_distribution!(ctx, ability)
        amount = ability&.extras&.divide or return false
        chosen = ctx["targets"].flatten.compact
        ctx["division"] ||= chosen.to_h { [it, 1] }
        left = amount - ctx["division"].values.sum
        return false unless left.positive? && chosen.any?

        if chosen.size == 1
          ctx["division"][chosen.first] += left
          return false
        end

        ask!("kind" => "distribute", "player" => ctx["player"], "left" => left)
        true
      end

      def distribute_options = casting["division"].keys.map { { type: "assign", target: it } }

      def distribute!(ref)
        casting["division"][ref] += 1
        ask!(nil)
      end

      # ---- costs that need a choice (CR 601.2h, 602.2b) -----------------------------------------

      # The index (in casting_costs) of the next cost that still needs a choice.
      def next_cost_choice(ctx, _ability = nil)
        made = (ctx["paid"] || []).group_by { it["cost"] }
        casting_costs(ctx).each_with_index.find do |cost, i|
          cost.respond_to?(:choices_needed) && !cost_chosen?(ctx, cost, i, made.fetch(i, []))
        end&.last
      end

      # A cost with a fixed number of choices is chosen once it has them; one of "any number" (crew, CR
      # 702.122a) says itself, given whether the player said they're done.
      def cost_chosen?(ctx, cost, index, entries)
        return entries.size >= cost.choices_needed unless cost.respond_to?(:chosen?)

        cost.chosen?(self, cost_payer(ctx), entries, ctx.fetch("costs_done", []).include?(index))
      end

      # Whether the player may stop choosing for the current cost ("any number", once enough is chosen).
      def cost_choice_finishable?
        ctx = casting
        return false if harmonize_pending?(ctx) || beam_choice_pending?(ctx)

        index = next_cost_choice(ctx)
        cost = casting_costs(ctx)[index]
        cost.respond_to?(:finishable?) && cost.finishable?(cost_entries(ctx, index))
      end

      def finish_cost_choice!
        ctx = casting
        (ctx["costs_done"] ||= []) << next_cost_choice(ctx)
        ask!(nil)
      end

      def ask_cost_choice!(ctx, cost)
        ask!("kind" => "choose_cost", "player" => ctx["player"], "cost" => cost.to_s)
        :wait
      end

      # The object a cost is paid for: the ability's source, or the spell itself.
      def cost_payer(ctx) = object(ctx["kind"] == "ability" ? ctx["source"] : ctx["object"])

      def cost_entries(ctx, index) = (ctx["paid"] || []).select { it["cost"] == index }

      def cost_choice_candidates
        ctx = casting
        return harmonize_options(ctx) if harmonize_pending?(ctx) # Engine::AltCasting
        return beam_choices(ctx).map { { object: it } } if beam_choice_pending?(ctx) # Engine::Permissions

        index = next_cost_choice(ctx)
        casting_costs(ctx)[index].choice_options(self, cost_payer(ctx), cost_entries(ctx, index))
      end

      # Records (and for tapping, pays) the chosen part of the cost (costs may be paid in any order,
      # CR 601.2h). Cancelling the cast untaps what was tapped (ctx "tapped").
      def choose_cost!(option)
        ctx = casting
        return choose_harmonize!(ctx, option[:object]) if harmonize_pending?(ctx) # Engine::AltCasting
        return choose_beam_creature!(option[:object]) if beam_choice_pending?(ctx) # Engine::Permissions

        index = next_cost_choice(ctx)
        entry = casting_costs(ctx)[index].choose!(self, option).merge("cost" => index)
        ctx["tapped"] << entry["object"] if entry["tapped"]
        (ctx["paid"] ||= []) << entry
        ask!(nil)
      end

      # As the spell or ability becomes cast: sacrifices and counter removals chosen earlier happen now.
      def pay_chosen_costs!(ctx)
        payer = state.objects[ctx["kind"] == "ability" ? ctx["source"] : ctx["object"]]
        casting_costs(ctx).each_with_index do |cost, i|
          cost.pay_chosen!(self, payer, cost_entries(ctx, i)) if cost.respond_to?(:pay_chosen!)
        end
        object(ctx["object"]).paid = Snapshot.deep_copy(ctx["paid"]) if ctx["paid"] # with what was sacrificed
      end

      # ---- once each turn (CR 602.5b) ----------------------------------------------------------

      def activations_this_turn(obj, ref)
        entry = obj.memory.dig("activations", ref)
        entry && entry["turn"] == state.turn ? entry["count"] : 0
      end

      def activation_allowed?(index, obj, ref, ability)
        return true unless ability.respond_to?(:restriction_met?)
        return false if ability.per_turn && activations_this_turn(obj, ref) >= ability.per_turn
        return false if ability.exhaust? && obj.memory.fetch("exhausted", []).include?(ref) # CR 702.177a

        ability.restriction_met?(self, index, obj.id)
      end

      # Kept on the source object, so the limit applies even if its controller changes (CR 602.5b). An exhaust
      # ability is remembered for as long as the object exists (CR 702.177a; a new object can again, CR 400.7).
      def record_activation!(ctx)
        source = state.objects[ctx["source"]] or return
        ability = chars(source).ability(ctx["ability"])
        (source.memory["exhausted"] ||= []) << ctx["ability"] if ability.respond_to?(:exhaust?) && ability.exhaust?
        return unless ability.respond_to?(:per_turn) && ability.per_turn

        (source.memory["activations"] ||= {})[ctx["ability"]] =
          { "turn" => state.turn, "count" => activations_this_turn(source, ctx["ability"]) + 1 }
      end

      # What was announced while casting stays with the spell or ability (CR 702.33d, 601.2d).
      def record_announcements!(obj, ctx)
        obj.memory["kicked"] = true if ctx["kicked"]
        obj.memory["division"] = ctx["division"].dup if ctx["division"]
        record_chosen_modes!(ctx, casting_ability)
      end

      # "Choose one that hasn't been chosen": the source remembers the modes chosen for it.
      def record_chosen_modes!(ctx, ability)
        return unless ability&.modal? && ability.extras.unchosen

        source = state.objects[ctx["source"]] or return
        ((source.memory["chosen_modes"] ||= {})[ctx["ability"]] ||= []).concat(ctx["modes"])
      end
    end
    include CastChoices
  end
end
