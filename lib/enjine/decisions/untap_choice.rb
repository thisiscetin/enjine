# frozen_string_literal: true

module Enjine
  module Decisions
    # CR 502.3: in their untap step, the active player decides whether a permanent they "may choose not
    # to untap" untaps. One decision per such tapped permanent (Engine::TurnStructure).
    class UntapChoice < Base
      def self.doc
        'Untap step: `{type: "untap", object: id}` or `{type: "keep_tapped", object: id}` for a permanent you may ' \
          "choose not to untap (CR 502.3)."
      end

      def self.options(_engine, pending)
        [{ type: "untap", object: pending["object"] }, { type: "keep_tapped", object: pending["object"] }]
      end

      def self.submit(engine, _pending, option) = engine.choose_untap!(option[:object], option[:type] == "untap")
    end
    register("untap_choice", UntapChoice)
  end

  module Frames
    # The active player's untap-step choices, then the untap itself (CR 502.3).
    class UntapChoice < Base
      def self.step(engine, frame) = engine.step_untap_choice!(frame)
      def self.decisions = %w[untap_choice]

      def self.validate(frame, data, errors)
        ids = Array(frame["pending"]) + Array(frame["keep"])
        errors << "frames: untap_choice permanents must be on the battlefield" unless ids.all? { data["battlefield"].include?(it) }
      end
    end
    register("untap_choice", UntapChoice)
  end
end
