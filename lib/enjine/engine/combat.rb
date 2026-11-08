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
      def eligible_attackers
        state.battlefield.select do |id|
          obj = object(id)
          obj.controller == state.active && !obj.tapped && chars(obj).creature? && !chars(obj).keyword?(:defender) &&
            !attackers.key?(id) && !summoning_sick_for_tap?(obj)
        end
      end

      # CR 506.3, 508.1b: the defending player or a planeswalker they control.
      def attack_targets
        defender = defending_player
        [Mechanics::Filters.player_ref(self, defender)] +
          state.battlefield.select { |id| object(id).controller == defender && chars(id).planeswalker? }
      end

      def declare_attacker!(id, target)
        attackers[id] = { "target" => target, "blocked" => false }
        state.attacks_declared += 1
        emit Events::AttackerDeclared.new(object: id, target: target)
        eligible_attackers.empty? ? finish_attackers! : nil
      end

      # CR 508.1f: attacking creatures become tapped.
      def finish_attackers!
        attackers.each_key { |id| tap!(object(id)) unless chars(id).keyword?(:vigilance) } # CR 702.20b
        turn_based_actions_done!
      end

      # ---- declare blockers (CR 509) -----------------------------------------------

      def begin_declare_blockers!
        return turn_based_actions_done! if block_options.empty? || attackers.empty?

        ask!("kind" => "declare_blockers", "player" => defending_player)
      end

      def eligible_blockers
        state.battlefield.select do |id|
          obj = object(id)
          obj.controller == defending_player && !obj.tapped && chars(obj).creature? && !state.blockers.key?(id)
        end
      end

      def declare_blocker!(id, attacker)
        state.blockers[id] = attacker
        attackers[attacker]["blocked"] = true # CR 509.1h: stays blocked even if the blocker leaves
        emit Events::BlockerDeclared.new(object: id, attacker: attacker)
        turn_based_actions_done! if block_options.empty? && blocks_legal?
      end

      # CR 509.1b-c restrictions: flying (702.9b) / reach (702.17b).
      def can_block?(blocker, attacker)
        return true unless chars(attacker).keyword?(:flying)

        chars(blocker).keyword?(:flying) || chars(blocker).keyword?(:reach)
      end

      def block_options
        eligible_blockers.flat_map do |id|
          attackers.keys.filter_map { |attacker| [id, attacker] if can_block?(id, attacker) }
        end
      end

      # CR 702.111b: an attacker with menace can't be blocked by just one creature.
      def blocks_legal? = menace_violations.empty?

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

      # CR 510.1c-d / 702.19b: several blockers, or trample, means the attacking player divides damage.
      def needs_assignment?(id)
        return false unless attackers[id]["blocked"] && deals_damage_now?(id) && power(object(id)).positive?

        count = blockers_of(id).size
        count > 1 || (count == 1 && trample?(id))
      end

      def combat_damage_frame = state.frames.last

      # Steps the combat_damage frame: ask for the next point of damage to divide, or deal it all.
      def step_combat_damage!(frame)
        while (attacker = frame["queue"].first)
          assigned = frame["assigned"][attacker] ||= {}
          remaining = power(object(attacker)) - assigned.values.sum
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
        needed = chars(attacker).keyword?(:deathtouch) ? 1 : toughness(object(blocker)) - object(blocker).damage
        assigned.fetch(blocker, 0) >= [needed, 1].max
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

          amount = power(object(id))
          blockers = blockers_of(id)
          if !info["blocked"] then hits << [id, info["target"], amount]
          elsif blockers.empty? then hits << [id, info["target"], amount] if trample?(id) # CR 702.19e
          elsif assigned.key?(id) then assigned[id].each { |target, n| hits << [id, target, n] }
          else hits << [id, blockers.first, amount]
          end
        end
        state.blockers.each do |blocker, attacker|
          hits << [blocker, attacker, power(object(blocker))] if deals_damage_now?(blocker)
        end
        hits.each { |source, target, amount| deal_damage!(source, target, amount) }
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
