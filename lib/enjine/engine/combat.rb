# frozen_string_literal: true

module Enjine
  class Engine
    # Combat (CR 506-511). state.attackers maps attacker id => {"target", "blocked"};
    # state.blockers maps blocker id => attacker id.
    module Combat
      def defending_player = state.opponent(state.active)

      # ---- declare attackers (CR 508) ------------------------------------------

      def begin_declare_attackers!
        return turn_based_actions_done! if eligible_attackers.empty?

        ask!("kind" => "declare_attackers", "player" => state.active)
      end

      # CR 508.1a: untapped creatures you've controlled continuously since your turn began (or with haste).
      # CR 508.1c: restrictions (defender, "can't attack", a player who can't attack) are obeyed.
      def eligible_attackers
        return [] if player_rule?(state.active, "cant_attack")

        state.battlefield.select do |id|
          obj = object(id)
          current = chars(obj)
          obj.controller == state.active && !obj.tapped && current.creature? &&
            (!current.keyword?(:defender) || current.keyword?(:attacks_despite_defender)) &&
            !current.keyword?(:cant_attack) && !attackers.key?(id) && !summoning_sick_for_tap?(obj)
        end
      end

      # CR 508.1d: creatures that attack each combat if able and could still be declared. The
      # declaration may end only once every such requirement is obeyed (no attack has a cost yet).
      def unmet_attack_requirements = attack_candidates.select { chars(it).keyword?(:attacks_each_combat) }

      # CR 506.3, 508.1b: the defending player or a planeswalker they control.
      def attack_targets
        defender = defending_player
        [Mechanics::Filters.player_ref(self, defender)] +
          state.battlefield.select { |id| object(id).controller == defender && chars(id).planeswalker? }
      end

      # Creatures that may be declared next. CR 506.5, 508.1c: one that can't attack alone is offered
      # only while another creature attacks or could still be declared.
      def attack_candidates
        eligible = eligible_attackers
        eligible.select { |id| !attacks_alone_restricted?(id) || !attackers.empty? || eligible.size > 1 }
      end

      def attacks_alone_restricted?(id) = chars(id).keyword?(:cant_attack_alone)

      # CR 508.1c: the declaration is illegal while a creature that can't attack alone attacks alone.
      def attack_declaration_legal? = !(attackers.size == 1 && attacks_alone_restricted?(attackers.keys.first))

      def declare_attacker!(id, target)
        attackers[id] = { "target" => target, "blocked" => false }
        state.attacks_declared += 1
        emit Events::AttackerDeclared.new(object: id, target: target)
        eligible_attackers.empty? && attack_declaration_legal? ? finish_attackers! : nil
      end

      # Undo one attack while the declaration isn't legal yet (CR 508.1c). The declaration it was part of
      # never happened, so "whenever this attacks" abilities it triggered go too.
      def withdraw_attacker!(id)
        attackers.delete(id)
        state.attacks_declared -= 1
        state.pending_triggers.reject! { it["event"]["type"] == "attacker_declared" && it["event"]["object"] == id }
      end

      # CR 508.4: a creature put onto the battlefield attacking attacks the defending player. (Choosing one
      # of their planeswalkers instead isn't offered yet.) It was never declared, so it never "attacked".
      # Only called while its controller controls an attacking creature (see Abilities::EntersAttacking).
      def enter_attacking!(obj, target = nil)
        target = Mechanics::Filters.player_ref(self, state.opponent(obj.controller)) unless target.is_a?(String) # CR 506.3a
        attackers[obj.id] = { "target" => target, "blocked" => false }
      end

      # CR 508.1f: attacking creatures become tapped. CR 508.3d: "whenever you attack" triggers
      # once the declaration is complete, if one or more creatures attack.
      def finish_attackers!
        attackers.each_key { |id| tap!(object(id)) unless chars(id).keyword?(:vigilance) } # CR 702.20b
        emit Events::AttacksDeclared.new(player: name(state.active), attackers: attackers.keys) unless attackers.empty?
        turn_based_actions_done!
      end

      # ---- declare blockers (CR 509) -----------------------------------------------

      def begin_declare_blockers!
        return turn_based_actions_done! if block_options.empty? || attackers.empty?

        ask!("kind" => "declare_blockers", "player" => defending_player)
      end

      # CR 509.1a; CR 509.1b: a creature that can't block is never offered.
      def eligible_blockers = able_blockers.reject { state.blockers.key?(it) }

      # The defending player's creatures that could block, whether they block already or not.
      def able_blockers
        state.battlefield.select do |id|
          obj = object(id)
          obj.controller == defending_player && !obj.tapped && chars(obj).creature? && !chars(obj).keyword?(:cant_block)
        end
      end

      def declare_blocker!(id, attacker)
        state.blockers[id] = attacker
        attackers[attacker]["blocked"] = true # CR 509.1h: stays blocked even if the blocker leaves
        emit Events::BlockerDeclared.new(object: id, attacker: attacker)
        finish_blockers! if block_options.empty? && blocks_legal?
      end

      # The declaration is final: each blocked attacker "becomes blocked" once (CR 509.1h, 509.3c, 603.2e).
      def finish_blockers!
        attackers.each do |id, info|
          emit Events::BecameBlocked.new(object: id, blockers: blockers_of(id)) if info["blocked"]
        end
        turn_based_actions_done!
      end

      # CR 509.1b restrictions: "can't be blocked", "can't be blocked by [quality] creatures", flying
      # (702.9b) / reach (702.17b).
      def can_block?(blocker, attacker)
        return false if chars(attacker).keyword?(:cant_be_blocked)
        return false if chars(attacker).abilities.any? { it.ability.kind == :cant_be_blocked_by && it.ability.forbids?(self, blocker) }
        return true unless chars(attacker).keyword?(:flying)

        chars(blocker).keyword?(:flying) || chars(blocker).keyword?(:reach)
      end

      def block_options
        eligible_blockers.flat_map do |id|
          attackers.keys.filter_map { |attacker| [id, attacker] if can_block?(id, attacker) }
        end
      end

      # CR 702.111b: an attacker with menace can't be blocked by just one creature.
      # CR 509.1c: an attacker that must be blocked if able is blocked whenever some creature could block it.
      def blocks_legal? = menace_violations.empty? && unmet_block_requirements.empty?

      # Attackers that must be blocked if able, unblocked while creatures could block them: blocking another
      # attacker instead obeys fewer requirements (CR 509.1c). With menace it takes two (CR 509.1b).
      def unmet_block_requirements
        attackers.keys.select do |id|
          next false unless chars(id).keyword?(:must_be_blocked) && blockers_of(id).empty?

          able_blockers.count { could_obey?(it, id) } >= (chars(id).keyword?(:menace) ? 2 : 1)
        end
      end

      # Whether `blocker` blocking `attacker` would obey more requirements: it can block it and blocks nothing,
      # or blocks an attacker without such a requirement (moving it from one that must be blocked gains nothing).
      def could_obey?(blocker, attacker)
        return false unless can_block?(blocker, attacker)

        blocking = state.blockers[blocker]
        blocking.nil? || !chars(blocking).keyword?(:must_be_blocked)
      end

      # Blocks to undo so a creature can block an attacker that must be blocked.
      def requirement_unblocks
        unmet_block_requirements.flat_map { |id| state.blockers.keys.select { could_obey?(it, id) } }.uniq
      end

      def menace_violations
        attackers.keys.select { |id| chars(id).keyword?(:menace) && blockers_of(id).size == 1 }
      end

      # Undo one block (offered while the declaration isn't legal yet).
      def remove_blocker!(id)
        attacker = state.blockers.delete(id)
        attackers[attacker]["blocked"] = blockers_of(attacker).any? # the declaration isn't final yet
      end

      def blockers_of(attacker) = state.blockers.select { |_, a| a == attacker }.keys

      # ---- combat damage (CR 510) -----------------------------------------------

      # CR 510.1c: an attacker blocked by several creatures divides its damage among them
      # as its controller chooses — asked one point at a time.
      # CR 510.4: if any attacking or blocking creature has first or double strike, there are
      # two combat damage steps: first strikers deal damage in the first, the rest in the second.
      def begin_combat_damage!
        state.combat_damage_pass ||= combatants.any? { first_striker?(it) } ? "first" : "regular"
        queue = attackers.keys.select { |id| needs_assignment?(id) }
        state.frames << { "type" => "combat_damage", "queue" => queue, "assigned" => {} }
      end

      def combatants = attackers.keys + state.blockers.keys

      def first_striker?(id) = chars(id).keyword?(:first_strike) || chars(id).keyword?(:double_strike)

      # Whether this creature deals combat damage in the current pass (CR 702.4b, 702.7b).
      def deals_damage_now?(id)
        case state.combat_damage_pass
        when "first" then first_striker?(id)
        when "regular_after_first" then !chars(id).keyword?(:first_strike) || chars(id).keyword?(:double_strike)
        else true
        end
      end

      # The second combat damage step follows a first-strike step (CR 510.4).
      def second_combat_damage_step?
        return false unless state.step == :combat_damage && state.combat_damage_pass == "first"

        state.combat_damage_pass = "regular_after_first"
        true
      end

      def trample?(id) = chars(id).keyword?(:trample)

      # CR 510.1a: the combat damage a creature assigns: its power, or its toughness when an effect says so
      # and its toughness is greater (assigns_damage_by_toughness).
      def combat_damage_amount(id)
        obj = object(id)
        amount = power(obj)
        chars(id).keyword?(:assigns_damage_by_toughness) ? [amount, toughness(obj)].max : amount
      end

      # CR 510.1c-d / 702.19b: several blockers, or trample, means the attacking player divides damage.
      def needs_assignment?(id)
        return false unless attackers[id]["blocked"] && deals_damage_now?(id) && combat_damage_amount(id).positive?

        count = blockers_of(id).size
        count > 1 || (count == 1 && trample?(id))
      end

      def combat_damage_frame = state.frames.last

      # Steps the combat_damage frame: ask for the next point of damage to divide, or deal it all.
      def step_combat_damage!(frame)
        while (attacker = frame["queue"].first)
          assigned = frame["assigned"][attacker] ||= {}
          remaining = combat_damage_amount(attacker) - assigned.values.sum
          if remaining.positive?
            ask!("kind" => "assign_damage", "player" => state.active, "attacker" => attacker, "remaining" => remaining)
            return :wait
          end
          frame["queue"].shift
        end
        deal_combat_damage!(frame["assigned"])
        :done
      end

      # Where the next point of an attacker's damage may go: any blocker; with trample, also
      # the player or planeswalker it attacks once every blocker has lethal damage assigned.
      def assignment_targets(attacker)
        blockers = blockers_of(attacker)
        assigned = combat_damage_frame["assigned"].fetch(attacker, {})
        return blockers unless trample?(attacker) && blockers.all? { lethal_assigned?(attacker, it, assigned) }

        blockers + [attackers[attacker]["target"]]
      end

      # CR 702.19b: lethal damage counts damage already marked; with deathtouch, 1 is lethal (702.2c).
      def lethal_assigned?(attacker, blocker, assigned)
        assigned.fetch(blocker, 0) >= [lethal_damage(attacker, blocker), 1].max
      end

      def assign_damage!(attacker, target)
        assigned = combat_damage_frame["assigned"][attacker]
        assigned[target] = assigned.fetch(target, 0) + 1
        emit Events::DamageAssigned.new(attacker: attacker, blocker: target)
        ask!(nil)
      end

      # CR 510.2: all combat damage in a step is dealt simultaneously.
      def deal_combat_damage!(assigned)
        hits = []
        attackers.each do |id, info|
          next unless deals_damage_now?(id)

          amount = combat_damage_amount(id)
          blockers = blockers_of(id)
          if !info["blocked"] then hits << [id, info["target"], amount]
          elsif blockers.empty? then hits << [id, info["target"], amount] if trample?(id) # CR 702.19e
          elsif assigned.key?(id) then assigned[id].each { |target, n| hits << [id, target, n] }
          else hits << [id, blockers.first, amount]
          end
        end
        state.blockers.each do |blocker, attacker|
          hits << [blocker, attacker, combat_damage_amount(blocker)] if deals_damage_now?(blocker)
        end
        simultaneous_damage do # CR 510.2
          dealt = Hash.new(0)
          lifelinked = hits.map(&:first).uniq.select { damage_source_chars(it)&.keyword?(:lifelink) }
          hits.each { |source, target, amount| dealt[source] += deal_damage!(source, target, amount, combat: true, lifelink: false) }
          lifelinked.each { lifelink!(it, dealt[it]) if dealt[it].positive? } # CR 120.3f, 119.9: one gain per source
        end
        turn_based_actions_done!
      end

      # CR 506.4: a permanent that leaves the battlefield is removed from combat.
      def leave_combat!(id)
        attackers.delete(id)
        state.blockers.delete(id)
        state.blockers.reject! { |_, attacker| attacker == id }
      end

      # CR 511.3: creatures stop being attacking/blocking at the end of combat.
      def end_combat!
        state.attacks_declared = 0
        state.combat_damage_pass = nil
        attackers.clear
        state.blockers.clear
      end
    end
    include Combat
  end
end
