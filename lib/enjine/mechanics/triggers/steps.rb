# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # "At the beginning of your upkeep" / "... of each end step".
      class StepBegins < Trigger
        STEPS = %w[untap upkeep draw precombat_main beginning_of_combat declare_attackers declare_blockers
                   combat_damage end_of_combat postcombat_main end cleanup].freeze
        WHOSE = %w[your each opponent].freeze

        primitive :trigger, :step_begins,
                  description: "A step begins. `whose`: \"your\" (default), \"each\" or \"opponent\".",
                  rules: %w[603.6b 503.1a 513.1a],
                  params: { "step" => "upkeep | draw | precombat_main | end | ...", "whose" => WHOSE.join(" | ") },
                  example: { "step_begins" => { "step" => "upkeep", "whose" => "your" } }

        def self.keys = %w[step whose]
        def event_class = Events::StepBegan

        def setup(params, errors, path)
          @step = params["step"]
          @whose = params.fetch("whose", "your")
          errors << "#{path}.step: must be one of #{STEPS.join(", ")}" unless STEPS.include?(@step)
          errors << "#{path}.whose: must be one of #{WHOSE.join(", ")}" unless WHOSE.include?(@whose)
        end

        def match?(engine, event, source)
          return false unless event.step == @step

          active = engine.state.active
          @whose == "each" || (@whose == "your") == (active == source["controller"])
        end

        def to_s = "At the beginning of #{@whose == "each" ? "each" : @whose} #{@step.tr("_", " ")}"
      end
    end
  end
end
