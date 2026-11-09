# frozen_string_literal: true

module Enjine
  module Mechanics
    module Keywords
      # Storied (CR 702.195a): "Any time you control three or more permanents that are artifacts, Sagas, and/or
      # legendary and you don't have an enduring story, you have an enduring story for the rest of the game."
      # The engine checks it (Engine::Designations#tell_enduring_stories!); cards read the designation with
      # the condition `{"designation": "enduring_story"}`.
      class Storied < Primitive
        primitive :keyword, :storied,
                  description: "While you control this permanent, once you control three or more permanents that are " \
                               "artifacts, Sagas and/or legendary, you have an enduring story for the rest of the game " \
                               "(condition `{\"designation\": \"enduring_story\"}`).",
                  rules: %w[702.195a 702.195b 702.195c], example: { "keywords" => ["storied"] }
      end
    end

    class Condition
      # "If you have an enduring story" / "as long as you have an enduring story": the controller has a player
      # designation (Engine::Designations; CR 702.195b).
      class Designation
        def self.build(data, errors, path)
          Mechanics.check_keys(data, %w[designation], errors, path)
          value = data["designation"]
          known = Engine::Designations::NAMES
          errors << "#{path}.designation: must be one of #{known.join(", ")}" unless known.include?(value)
          new(value)
        end

        def initialize(designation)
          @designation = designation
          freeze
        end

        def true?(engine, ctx) = engine.designation?(ctx.controller, @designation)
        def to_s = "you have #{@designation == "enduring_story" ? "an enduring story" : @designation.tr("_", " ")}"
      end
    end
  end
end
