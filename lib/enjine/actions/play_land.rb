# frozen_string_literal: true

module Enjine
  module Actions
    # CR 305.1-305.2, 116.2a: playing a land is a special action — own main phase,
    # empty stack, while holding priority, one land per turn.
    class PlayLand
      def self.doc
        '`{type: "play_land", object: id}` — special action: your main phase, empty stack, one land per turn (CR 305.1, 305.2).'
      end

      LANDS_PER_TURN = 1

      def self.options(engine, index)
        return [] unless engine.sorcery_timing?(index) && engine.player(index).lands_played < LANDS_PER_TURN

        engine.player(index).hand.filter_map do |id|
          { type: "play_land", object: id } if engine.chars(id).land?
        end
      end

      def self.perform(engine, index, option)
        engine.player(index).lands_played += 1
        engine.move!(option[:object], :battlefield, controller: index, reason: "play_land")
        engine.action_taken!(index) # CR 117.3c: the player receives priority again
      end
    end
    register("play_land", PlayLand)
  end
end
