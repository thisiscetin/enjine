# frozen_string_literal: true

module Enjine
  class Engine
    # State-based actions (CR 704) and the end of the game (CR 104).
    module StateBasedActions
      def check_state_based_actions!
        loop do
          check_player_state_based_actions!
          break if state.over? || !check_permanent_state_based_actions!
        end
      end

      def check_player_state_based_actions!
        state.players.each_with_index do |pl, i|
          next if pl.lost

          reason = if loses_for_life?(i) then "life" # CR 704.5a (unless an effect says otherwise)
                   elsif pl.drew_from_empty then "empty_library" # CR 704.5b
                   elsif pl.poison >= 10 then "poison" # CR 704.5c
                   elsif loses_to_commander_damage?(i) then "commander_damage" # CR 903.10a
                   end
          pl.drew_from_empty = false
          lose!(i, reason) if reason
        end
        end_game_if_decided!
      end

      def concede!(index)
        lose!(index, "concede") # CR 104.3a
        end_game_if_decided!
      end

      def lose!(index, reason)
        player(index).lost = reason
        emit Events::PlayerLost.new(player: name(index), reason: reason)
      end

      # CR 104.2a: last player standing wins; CR 104.4a: all players losing at once is a draw.
      def end_game_if_decided!
        return if state.over?

        losers = state.players.select(&:lost)
        return if losers.empty?

        survivors = state.players.reject(&:lost)
        winner = survivors.size == 1 ? survivors.first.name : nil
        reason = losers.map(&:lost).uniq.join(",")
        state.result = { "winner" => winner, "reason" => reason }
        ask!(nil)
        state.frames.clear
        reveal_face_down_at_end! # CR 708.9 (Engine::FaceDownPermanents)
        emit Events::GameEnded.new(winner: winner, reason: reason)
      end

      # CR 704.5d, 704.5f, 704.5g, 704.5i, 704.5m, 704.5n, 704.5q. All applicable actions happen
      # simultaneously (CR 704.3). Returns true when anything happened, so the check repeats.
      def check_permanent_state_based_actions!
        ceased = remove_tokens_outside_battlefield! # CR 704.5d
        ceased = annihilate_counters! || ceased # CR 704.5q
        ceased = unattach_illegal_attachments! || ceased # CR 704.5n, 704.5p
        ceased = start_engines! || ceased # CR 704.5aa (Engine::Speed)
        ceased = tell_enduring_stories! || ceased # CR 702.195a (Engine::Designations)
        doomed = nil
        state.battlefield.each do |id|
          obj = object(id)
          defn = chars(obj)
          reason = defn.creature? ? creature_sba(obj) : noncreature_sba(obj, defn)
          reason ||= "sba_aura" if illegal_aura?(obj) # CR 704.5m
          reason ||= "sacrifice" if saga_complete?(obj) # CR 704.5s: its controller sacrifices it
          (doomed ||= []) << [id, reason] if reason
        end
        return ceased unless doomed

        in_batch("sba:#{state.next_id}") do # CR 704.3, 603.2c, 603.10a: at once, one event batch
          simultaneously { doomed.each { |id, reason| move!(id, :graveyard, reason: reason) } }
        end
        true
      end

      # CR 704.5i: a planeswalker with 0 loyalty is put into its owner's graveyard; a battle, see #battle_sba.
      def noncreature_sba(obj, current)
        return "sba_loyalty" if current.planeswalker? && loyalty(obj) <= 0

        battle_sba(obj) if current.type?(:battle)
      end

      # CR 704.5v, 310.7: a battle with defense 0 is put into its owner's graveyard, unless it's the source of a
      # triggered ability that has triggered but not yet left the stack (a Siege's defeat trigger, CR 310.12).
      # CR 704.5x: a Siege its protector controls gets a new protector from among its controller's opponents (no
      # choice in a two-player game).
      def battle_sba(obj)
        obj.memory["protector"] = state.opponent(obj.controller) if protector(obj) == obj.controller && chars(obj).subtypes.include?(:siege)
        return nil if obj.counters.fetch("defense", 0).positive?

        waiting = state.pending_triggers.any? { it["source"] == obj.id } ||
                  state.stack.any? { (ability = object(it)).ability? && ability.source == obj.id && ability.memory.key?("trigger_id") }
        waiting ? nil : "sba_defense"
      end

      # CR 704.5q, 122.3: N +1/+1 and N -1/-1 counters are removed, N the smaller count.
      def annihilate_counters!
        hit = state.battlefield.filter_map do |id|
          obj = object(id)
          n = [obj.counters.fetch("+1/+1", 0), obj.counters.fetch("-1/-1", 0)].min
          [obj, n] if n.positive?
        end
        hit.each do |obj, n|
          remove_counters!(obj, "+1/+1", n)
          remove_counters!(obj, "-1/-1", n)
        end
        !hit.empty?
      end

      # CR 704.5d / 111.7: a token in a zone other than the battlefield ceases to exist. Phased-out tokens are
      # still on the battlefield (CR 702.26d), see Engine::Copies#ceases_to_exist?.
      # Skipped while the zones are as last scanned (Engine::Zones#zones_version), unless a prepared copy lost its
      # permanent since (Engine::Faces#unprepare!).
      def remove_tokens_outside_battlefield!
        return false if @tokens_scanned == zones_version

        gone = state.objects.values.select { ceases_to_exist?(it) } # and copies, CR 707.10a (Engine::Copies)
        gone.each do |obj|
          state.zone_list(obj.zone, obj.owner).delete(obj.id)
          state.objects.delete(obj.id)
          emit Events::TokenCeased.new(object: obj.id, card: obj.card, zone: obj.zone.to_s)
        end
        @tokens_scanned = zones_version
        !gone.empty?
      end

      # The next state-based action check looks for tokens and copies to remove again.
      def rescan_tokens! = @tokens_scanned = nil

      # CR 704.5j: the legend rule needs a choice, so it runs as a frame before priority.
      def legend_rule_first!(index)
        return false if state.frames.any? { it["type"] == "legend_rule" }

        conflict = legend_conflicts.first or return false
        state.frames << { "type" => "legend_rule", "then" => index, "player" => conflict[0], "name" => conflict[1] }
        ask!(nil)
        true
      end

      # [[controller, card name, [ids]]] for every legend-rule violation.
      def legend_conflicts
        groups = state.battlefield.group_by do |id|
          c = chars(id)
          c.legendary? ? [object(id).controller, c.name] : nil
        end
        groups.filter_map { |key, ids| [key[0], key[1], ids] if key && ids.size > 1 }
      end

      def legend_candidates(frame)
        legend_conflicts.find { |player, name, _| player == frame["player"] && name == frame["name"] }&.last || []
      end

      def step_legend_rule!(frame)
        candidates = legend_candidates(frame)
        if candidates.size > 1 && !frame["keep"]
          ask!("kind" => "legend_rule", "player" => frame["player"], "name" => frame["name"])
          return :wait
        end
        (candidates - [frame["keep"]]).each { move!(it, :graveyard, reason: "sba_legend_rule") }
        give_priority!(frame["then"]) # state-based actions are checked again (CR 704.3)
        :done
      end

      def keep_legend!(id)
        state.frames.rfind { it["type"] == "legend_rule" }["keep"] = id
        ask!(nil)
      end

      def creature_sba(obj)
        toughness = toughness(obj)
        return "sba_toughness" if toughness <= 0 # CR 704.5f (indestructible doesn't help)
        return nil if chars(obj).keyword?(:indestructible) # CR 702.12b

        if obj.damage.positive? && obj.damage >= toughness then "sba_lethal_damage" # CR 704.5g
        elsif obj.deathtouched then "sba_deathtouch" # CR 704.5h (wither damage is dealt but not marked, CR 702.80a)
        end
      end
    end

    include StateBasedActions
  end
end
