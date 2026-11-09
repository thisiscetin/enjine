# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # "Whenever a creature you control attacking causes a triggered ability of that creature to trigger" (CR 603.2):
      # another ability triggering is the event. `cause: "attacks"`: the other ability triggered on its own source
      # attacking (CR 508.1). "Copy that ability" is copy_spell of {"triggering": "ability"}: the triggered ability
      # once it's on the stack (CR 707.10); the controller orders the two abilities (CR 603.3b).
      class AbilityTriggers < Trigger
        CAUSES = %w[attacks].freeze

        primitive :trigger, :ability_triggers,
                  description: "A triggered ability of the subject triggers. `cause: \"attacks\"` (required): its trigger " \
                               "event was the subject attacking. {\"triggering\": \"ability\"} is that triggered ability " \
                               "while it's on the stack.",
                  rules: %w[603.2 603.3b 508.1 707.10],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, \"controller\": ..., \"other\": true}",
                            "cause" => CAUSES.join(" | ") },
                  example: { "ability_triggers" => { "subject" => { "each" => "creature", "controller" => "you" },
                                                     "cause" => "attacks" } }

        def self.keys = %w[subject cause]
        def event_class = Events::AbilityTriggered

        def setup(params, errors, path)
          @cause = params["cause"]
          errors << "#{path}.cause: must be one of #{CAUSES.join(", ")}" unless CAUSES.include?(@cause)
        end

        def match?(engine, event, source)
          pending = engine.state.pending_triggers.find { it["id"] == event.trigger } or return false
          cause = pending["event"] || {}
          return false unless cause["type"] == "attacker_declared" && cause["object"] == event.source # CR 508.1

          obj = engine.state.objects[event.source] or return false
          @subject.match?(engine, event.source, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        def occurrences(engine, event, source)
          return [] unless match?(engine, event, source)

          [{ "object" => event.source, "player" => engine.object(event.source).controller, "card" => event.card,
             "ability" => event.trigger }]
        end

        def to_s = "Whenever #{@subject} attacking causes a triggered ability of it to trigger"
      end
    end
  end
end
