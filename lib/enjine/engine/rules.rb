# frozen_string_literal: true

module Enjine
  class Engine
    # Player-level rules effects and the rules they change: "you have hexproof", "no maximum hand
    # size", "can't attack", "prevent all damage that would be dealt to you", "you don't lose the
    # game for having 0 or less life", "you can't sacrifice ..." (static abilities of permanents and
    # resolved effects with a duration), winning and losing by an effect (CR 104.2b, 104.3e), extra
    # turns (CR 500.7), control changes (CR 613.1b), assimilate (CR 701.72), "for as long as" effects
    # (CR 611.2b) and targeting restrictions (CR 115.4).
    module Rules
      # ---- player rules -------------------------------------------------------------------

      # Whether `rule` applies to the player: a `player_rule` effect naming them (state.effects) or a
      # `player_rule` static ability of a permanent on the battlefield whose condition holds. `object`: the
      # permanent or card a filtered rule ("can't sacrifice Treasure tokens", "creature spells can't be
      # countered") is asked about.
      def player_rule?(index, rule, object = nil)
        ref = Mechanics::Filters.player_ref(self, index)
        return true if state.effects.any? { it["kind"] == "player_rule" && it["rule"] == rule && it["affected"].include?(ref) }

        player_rule_statics.any? do |source, ability|
          ability.rule == rule && ability.applies_to?(index, source.controller) &&
            (object.nil? || ability.matches?(self, object, source)) && ability.active?(self, source)
        end
      end

      # A rule of the whole game ("Damage can't be prevented"), whichever player it was given to.
      def game_rule?(rule) = state.players.each_index.any? { player_rule?(it, rule) }

      # CR 101.2: "can't cast" beats any permission to cast. `obj`: the card (or stand-in) to be cast. The card's own
      # "you can't cast this spell unless ..." too (CR 601.3).
      def cast_forbidden?(index, obj)
        player_rule?(index, "cant_cast", obj) || (obj.zone != :hand && player_rule?(index, "cant_cast_except_from_hand")) ||
          chars(obj).abilities.any? { it.ability.kind == :cast_restriction && !it.ability.allows?(self, index, obj) }
      end

      # CR 602.5, 101.2: abilities of a permanent matching a `cant_activate` filter can't be activated.
      def activation_forbidden?(index, obj) = obj.zone == :battlefield && player_rule?(index, "cant_activate", obj)

      # CR 615.12: damage that can't be prevented.
      def unpreventable?(combat) = game_rule?("damage_cant_be_prevented") || (combat && game_rule?("combat_damage_cant_be_prevented"))

      # [[source permanent, PlayerRule ability]] on the battlefield, cached with the layer pass (they
      # change only on the events that change characteristics).
      def player_rule_statics
        return @player_rule_statics if @player_rule_epoch == @epoch && @player_rule_state.equal?(state) && @player_rule_statics

        @player_rule_epoch = @epoch
        @player_rule_state = state
        @player_rule_statics = (state.battlefield + (state.command || [])).flat_map do |id| # emblems too (CR 114.4)
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

      # CR 615.1: a prevention effect protecting a player from all damage (Replacements#preventing!).
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
      # ability is targeting (nil for a spell). `targeter`: the spell, or the ability's source, whose qualities
      # protection and hexproof from a quality look at (CR 702.16b, 702.11d).
      def targeting_forbidden?(ref, index, source = nil, targeter: source)
        player = Mechanics::Filters.player_index(self, ref)
        return player != index && player_rule?(player, "hexproof") if player

        obj = state.objects[ref]
        return false unless obj && obj.zone == :battlefield

        quality = targeter && state.objects[targeter]
        return true if protected_from?(obj, quality)
        return false if obj.controller == index

        src = source && state.objects[source]
        protected_from?(obj, quality, :hexproof_from) ||
          (!src.nil? && chars(obj).abilities.any? { it.ability.kind == :cant_be_targeted_by && it.ability.forbids?(self, src) })
      end

      # ---- protection and hexproof from a quality (CR 702.11d, 702.16) ----------------------

      # Whether the permanent has protection (or, with `kind` :hexproof_from, hexproof) from `other`: a spell,
      # the source of an ability or of damage, an Aura, an Equipment or a blocking creature.
      def protected_from?(obj, other, kind = :protection_from)
        return false if other.nil?

        chars(obj).abilities.any? { it.ability.kind == kind && it.ability.from?(self, other) }
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

      # ---- extra and skipped turns (CR 500.7, 614.10) ----------------------------------------

      # CR 500.7: the turn is added directly after this one; the most recently created is taken first.
      def add_extra_turn!(index)
        state.extra_turns["queue"] << index
        emit Events::ExtraTurnAdded.new(player: name(index))
      end

      # CR 614.10a: the player skips their next `count` turns (each skip waits for a turn that isn't skipped).
      def skip_turns!(index, count)
        return unless count.positive?

        (state.extra_turns["skip"] ||= []).concat([index] * count)
      end

      # The player whose turn comes next: an extra turn if one was added, else the next in turn order. A
      # skipped turn doesn't happen (CR 614.10): the turn after it comes next.
      def take_next_turn!
        last = state.active
        loop do
          extra = state.extra_turns["queue"].pop
          index = extra || state.opponent(last)
          skip = state.extra_turns.fetch("skip", []).index(index)
          unless skip
            state.extra_turns["begun"] |= [index] if extra
            return index
          end
          state.extra_turns["skip"].delete_at(skip)
          state.extra_turns.delete("skip") if state.extra_turns["skip"].empty?
          emit Events::TurnSkipped.new(player: name(index))
          last = index
        end
      end

      def began_extra_turn?(index) = state.extra_turns["begun"].include?(index)

      # ---- control changes (CR 613.1b, 108.4) -----------------------------------------------

      # A control change with indefinite duration (CR 613.1b): it becomes a new controller's
      # permanent, newly under their control (CR 302.6), and leaves combat (CR 506.4). The newest
      # control change is remembered, so an older "until end of turn" one doesn't undo it as it ends.
      def gain_control!(obj, controller, timestamp = next_timestamp!)
        obj.memory["control_timestamp"] = timestamp
        return if obj.controller == controller

        leave_combat!(obj.id)
        obj.controller = controller
        obj.controlled_since = state.turn
        emit Events::ControlChanged.new(object: obj.id, controller: name(controller))
      end

      # Control of `obj` for a while: until end of turn, an effect that ends in the cleanup step (CR 514.2), handing
      # it back unless a newer control change has happened since.
      # `duration`: "end_of_turn", or "for as long as" its source remains tapped / on the battlefield (CR 611.2b,
      # `source` set; Engine::Rules#end_while_source_effects! hands it back).
      def gain_control_for!(obj, controller, ctx, duration: "end_of_turn", source: nil)
        return if obj.controller == controller

        timestamp = next_timestamp!
        previous = obj.controller
        gain_control!(obj, controller, timestamp)
        state.effects << { "kind" => "control", "timestamp" => timestamp, "controller" => ctx.controller,
                           "affected" => [obj.id], "duration" => duration, "previous" => previous,
                           "source" => source }.compact
        emit Events::EffectStarted.new(kind: "control", affected: [obj.id], details: { "controller" => controller })
      end

      # CR 514.2: as "until end of turn" control effects end, control returns to the previous controller.
      def revert_temporary_control! = revert_control!(state.effects.select { it["duration"] == "end_of_turn" })

      # As temporary control effects end, control returns to the previous controller. Several of them on one
      # permanent all end together: it goes back to whoever had it before the first.
      def revert_control!(ending)
        ending.select { it["kind"] == "control" }.group_by { it["affected"].first }.each do |id, list|
          obj = state.objects[id]
          next unless obj && obj.zone == :battlefield && obj.memory["control_timestamp"] == list.last["timestamp"]

          gain_control!(obj, list.first["previous"])
        end
      end

      # ---- assimilate (CR 701.72) -------------------------------------------------------------

      # CR 701.72a: a permanent: gain control of it, put a +1/+1 counter on it, it becomes a Borg artifact creature.
      # CR 701.72b: a permanent card elsewhere: put it onto the battlefield under your control with a +1/+1
      # counter; it's a Borg artifact creature. Returns the assimilated permanent's id (or nil).
      # `enters`: what an "as this enters" choice adds for a card put onto the battlefield (CR 614.12a).
      def assimilate!(ref, controller, ctx, enters: nil)
        obj = state.objects[ref] or return nil
        if obj.zone == :battlefield
          gain_control!(obj, controller)
          add_counters!(obj, "+1/+1", 1)
        else
          return nil unless obj.kind == "card" && catalog.fetch(obj.card).permanent? && %i[graveyard exile hand library].include?(obj.zone)

          status = (enters || {}).merge("counters" => (enters || {}).fetch("counters", {}).merge("+1/+1" => 1) { |_, a, b| a + b })
          obj = move!(ref, :battlefield, controller: controller, reason: "assimilate", enters: status) or return nil
        end
        # The type change lasts while it stays on the battlefield; ones about objects that left are dropped.
        state.effects.reject! { it["kind"] == "assimilate" && !state.battlefield.include?(it["affected"].first) }
        state.effects << { "kind" => "assimilate", "timestamp" => next_timestamp!, "controller" => ctx.controller,
                           "affected" => [obj.id], "duration" => "permanent" }
        emit Events::EffectStarted.new(kind: "assimilate", affected: [obj.id], details: {})
        obj.id
      end

      # ---- "for as long as [source] remains tapped" (CR 611.2b) ------------------------------

      # Whether a `while_source_tapped` effect still applies: its source is on the battlefield and tapped.
      def while_source_holds?(effect)
        source = effect["source"]
        state.battlefield.include?(source) && object(source).tapped
      end

      # "For as long as [source] remains tapped / on the battlefield" (CR 611.2b).
      WHILE_SOURCE = %w[while_source_tapped while_source_on_battlefield].freeze

      # CR 611.2b: once the duration ends (the source untaps, leaves or phases out, CR 702.26f), the effect
      # is over for good, even if the source becomes tapped again. Untapping ends only `while_source_tapped`.
      def end_while_source_effects!(id, durations = WHILE_SOURCE)
        ending = ->(effect) { durations.include?(effect["duration"]) && effect["source"] == id }
        count = state.effects.count(&ending)
        return if count.zero?

        revert_control!(state.effects.select(&ending)) # "for as long as" control (CR 611.2b)
        state.effects.reject!(&ending)
        emit Events::EffectsEnded.new(count: count)
      end
    end

    include Rules
  end
end
