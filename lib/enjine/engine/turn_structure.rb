# frozen_string_literal: true

module Enjine
  class Engine
    # Turn structure (CR 500): moving from step to step, the untap step's turn-based actions and the
    # land-play allowance (CR 502, 305.2).
    #
    # Untap step (CR 502.1, 502.3): first, the permanents the active player controlled when they phased
    # out phase in (unless an effect says permanents can't phase in); then the active player chooses
    # which of their "may choose not to untap" permanents stay tapped (an `untap_choice` frame, one
    # decision per such tapped permanent); then the rest of their permanents untap.
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
        phasing_step!(index) # CR 502.1
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
          obj.tapped && obj.controller == index && !current.keyword?(:doesnt_untap) && !obj.memory["exerted"] &&
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

      # ---- turn structure (CR 500) --------------------------------------------

      def begin_turn!(index)
        end_effects_until_turn_of!(index) # "until your next turn" (CR 611.2a)
        state.turn += 1
        state.active = index
        state.players.each { it.lands_played = 0 }
        state.extra_phases = State.no_extra_phases
        emit Events::TurnBegan.new(turn: state.turn, active: name(index))
        enter_step!(:untap)
      end

      def enter_step!(step_name)
        state.extra_phases["combats"] += 1 if step_name == :beginning_of_combat
        state.step = step_name
        state.step_state = "begin"
        state.passes = 0
        state.priority = nil
      end

      # Runs the game forward until a decision is pending or the game is over.
      def advance!
        until state.pending || state.over?
          if (frame = state.frames.last)
            step_frame!(frame)
            next
          end
          break if state.step.nil?

          case state.step_state
          when "begin"
            state.step_state = "active"
            emit Events::StepBegan.new(turn: state.turn, step: state.step.to_s, phase: step.phase.to_s)
            step.begin(self)
          when "done" then next_step!
          else raise Error, "engine stalled in #{state.step} (#{state.step_state}) with no pending decision"
          end
        end
      end

      # Steps the innermost in-progress process (see Enjine::Frames).
      def step_frame!(frame)
        result = Frames.fetch(frame["type"]).step(self, frame)
        state.frames.delete_at(state.frames.rindex { it.equal?(frame) }) if result == :done && state.frames.include?(frame)
      end

      # Called once a step's turn-based actions (and any decisions they needed) are complete.
      def turn_based_actions_done!
        step.finish(self)
        if !step.priority? && state.step == :cleanup && !state.pending_triggers.empty?
          state.repeat_cleanup = true # CR 514.3a: priority now, then another cleanup step
          state.step_state = "active"
          give_priority!(state.active)
        elsif step.priority?
          give_priority!(state.active)
        else
          ask!(nil)
          state.step_state = "done"
        end
      end

      # CR 500.4: mana empties between steps. CR 500.1: proceed to the next step / turn.
      def next_step!
        empty_mana_pools!
        end_combat! if state.step == :end_of_combat # CR 511.3
        return enter_step!(:combat_damage) if second_combat_damage_step? # CR 510.4

        if state.step == :cleanup && state.repeat_cleanup
          state.repeat_cleanup = false
          return enter_step!(:cleanup)
        end
        index = Steps.index(state.step) + 1
        index += 1 while index < Steps::ORDER.size && Steps::ORDER[index].skip?(self)
        if index >= Steps::ORDER.size
          begin_turn!(take_next_turn!) # an extra turn comes first (CR 500.7)
        else
          following = Steps::ORDER[index]
          enter_step!(following.phase == step.phase ? following.name : phase_after!(step.phase, following.name))
        end
      end

      # ---- additional phases (CR 500.8) ---------------------------------------------------

      # The first step of each kind of phase an effect can add (an added main phase is a postcombat one).
      ADDED_PHASES = { "combat" => :beginning_of_combat, "main" => :postcombat_main }.freeze

      # "After this phase, there is an additional combat phase [followed by an additional main phase]": the
      # phases are added directly after the current phase (CR 500.8).
      def add_phases!(phases)
        state.extra_phases["pending"] << { "after" => step.phase.to_s, "phases" => phases }
      end

      # As `phase` ends: the first step of the next added phase, else of the phase the turn goes on with
      # (`natural`). Phases added after the same phase come most recently created first (CR 500.8).
      def phase_after!(phase, natural)
        extra = state.extra_phases
        due = extra["pending"].select { it["after"] == phase.to_s }
        extra["pending"] -= due
        due.each { extra["queue"].unshift(*it["phases"]) }
        if extra["queue"].empty?
          resume = extra.delete("resume")
          return resume ? resume.to_sym : natural
        end
        extra["resume"] ||= natural.to_s
        ADDED_PHASES.fetch(extra["queue"].shift)
      end

      # "If it's the first combat phase of the turn".
      def first_combat_phase? = state.extra_phases["combats"] == 1
    end

    include TurnStructure
  end
end
