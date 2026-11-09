# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "All artifacts and creatures phase out" (CR 702.26b): the permanents
      # are treated as though they don't exist until they phase in during their controller's next untap step
      # (CR 502.1). Auras and Equipment attached to them phase out with them (CR 702.26g). See
      # Engine::TurnStructure.
      class PhaseOut < Effect
        primitive :effect, :phase_out,
                  description: "Each referenced permanent phases out, with the Auras and Equipment attached to it " \
                               "(indirectly). It phases in during the untap step of the player who controlled it as " \
                               "it phased out. Phasing isn't a zone change: no enters or leaves triggers.",
                  rules: %w[702.26a 702.26b 702.26d 702.26g 702.26h 502.1 506.4],
                  params: { "to" => "selector" },
                  example: { "phase_out" => { "to" => { "each" => { "permanent" => { "any_of" => %w[artifact creature] } } } } }

        def self.keys = %w[to if]

        def apply(engine, ctx) = engine.phase_out!(objects(engine, ctx))

        def to_s = "phase out → #{to}"
      end
    end

    module Abilities
      # "Permanents can't phase in" (CR 702.26a, 502.1): while this permanent is on the battlefield, nothing
      # phases in during untap steps.
      class CantPhaseIn < Abilities::TurnRule
        primitive :ability, :cant_phase_in,
                  description: "While this permanent is on the battlefield, permanents can't phase in.",
                  rules: %w[702.26a 502.1 604.1], example: "cant_phase_in"

        INSTANCE = new.freeze

        def kind = :cant_phase_in
        def to_s = "Permanents can't phase in"
      end
    end
  end
end
