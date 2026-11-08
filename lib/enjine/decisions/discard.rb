# frozen_string_literal: true

module Enjine
  module Decisions
    # CR 514.1: during cleanup the active player discards down to maximum hand size,
    # one card per decision.
    class Discard < Base
      def self.doc
        'Cleanup step: discard one card, `{type: "discard", object: id}`, until the hand ' \
          "has 7 cards. `count` is how many remain (CR 514.1)."
      end

      def self.options(engine, pending)
        engine.player(pending["player"]).hand.map { |id| { type: "discard", object: id } }
      end

      def self.submit(engine, pending, option)
        engine.move!(option[:object], :graveyard, reason: "discard")
        remaining = pending["count"] - 1
        if remaining.positive?
          engine.ask!(pending.merge("count" => remaining))
        else
          engine.turn_based_actions_done!
        end
      end
    end
    register("discard", Discard)
  end
end
