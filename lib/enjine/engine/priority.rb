# frozen_string_literal: true

module Enjine
  class Engine
    # Priority (CR 117): who may act, passing, and when the top of the stack resolves or the step ends.
    module Priority
      # CR 117.5: state-based actions are checked whenever a player would receive priority.
      def give_priority!(index)
        check_state_based_actions!
        return if state.over?
        return if legend_rule_first!(index)
        return if put_triggers_first!(index)

        state.priority = index
        ask!("kind" => "priority", "player" => index)
      end

      # Any action other than passing resets the "pass in succession" count (CR 117.4).
      def action_taken!(index)
        state.passes = 0
        give_priority!(index)
      end

      def pass_priority!(index)
        emit Events::PriorityPassed.new(player: name(index))
        state.passes += 1
        if state.passes >= state.players.size && !state.stack.empty?
          ask!(nil)
          begin_resolution! # CR 117.4, 608
        elsif state.passes >= state.players.size
          # CR 117.4 / 500.2: all players passed with an empty stack -> the step ends.
          ask!(nil)
          state.step_state = "done"
        else
          give_priority!(state.opponent(index))
        end
      end

      def sorcery_timing?(index)
        state.active == index && Steps::MAIN_PHASE_STEPS.include?(state.step) && state.stack.empty? &&
          state.pending&.fetch("kind") == "priority"
      end
    end

    include Priority
  end
end
