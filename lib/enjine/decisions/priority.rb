# frozen_string_literal: true

module Enjine
  module Decisions
    # CR 117: the player with priority may take any legal action or pass.
    # Options are the union of every registered priority action (Enjine::Actions).
    class Priority < Base
      def self.doc
        "The player holding priority takes an action or passes. Options come from the priority actions below (CR 117)."
      end

      def self.options(engine, pending)
        Actions::PRIORITY.flat_map { |action| action.options(engine, pending["player"]) }
      end

      def self.submit(engine, pending, option)
        Actions.fetch(option[:type]).perform(engine, pending["player"], option)
      end
    end
    register("priority", Priority)
  end
end
