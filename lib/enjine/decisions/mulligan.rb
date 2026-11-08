# frozen_string_literal: true

module Enjine
  module Decisions
    # CR 103.5: keep the opening hand or take a (London) mulligan.
    class Mulligan < Base
      def self.doc
        'Keep the hand (`{type: "keep"}`) or take a London mulligan (`{type: ' \
          '"mulligan"}`). Players declare in turn order; mulligans then happen ' \
          "simultaneously (CR 103.5)."
      end

      KEEP = { type: "keep" }.freeze
      MULLIGAN = { type: "mulligan" }.freeze

      def self.options(engine, pending)
        engine.player(pending["player"]).mulligans < Engine::MAX_MULLIGANS ? [KEEP, MULLIGAN] : [KEEP]
      end

      def self.submit(engine, pending, option)
        engine.declare_mulligan!(pending["player"], option[:type])
      end
    end
    register("mulligan", Mulligan)
  end
end
