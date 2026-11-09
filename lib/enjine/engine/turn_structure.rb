# frozen_string_literal: true

module Enjine
  class Engine
    # The untap step's turn-based actions and the land-play allowance (CR 502, 305.2, 702.26).
    #
    # Untap step (CR 502.1, 502.3): first, the permanents the active player controlled when they phased
    # out phase in (unless an effect says permanents can't phase in); then the active player chooses
    # which of their "may choose not to untap" permanents stay tapped (an `untap_choice` frame, one
    # decision per such tapped permanent); then the rest of their permanents untap.
    #
    # Phasing (CR 702.26) isn't a zone change (702.26d): a phased-out permanent keeps its id, counters,
    # tapped status, attachments and controller. It is moved from `state.battlefield` to the pseudo-zone
    # `state.phased_out` (zone `:phased_out`), so every rule that looks at the battlefield treats it as
    # though it doesn't exist (702.26b) without knowing about phasing. `GameObject#phased_out` records
    # who controlled it as it phased out (for 502.1) and whether it phased out indirectly, attached to
    # another permanent (702.26g).
    module TurnStructure
      # ---- lands (CR 305.2) ---------------------------------------------------------------

      # How many lands `index` can play this turn: one, plus one for each "you may play an additional
      # land" ability of a permanent they control (CR 305.2). Lands put onto the battlefield by effects
      # aren't played, so they don't count against it (CR 305.2a).
      def land_plays_allowed(index)
        1 + state.battlefield.sum do |id|
          obj = object(id)
          obj.controller == index ? chars(obj).abilities.count { it.ability.kind == :additional_land_plays } : 0
        end
      end

      # CR 305.2a-b: whether `index` may play another land this turn.
      def land_play_available?(index) = player(index).lands_played < land_plays_allowed(index)

      # ---- the untap step (CR 502) --------------------------------------------------------

      def begin_untap_step!
        index = state.active
        phase_in_all!(index) # CR 502.1
        candidates = untap_choice_candidates(index)
        return finish_untap_step!(index, []) if candidates.empty?

        state.frames << { "type" => "untap_choice", "player" => index, "pending" => candidates, "keep" => [] }
        ask!(nil)
      end

      # CR 502.3: tapped permanents of `index` whose "you may choose not to untap" applies, and that
      # would otherwise untap.
      def untap_choice_candidates(index)
        state.battlefield.select do |id|
          obj = object(id)
          current = chars(obj)
          obj.tapped && obj.controller == index && !current.keyword?(:doesnt_untap) &&
            current.abilities.any? { it.ability.kind == :may_not_untap }
        end
      end

      # The untap_choice frame: one decision per candidate, then everything else untaps.
      def step_untap_choice!(frame)
        frame["pending"] &= state.battlefield
        if (id = frame["pending"].first)
          ask!("kind" => "untap_choice", "player" => frame["player"], "object" => id)
          return :wait
        end
        finish_untap_step!(frame["player"], frame["keep"])
        :done
      end

      # Records the answer to an untap_choice decision.
      def choose_untap!(id, untap)
        frame = state.frames.rfind { it["type"] == "untap_choice" }
        frame["pending"].delete(id)
        frame["keep"] << id unless untap
        ask!(nil)
      end

      def finish_untap_step!(index, keep)
        untap_all!(index, keep: keep)
        turn_based_actions_done!
      end

      # ---- phasing (CR 702.26) ------------------------------------------------------------

      # Phases out the permanents `ids` at the same time. Auras and Equipment attached to them phase out
      # indirectly with them; one that would phase out both ways phases out indirectly (CR 702.26g-h).
      def phase_out!(ids)
        ids = ids.select { state.battlefield.include?(it) }
        indirect = ids.flat_map { attached_tree(it) }
        (ids - indirect).each do |id|
          obj = object(id)
          phase_out_one!(obj, false)
          attached_tree(id).each { phase_out_one!(object(it), true) }
        end
      end

      # Every permanent attached to `id`, and every permanent attached to those (CR 702.26g).
      def attached_tree(id)
        attachments_of(id).flat_map { [it, *attached_tree(it)] }
      end

      def phase_out_one!(obj, indirectly)
        return unless state.battlefield.delete(obj.id)

        obj.zone = :phased_out
        obj.phased_out = { "by" => obj.controller, "indirectly" => indirectly }
        state.phased_out << obj.id
        leave_combat!(obj.id) # CR 506.4: removed from combat
        end_while_source_effects!(obj.id) # CR 702.26f: "for as long as" effects can no longer see it
        emit Events::PhasedOut.new(object: obj.id, indirectly: indirectly)
      end

      # CR 502.1, 702.26a: the permanents that phased out directly under `index`'s control phase in, with
      # whatever phased out indirectly attached to them (CR 702.26g). Nothing phases in while an effect
      # says permanents can't phase in.
      def phase_in_all!(index)
        return if state.phased_out.empty? || phasing_in_prevented?

        direct = state.phased_out.select do |id|
          info = object(id).phased_out
          info["by"] == index && !info["indirectly"]
        end
        direct.each { phase_in!(object(it)) }
      end

      def phasing_in_prevented?
        state.battlefield.any? { |id| chars(id).abilities.any? { it.ability.kind == :cant_phase_in } }
      end

      # CR 702.26c, 702.26i: it phases in attached to what it was attached to if that is still on the
      # battlefield (phased in or not), else unattached; state-based actions deal with the rest.
      def phase_in!(obj)
        state.phased_out.delete(obj.id)
        indirectly = obj.phased_out["indirectly"]
        obj.zone = :battlefield
        obj.phased_out = nil
        state.battlefield << obj.id
        to = obj.attached_to
        obj.attached_to = nil if !indirectly && to && !state.battlefield.include?(to) && !state.phased_out.include?(to)
        emit Events::PhasedIn.new(object: obj.id)
        state.phased_out.select { object(it).attached_to == obj.id && object(it).phased_out["indirectly"] }
             .each { phase_in!(object(it)) }
      end

      # ---- "for as long as [source] remains tapped" (CR 611.2b) ------------------------------

      # Whether a `while_source_tapped` effect still applies: its source is on the battlefield and tapped.
      def while_source_holds?(effect)
        source = effect["source"]
        state.battlefield.include?(source) && object(source).tapped
      end

      # CR 611.2b: once the duration ends (the source untaps, leaves or phases out), the effect is over
      # for good, even if the source becomes tapped again.
      def end_while_source_effects!(id)
        ending = state.effects.count { it["duration"] == "while_source_tapped" && it["source"] == id }
        return if ending.zero?

        state.effects.reject! { it["duration"] == "while_source_tapped" && it["source"] == id }
        emit Events::EffectsEnded.new(count: ending)
      end
    end
    include TurnStructure
  end
end
