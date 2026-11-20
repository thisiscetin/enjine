# frozen_string_literal: true

module Enjine
  class Engine
    # Durations measured in a player's own turns (CR 611.2a): "until the end of your next turn" control effects
    # and "until your next end step" permissions. "Until your next turn" ends as that turn begins
    # (Engine::Rules#end_effects_until_turn_of!).
    module Durations
      # At cleanup of its controller's next turn (CR 514.2), an "until the end of your next turn" control effect
      # ends and control returns (Engine::Rules#revert_control!).
      def end_next_turn_control!
        ending = state.effects.select do |e|
          e["kind"] == "control" && e["duration"] == "end_of_your_next_turn" && e["controller"] == state.active &&
            state.turn > e["turn"]
        end
        return if ending.empty?

        revert_control!(ending)
        state.effects.reject! { ending.include?(it) }
        emit Events::EffectsEnded.new(count: ending.size)
      end

      # What an effect lasting "until your next end step" remembers: an effect made during its controller's end
      # step or cleanup (`late`) lasts until the end step of their next turn; otherwise this turn's end step ends
      # it on their own turn.
      def end_step_timing(index, duration)
        return {} unless duration == "until_your_next_end_step"

        { "late" => state.active == index && %i[end cleanup].include?(state.step) }
      end

      # CR 513.1: as the active player's end step begins, their "until your next end step" effects end.
      def expire_end_step_effects!
        ending = state.effects.select do |e|
          e["duration"] == "until_your_next_end_step" && e["controller"] == state.active &&
            (state.turn > e["turn"] || !e["late"])
        end
        return if ending.empty?

        state.effects.reject! { ending.include?(it) }
        emit Events::EffectsEnded.new(count: ending.size)
      end
    end

    include Durations
  end
end
