# frozen_string_literal: true

module Enjine
  class Engine
    # Player-level rules effects and the rules they change: "you have hexproof", "no maximum hand
    # size", "can't attack", "prevent all damage that would be dealt to you", "you don't lose the
    # game for having 0 or less life", "you can't sacrifice ..." (static abilities of permanents and
    # resolved effects with a duration), winning and losing by an effect (CR 104.2b, 104.3e), extra
    # turns (CR 500.7), temporary control changes (CR 613.1b) and targeting restrictions (CR 115.4).
    module Rules
      # ---- player rules -------------------------------------------------------------------

      # Whether `rule` applies to the player: a `player_rule` effect naming them (state.effects) or a
      # `player_rule` static ability of a permanent on the battlefield. `object`: the permanent a
      # filtered rule ("can't sacrifice Treasure tokens") is asked about.
      def player_rule?(index, rule, object = nil)
        ref = Mechanics::Filters.player_ref(self, index)
        return true if state.effects.any? { it["kind"] == "player_rule" && it["rule"] == rule && it["affected"].include?(ref) }

        player_rule_statics.any? do |source, ability|
          ability.rule == rule && ability.applies_to?(index, source.controller) &&
            (object.nil? || ability.matches?(self, object, source))
        end
      end

      # [[source permanent, PlayerRule ability]] on the battlefield, cached with the layer pass (they
      # change only on the events that change characteristics).
      def player_rule_statics
        return @player_rule_statics if @player_rule_epoch == @epoch && @player_rule_state.equal?(state) && @player_rule_statics

        @player_rule_epoch = @epoch
        @player_rule_state = state
        @player_rule_statics = state.battlefield.flat_map do |id|
          source = object(id)
          chars(source).abilities.filter_map { [source, it.ability] if it.ability.kind == :player_rule }
        end
      end

      # CR 402.2 / 514.1: seven, or nil when the player has no maximum hand size.
      def max_hand_size(index) = player_rule?(index, "no_max_hand_size") ? nil : HAND_SIZE

      # CR 701.21a: only a permanent you control can be sacrificed, and "can't" effects forbid more
      # (CR 614.17b: a cost that includes sacrificing it can't be paid).
      def can_sacrifice?(obj, index)
        obj.zone == :battlefield && obj.controller == index && !player_rule?(index, "cant_sacrifice", obj)
      end

      # CR 704.5a, unless an effect says the player doesn't lose for having 0 or less life.
      def loses_for_life?(index) = player(index).life <= 0 && !player_rule?(index, "cant_lose_for_life")

      # CR 615.1: a prevention effect protecting a player from all damage.
      def damage_prevented?(ref)
        index = Mechanics::Filters.player_index(self, ref)
        !index.nil? && player_rule?(index, "prevent_all_damage")
      end

      # "Until your next turn" effects end as that player's next turn begins (CR 611.2a, 500.1).
      def end_effects_until_turn_of!(index)
        ending = state.effects.count { it["duration"] == "until_your_next_turn" && it["controller"] == index }
        return if ending.zero?

        state.effects.reject! { it["duration"] == "until_your_next_turn" && it["controller"] == index }
        emit Events::EffectsEnded.new(count: ending)
      end

      # ---- targeting restrictions (CR 115.4, 702.11c) --------------------------------------

      # Whether choosing `ref` as a target is forbidden for player `index`: a player with hexproof can't
      # be targeted by opponents (CR 702.11c), and a permanent may say it can't be the target of
      # abilities from some sources its controller's opponents control. `source`: the permanent whose
      # ability is targeting (nil for a spell).
      def targeting_forbidden?(ref, index, source = nil)
        player = Mechanics::Filters.player_index(self, ref)
        return player != index && player_rule?(player, "hexproof") if player
        return false unless source

        obj = state.objects[ref]
        src = state.objects[source]
        return false unless obj && src && obj.zone == :battlefield && obj.controller != index

        chars(obj).abilities.any? { it.ability.kind == :cant_be_targeted_by && it.ability.forbids?(self, src) }
      end

      # ---- winning and losing by an effect (CR 104.2b, 104.3e) ------------------------------

      # CR 104.2b: in a two-player game, a player winning means every opponent loses. CR 104.3f: a
      # player who would win and lose at once loses (handled: a loss already recorded stays).
      def win_game!(index)
        state.players.each_index { lose!(it, "opponent_won") unless it == index || player(it).lost }
        end_game_if_decided!
      end

      def lose_game!(index)
        lose!(index, "effect")
        end_game_if_decided!
      end

      # ---- extra turns (CR 500.7) -----------------------------------------------------------

      # CR 500.7: the turn is added directly after this one; the most recently created is taken first.
      def add_extra_turn!(index)
        state.extra_turns["queue"] << index
        emit Events::ExtraTurnAdded.new(player: name(index))
      end

      # The player whose turn comes next: an extra turn if one was added, else the next in turn order.
      def take_next_turn!
        index = state.extra_turns["queue"].pop
        return state.opponent(state.active) unless index

        state.extra_turns["begun"] |= [index]
        index
      end

      def began_extra_turn?(index) = state.extra_turns["begun"].include?(index)

      # ---- control changes (CR 613.1b, 108.4) -----------------------------------------------

      # Control of `obj` until end of turn: an effect that ends in the cleanup step (CR 514.2), handing
      # it back unless a newer control change has happened since.
      def gain_control_until_end_of_turn!(obj, controller, ctx)
        return if obj.controller == controller

        timestamp = next_timestamp!
        previous = obj.controller
        gain_control!(obj, controller, timestamp)
        state.effects << { "kind" => "control", "timestamp" => timestamp, "controller" => ctx.controller,
                           "affected" => [obj.id], "duration" => "end_of_turn", "previous" => previous }
        emit Events::EffectStarted.new(kind: "control", affected: [obj.id], details: { "controller" => controller })
      end

      # CR 514.2: as "until end of turn" control effects end, control returns to the previous controller.
      # Several of them on one permanent all end together: it goes back to whoever had it before the first.
      def revert_temporary_control!
        ending = state.effects.select { it["kind"] == "control" && it["duration"] == "end_of_turn" }
        ending.group_by { it["affected"].first }.each do |id, list|
          obj = state.objects[id]
          next unless obj && obj.zone == :battlefield && obj.memory["control_timestamp"] == list.last["timestamp"]

          gain_control!(obj, list.first["previous"])
        end
      end

      # ---- damage and counters --------------------------------------------------------------

      # All damage marked on a permanent is removed ("healed", CR 120.6, 514.2).
      def remove_damage!(obj)
        obj.damage = 0
        obj.deathtouched = false
      end

      def remove_all_counters!(obj, kind = nil)
        (kind ? [kind] : obj.counters.keys).each { remove_counters!(obj, it, obj.counters.fetch(it, 0)) }
      end

      # CR 701.14a-d: each creature deals damage equal to its power to the other, at the same time; not
      # combat damage. Neither deals damage unless both are still creatures on the battlefield (701.14b).
      # A creature fighting itself deals twice its power to itself (701.14c).
      def fight!(one, other)
        return unless [one, other].all? { state.battlefield.include?(it) && chars(it).creature? }
        return deal_damage!(one, one, 2 * power(object(one))) if one == other

        powers = [power(object(one)), power(object(other))]
        deal_damage!(one, other, powers[0])
        deal_damage!(other, one, powers[1])
      end
    end
    include Rules
  end
end
