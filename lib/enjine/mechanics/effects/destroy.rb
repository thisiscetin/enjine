# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Destroy permanents (CR 701.8).
      class Destroy < Effect
        primitive :effect, :destroy, description: "Destroy each referenced permanent (it goes to its owner's graveyard).",
                                     rules: %w[701.8a], params: { "to" => "selector" },
                                     example: { "destroy" => { "to" => { "target" => 0 } } }
        def self.keys = %w[to if]

        # CR 702.12b: indestructible permanents aren't destroyed.
        def apply(engine, ctx)
          objects(engine, ctx).each do |id|
            engine.move!(id, :graveyard, reason: "destroy") unless engine.chars(id).keyword?(:indestructible)
          end
        end
      end
    end
  end
end
