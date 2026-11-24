# frozen_string_literal: true

module Enjine
  class Engine
    # The id prefix of a card exiled face down, so its id doesn't name it (CR 406.3).
    FACE_DOWN_ID = "face_down"

    # Cards exiled face down (CR 406.3, 406.3a-b). Such a card has no characteristics (Engine#chars) and
    # only the players in its memory "may_look" see which card it is (View, Events::ZoneChanged); a hidden-away
    # card (memory "looker_source", CR 702.75a), the player who controls that permanent now. The effect
    # that exiled it may let a player play it; the card is turned face up just before it's played, so
    # whether it can be played is judged face up, and only for a player who may look at it.
    module FaceDown
      def face_down?(obj) = obj.zone == :exile && obj.memory["face_down"] == true

      # Whether `index` may look at the face-down card (always true for a face-up card). A hidden-away card's
      # looker follows its permanent's controller while that permanent is on the battlefield (CR 702.75a).
      def may_look?(obj, index)
        return true unless face_down?(obj)

        source = state.objects[obj.memory["looker_source"]]
        return source.controller == index if source&.zone == :battlefield

        obj.memory.fetch("may_look", []).include?(index)
      end

      # Evaluates the block with the face-down card `id` seen face up (CR 406.3a: "turned face up just
      # before the player announces that they are playing the card"). Nothing in the block changes state.
      def face_up(id)
        previous = @face_up
        @face_up = id
        yield
      ensure
        @face_up = previous
      end
    end
    include FaceDown
  end
end
