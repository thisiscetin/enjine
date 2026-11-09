# frozen_string_literal: true

module Enjine
  class Engine
    # Casting spells (CR 601) and activating abilities (CR 602), one atomic decision
    # at a time: announce -> choose targets -> pay mana (tapping sources manually)
    # -> cast. Until every cost is paid the whole process can be cancelled and is
    # rewound (CR 734, "Handling Illegal Actions"). The in-progress context lives in
    # casting so a game can be exported mid-cast.
    module Casting
      # ---- what can be started ---------------------------------------------------

      def castable?(index, id)
        obj = object(id)
        defn = definition(obj)
        return false unless defn.castable?
        return false unless defn.instant_speed? || sorcery_timing?(index)
        return false if cast_forbidden?(index, obj) # CR 101.2 (Engine::Rules)
        return false unless additional_costs_payable?(obj) # CR 601.2f: e.g. "sacrifice a creature"

        cost = Mana.sum_costs([defn.mana_cost, *spell_extra_mana(obj, false)])
        if ability_targetable?(defn.spell_ability, index, id) &&
           affordable?(index, total_cost(index, cost, spell: obj), nil, { "spell" => id, **spell_waterbend(obj, false) })
          return true
        end

        kicked_castable?(index, obj) # CR 702.33g: only the kicked spell has legal targets
      end

      def activatable?(index, id, ability_ref)
        obj = object(id)
        ability = chars(obj).ability(ability_ref)
        return false unless ability && %i[activated loyalty].include?(ability.kind)
        return false unless obj.zone == ability.zone # CR 113.6: e.g. cycling only from the hand (702.29a)
        return false if ability.sorcery_speed? && !sorcery_timing?(index)
        return false if activation_forbidden?(index, obj) # CR 602.5, 101.2 (Engine::Rules)
        return false unless ability.costs.reject(&:mana?).all? { it.payable?(self, obj) }
        return false unless activation_allowed?(index, obj, ability_ref, ability) # CR 602.5b

        if (ability.kind == :loyalty) && (obj.loyalty_turn == state.turn || (loyalty(obj) + ability.loyalty_cost).negative?)
          # CR 606.3: once per turn. CR 118.3: a cost can't remove more counters than there are.
          return false
        end

        cost = total_cost(index, ability.mana_cost, ability: ability, source: id)
        purpose = { "ability" => id, **waterbend_purpose(ability.costs) } # CR 701.67a (Engine::Waterbending)
        ability_targetable?(ability, index, nil, id, ref: ability_ref) &&
          affordable?(index, cost, needs_tap?(ability) ? id : nil, purpose)
      end

      # Whether the ability can get legal targets: for modal abilities, enough modes must (CR 700.2),
      # not counting modes already chosen for the source of a "choose one that hasn't been chosen".
      def ability_targetable?(ability, index, exclude, source = nil, ref: nil)
        return true if ability.nil?
        return targets_available?(ability.targets, index, exclude, source) unless ability.modal?

        (available_modes(ability, index, exclude, source) - used_modes(ability, source, ref)).size >= ability.choose
      end

      def available_modes(ability, index, exclude, source = nil)
        ability.modes.each_index.select { targets_available?(ability.modes[it].targets, index, exclude, source) }
      end

      # "Up to one target" needs no candidate (CR 601.2c).
      def targets_available?(specs, index, exclude, source = nil)
        specs.all? do |spec|
          need = target_minimum(spec, index, source) # Engine::TargetCounts
          need.zero? || spec.candidates_for(self, index, source).count do
            it != exclude && targetable?(it, index, source, targeter: source || exclude) # a spell's card is `exclude`
          end >= need
        end
      end

      def optional_target?(spec) = spec.respond_to?(:optional?) && spec.optional?

      # CR 702.11b: hexproof permanents can't be targeted by their controller's opponents. `source`: the
      # permanent whose ability targets (nil for a spell); `targeter`: the spell, or the ability's source (protection,
      # CR 702.16b); see Engine::Rules#targeting_forbidden?.
      def targetable?(ref, index, source = nil, targeter: source)
        return false if targeting_forbidden?(ref, index, source, targeter: targeter) # CR 702.11c, 115.4

        obj = state.objects[ref]
        return true unless obj && obj.zone == :battlefield && obj.controller != index

        !chars(obj).keyword?(:hexproof)
      end

      # The ability an ability object on the stack represents. It keeps existing even if its
      # source has left the battlefield (CR 113.7a), so it's looked up on the source's card.
      def stack_ability(obj) = definition(obj).ability(obj.ability)

      def needs_tap?(ability) = ability.costs.any?(Mechanics::Costs::Tap)

      # The spell ability of a spell (printed, CR 113.3a).
      def spell_ability_of(obj) = definition(obj).spell_ability

      # ---- starting ----------------------------------------------------------------

      # CR 601.2a: the card moves from where it is to the stack. `via` names how a card outside the
      # hand is cast (see Engine::Permissions); "free" casts it without paying its mana cost during
      # the resolution of a spell or ability (CR 608.2g, 118.9), after which nobody gets priority.
      # `face`: cast another face of the card (a modal card's back, an Adventure, an Omen; Engine::Faces).
      def begin_cast!(index, card_id, via: nil, face: nil)
        return begin_outside_cast!(index, card_id, via) if outside_key?(card_id) # CR 400.11b

        card = object(card_id)
        method = via && play_method(index, card_id, via)
        origin = { "id" => card_id, "zone" => card.zone.to_s,
                   "index" => state.zone_list(card.zone, card.owner).index(card_id) }
        origin["memory"] = card.memory.slice("face_down", "may_look") if face_down?(card) # turned face up (CR 406.3a)
        origin["memory"] = card.memory.slice("prepared_for") if card.memory["prepared_for"] # a prepare spell (CR 723.3c)
        obj = move!(card_id, :stack, controller: index, reason: "cast")
        turn_spell_face!(obj, face) # CR 712.8b, 716.3b, 721.3b
        extra = method ? { "method" => method } : {}
        extra["no_priority"] = true if %w[free resolving].include?(via) # cast while resolving (CR 608.2g)
        start_casting!(index, obj.id, "spell", origin: origin, extra: extra)
      end

      # CR 602.2a: the ability is created on the stack.
      def begin_activation!(index, source_id, ability_ref)
        source = object(source_id)
        # CR 602.2a: activating from a hidden zone reveals the card.
        emit Events::CardRevealed.new(player: name(index), object: source_id, card: source.card) if source.zone == :hand
        card, ref = granted_origin(ability_ref) # a granted ability lives in the granting card's data
        obj = create_object(card || source.card, index, :stack)
        obj.kind = "ability"
        obj.source = source_id
        obj.ability = ref || ability_ref
        state.stack.unshift(obj.id)
        start_casting!(index, obj.id, "ability", source: source_id, ability: ability_ref)
      end

      # `x` stays nil until announced (CR 601.2b); `remaining` stays nil until the total cost is
      # determined and locked in after targets are chosen (CR 601.2f).
      def start_casting!(index, object_id, kind, origin: nil, source: nil, ability: nil, extra: {})
        state.frames << { "type" => "cast", "player" => index, "object" => object_id, "kind" => kind,
                          "origin" => origin, "source" => source, "ability" => ability, "targets" => [], "modes" => [],
                          "x" => nil, "remaining" => nil,
                          "pool" => player(index).mana_pool.transform_keys(&:to_s), "tapped" => [],
                          "restricted" => Snapshot.deep_copy(player(index).restricted_mana),
                          "triggers_before" => state.pending_triggers.map { it["id"] } }.merge(extra)
        ask!(nil) # advance! now steps the cast frame
      end

      # The cast/activation in progress (the top frame while a cast decision is pending).
      def casting
        frame = state.frames.last
        frame if frame && frame["type"] == "cast"
      end

      def casting_ability
        ctx = casting
        obj = object(ctx["object"])
        ctx["kind"] == "spell" ? definition(obj).spell_ability : stack_ability(obj)
      end

      # ---- the in-progress steps --------------------------------------------------

      # Steps the cast frame: modes and X (601.2b), targets (601.2c), total cost (601.2f), payment.
      def continue_casting!
        ctx = casting
        ability = casting_ability
        return :wait if ask_kicker!(ctx)

        if ability&.modal? && modes_pending?(ctx, ability)
          min, max = mode_range(ctx, ability)
          ask!({ "kind" => "choose_mode", "player" => ctx["player"], "choose" => max, "chosen" => ctx["modes"].size }
                 .merge(min == max ? {} : { "min" => min }))
          return :wait
        end
        return :wait if ask_x!(ctx)

        specs = casting_targets
        return :wait if ask_targets!(ctx, specs) # Engine::TargetCounts
        return :wait if ask_distribution!(ctx, ability)

        return ask_harmonize!(ctx) if harmonize_pending?(ctx) # CR 702.180b (Engine::AltCasting)

        lock_total_cost!(ctx) unless ctx["remaining"]
        if beam_choice_pending?(ctx) then ask_beam_choice!(ctx) # CR 702.196a (Engine::Permissions)
        elsif (cost = next_cost_choice(ctx)) then ask_cost_choice!(ctx, casting_costs(ctx)[cost])
        elsif remaining_left?(ctx["remaining"])
          ask!("kind" => "pay_cost", "player" => ctx["player"], "remaining" => remaining_text)
          :wait
        else
          finish_casting!
          :done
        end
      end

      def casting_targets = casting_ability&.targets_for(casting["modes"], kicked: casting["kicked"]) || []

      # CR 601.2c: targets, in order; a spell or ability can't target itself (CR 115.5), and the same
      # object can't be chosen twice for one instance of the word "target" (`distinct_from`).
      def target_candidates
        ctx = casting
        spec = casting_targets[target_slot(ctx)] # Engine::TargetCounts: a counted slot's list may be open
        taken = spec.respond_to?(:distinct_from) ? spec.distinct_from.flat_map { Array(ctx["targets"][it]) } : []
        taken += open_target_group(ctx)
        candidates = spec.candidates_for(self, ctx["player"], ctx["source"]).reject do
          it == ctx["object"] || taken.include?(it) || !targetable?(it, ctx["player"], ctx["source"],
                                                                    targeter: ctx["source"] || ctx["object"])
        end
        sharing_type(candidates, spec, ctx)
      end

      # "Target permanents that share a card type" (`shares_type_with`, CR 205.2a): only candidates sharing one
      # with the earlier target.
      def sharing_type(candidates, spec, ctx)
        index = spec.respond_to?(:shares_type_with) && spec.shares_type_with
        other = index && state.objects[Array(ctx["targets"][index]).first] or return candidates

        candidates.select { state.objects.key?(it) && chars(it).types.intersect?(chars(other).types) }
      end

      # The target options; an "up to one" target may be left unchosen (`done`).
      def target_options
        options = target_candidates.map { { type: "target", target: it } }
        optional_target?(casting_targets[casting["targets"].size]) && !casting["counting"] ? options + [{ type: "done" }] : options
      end

      # `ref` nil: no target chosen for an optional ("up to one") target. Abilities that trigger when
      # something becomes a target (ward, CR 702.21a) learn which spell or ability targeted it.
      def choose_target!(ref)
        ctx = casting
        add_chosen_target!(ctx, ref)
        if ref
          queued = state.pending_triggers.size
          emit Events::TargetChosen.new(player: name(ctx["player"]), object: ctx["object"], target: ref)
          state.pending_triggers.drop(queued).each { it["memory"] = it["memory"].merge("targeted_by" => ctx["object"]) }
        end
        ask!(nil)
      end

      # CR 601.2h-i / 602.2b: remaining costs are paid, the spell becomes cast.
      def finish_casting!
        ctx = casting
        index = ctx["player"]
        obj = object(ctx["object"])
        obj.targets = ctx["targets"].dup
        obj.modes = ctx["modes"].dup unless ctx["modes"].empty?
        obj.mana_spent = ctx["spent"].dup if ctx["spent"]
        record_announcements!(obj, ctx) # kicked (CR 702.33d), division (CR 601.2d), modes chosen before
        record_cast_choices!(obj, ctx) # cost choices; facing a dilemma (CR 700.17)
        waterbent!(ctx) # CR 701.67c (Engine::Waterbending)
        if ctx["kind"] == "trigger"
          emit Events::TriggerPutOnStack.new(player: name(index), object: obj.id, source: ctx["source"], card: obj.card,
                                             ability: ctx["ability"], targets: obj.targets.flatten)
          return # placing continues in the put_triggers frame; no priority yet
        elsif ctx["kind"] == "ability"
          pay_ability_costs!(ctx, obj)
          record_activation!(ctx) # CR 602.5b
          emit Events::AbilityActivated.new(player: name(index), object: obj.id, card: obj.card, source: ctx["source"],
                                            ability: ctx["ability"], targets: obj.targets.flatten)
        else
          finish_spell_cast!(ctx, obj)
        end
        return if ctx["no_priority"] # CR 608.2g: no priority; the resolving spell or ability continues

        action_taken!(index) # CR 117.3c (the frame is popped by advance!)
      end

      # A spell becomes cast (CR 601.2i) once its other costs are paid.
      def finish_spell_cast!(ctx, obj)
        casting_costs(ctx).each { it.pay!(self, obj) unless it.respond_to?(:choices_needed) } # pay life (CR 119.4)
        pay_chosen_costs!(ctx) # e.g. the creature sacrificed for an additional cost (CR 601.2h)
        finish_cast_method!(obj, ctx) # Engine::Permissions
        cast_prepared_copy!(ctx.dig("origin", "id")) # CR 723.3c (Engine::Faces)
        emit Events::SpellCast.new(player: name(ctx["player"]), object: obj.id, card: obj.card,
                                   targets: obj.targets.flatten, during_resolution: ctx["no_priority"] == true)
      end

      # The non-mana costs (CR 602.2b): its own ({T}, sacrifice it, exile it from the graveyard), then
      # the chosen ones (sacrifice another creature, remove counters). A source sacrificed as a cost is
      # remembered as it last existed (its counters, CR 608.2h).
      def pay_ability_costs!(ctx, obj)
        source = object(ctx["source"])
        ability = chars(source).ability(ctx["ability"])
        obj.memory["source_counters"] = source.counters.dup if ability.costs.any?(Mechanics::Costs::SacrificeSelf)
        ability.costs.reject(&:mana?).each { it.pay!(self, source) }
        pay_chosen_costs!(ctx)
        return unless ability.kind == :loyalty

        source.loyalty_turn = state.turn
        cost = ability.loyalty_cost
        cost.negative? ? remove_counters!(source, "loyalty", -cost) : add_counters!(source, "loyalty", cost)
      end

      # Rewinds an unfinished cast or activation (CR 734.1). Offered only while nothing irreversible
      # has been paid (see Engine::Payment#cancellable?): tapping is undone, mana abilities' mana
      # leaves the pool, and abilities that triggered meanwhile are dropped.
      def cancel_casting!
        ctx = casting
        index = ctx["player"]
        rewind_payment!(ctx)
        obj = object(ctx["object"])
        state.stack.delete(obj.id)
        state.objects.delete(obj.id)
        restore_to_origin!(obj, ctx["origin"]) if ctx["kind"] == "spell"
        emit Events::CastCancelled.new(player: name(index), object: obj.id, card: obj.card)
        state.frames.pop
        return ask!(nil) if ctx["no_priority"] # cast during resolution: the resolution goes on (CR 608.2g)

        give_priority!(index)
      end

      # (Costs that need a choice, e.g. tapping another creature: see Engine::CastChoices.)

      # As a spell or ability becomes cast, activated or put on the stack: it keeps the cost choices
      # (CR 702.184a uses the tapped creature's power), and chosen modes mean its controller faced a
      # dilemma (CR 700.17). Recording it here, not as modes are chosen, keeps a cancelled cast from counting.
      def record_cast_choices!(obj, ctx)
        obj.paid = ctx["paid"].map(&:dup) if ctx["paid"]
        emit Events::DilemmaFaced.new(player: name(ctx["player"]), object: obj.id, modes: obj.modes.dup) if obj.modes
      end
    end

    include Casting
  end
end
