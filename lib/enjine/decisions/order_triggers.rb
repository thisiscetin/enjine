# frozen_string_literal: true

module Enjine
  module Decisions
    # CR 603.3b: a player with several triggered abilities to put on the stack chooses the
    # order, one per decision: the chosen trigger goes on the stack next (so it resolves later).
    class OrderTriggers < Base
      def self.doc
        'Put one of your pending triggered abilities on the stack next: `{type: "trigger", trigger: id}` ' \
          "(CR 603.3b). The last one put on the stack resolves first."
      end

      def self.options(engine, pending)
        engine.pending_triggers_for(pending["player"]).map { { type: "trigger", trigger: it["id"] } }
      end

      def self.submit(engine, _pending, option) = engine.choose_trigger!(option[:trigger])
    end
    register("order_triggers", OrderTriggers)
  end
end
