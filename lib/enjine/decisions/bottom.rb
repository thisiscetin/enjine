# frozen_string_literal: true

module Enjine
  module Decisions
    # CR 103.5: after keeping, put one card from hand on the bottom of the library
    # (asked once per card, so the order is the order chosen).
    class Bottom < Base
      def self.doc
        'After keeping, put one card on the bottom of the library: `{type: "bottom", ' \
          "object: id}`. Asked once per mulligan taken. Hidden from the opponent (CR 103.5)."
      end

      def self.options(engine, pending)
        engine.player(pending["player"]).hand.map { |id| { type: "bottom", object: id } }
      end

      def self.submit(engine, _pending, option)
        engine.move!(option[:object], :library, position: :bottom, reason: "mulligan_bottom")
        engine.next_bottom_or_start!
      end

      # Which card went to the bottom is hidden from the opponent.
      def self.redact(option, viewer_is_decider) = viewer_is_decider ? option : { type: "bottom" }
    end
    register("bottom", Bottom)
  end
end
