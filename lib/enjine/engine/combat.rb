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
          obj.controller == state.active && !obj.tapped && definition(obj).creature? &&
            !attackers.key?(id) && !summoning_sick_for_tap?(obj)
        end
      end

      # CR 506.3, 508.1b: the defending player or a planeswalker they control.
      def attack_targets
        defender = defending_player
        [Mechanics::Filters.player_ref(self, defender)] +
          state.battlefield.select { |id| object(id).controller == defender && definition(object(id)).planeswalker? }
      end

      def declare_attacker!(id, target)
        attackers[id] = { "target" => target, "blocked" => false }
        state.attacks_declared += 1
        emit Events::AttackerDeclared.new(object: id, target: target)
        eligible_attackers.empty? ? finish_attackers! : nil
      end

      # CR 508.1f: attacking creatures become tapped.
      def finish_attackers!
        attackers.each_key { |id| tap!(object(id)) }
        turn_based_actions_done!
      end

      # ---- declare blockers (CR 509) -----------------------------------------------

      def begin_declare_blockers!
        return turn_based_actions_done! if eligible_blockers.empty? || attackers.empty?

        ask!("kind" => "declare_blockers", "player" => defending_player)
      end

      def eligible_blockers
        state.battlefield.select do |id|
          obj = object(id)
          obj.controller == defending_player && !obj.tapped && definition(obj).creature? && !state.blockers.key?(id)
        end
      end

      def declare_blocker!(id, attacker)
        state.blockers[id] = attacker
        attackers[attacker]["blocked"] = true # CR 509.1h: stays blocked even if the blocker leaves
        emit Events::BlockerDeclared.new(object: id, attacker: attacker)
        turn_based_actions_done! if eligible_blockers.empty?
      end

      def blockers_of(attacker) = state.blockers.select { |_, a| a == attacker }.keys

      # ---- combat damage (CR 510) -----------------------------------------------

      # CR 510.1c: an attacker blocked by several creatures divides its damage among them
      # as its controller chooses — asked one point at a time.
      def begin_combat_damage!
        queue = attackers.keys.select { |id| blockers_of(id).size > 1 && power(object(id)).positive? }
        state.frames << { "type" => "combat_damage", "queue" => queue, "assigned" => {} }
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

      def assign_damage!(attacker, blocker)
        assigned = combat_damage_frame["assigned"][attacker]
        assigned[blocker] = assigned.fetch(blocker, 0) + 1
        emit Events::DamageAssigned.new(attacker: attacker, blocker: blocker)
        ask!(nil)
      end

      # CR 510.2: all combat damage is dealt simultaneously.
      def deal_combat_damage!(assigned)
        hits = []
        attackers.each do |id, info|
          amount = power(object(id))
          blockers = blockers_of(id)
          if !info["blocked"]
            hits << [id, info["target"], amount]
          elsif blockers.size == 1
            hits << [id, blockers.first, amount]
          else
            assigned.fetch(id, {}).each { |blocker, n| hits << [id, blocker, n] }
          end
        end
        state.blockers.each { |blocker, attacker| hits << [blocker, attacker, power(object(blocker))] }
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
        attackers.clear
        state.blockers.clear
      end
    end
    include Combat
  end
end
