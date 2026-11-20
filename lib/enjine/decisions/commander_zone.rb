# frozen_string_literal: true

module Enjine
  module Decisions
    # CR 903.9: a commander went to a graveyard, exile, hand or library; its owner chooses whether to put it
    # into the command zone instead (Engine::Commander).
    class CommanderZone < Base
      def self.doc
        'Your commander is in a graveyard, exile, hand or library: `{type: "command", object: id}` puts it into ' \
          'the command zone, `{type: "stay", object: id}` leaves it where it is (CR 903.9).'
      end

      def self.options(_engine, pending)
        [{ type: "command", object: pending["object"] }, { type: "stay", object: pending["object"] }]
      end

      def self.submit(engine, _pending, option) = engine.choose_commander_zone!(option[:type] == "command")
    end
    register("commander_zone", CommanderZone)
  end

  module Frames
    # The owner's choice to send a commander back to the command zone (CR 903.9), before priority.
    class CommanderZone < Base
      def self.step(engine, frame) = engine.step_commander_zone!(frame)
      def self.decisions = %w[commander_zone]

      def self.validate(frame, data, errors)
        errors << "frames: commander_zone object #{frame["object"]} doesn't exist" unless data["objects"].any? do
          it["id"] == frame["object"]
        end
      end
    end
    register("commander_zone", CommanderZone)
  end
end
