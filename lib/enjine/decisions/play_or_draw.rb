# frozen_string_literal: true

module Enjine
  module Decisions
    # CR 103.1: the winner of the die roll chooses to play first or draw first.
    class PlayOrDraw < Base
      def self.doc = 'The die-roll winner chooses `{type: "play"}` or `{type: "draw"}` (CR 103.1).'

      OPTIONS = [{ type: "play" }.freeze, { type: "draw" }.freeze].freeze

      def self.options(_engine, _pending) = OPTIONS

      def self.submit(engine, pending, option)
        engine.choose_starting_player!(pending["player"], option[:type] == "play")
      end
    end
    register("play_or_draw", PlayOrDraw)
  end
end
