# frozen_string_literal: true

require_relative "triggers"

module Enjine
  module Mechanics
    module Triggers
      # "Whenever you face a dilemma" (CR 700.17): a player faces a dilemma whenever they
      # choose one or more modes for a spell or ability. The engine records it when the spell or ability
      # with chosen modes is cast, activated or put on the stack, so a cancelled cast never counts.
      class FacesDilemma < Trigger
        primitive :trigger, :faces_dilemma,
                  description: "A player faces a dilemma: they chose one or more modes for a spell or ability " \
                               "(cast, activated, or a triggered ability put on the stack). " \
                               "`controller`: you (default) | opponent | any. CR 700.17.",
                  rules: %w[700.17 700.2 601.2b 603.3c],
                  params: { "controller" => "you | opponent | any" },
                  example: { "faces_dilemma" => {} }

        CONTROLLERS = %w[you opponent any].freeze

        def self.keys = %w[controller]
        def event_class = Events::DilemmaFaced

        def setup(params, errors, path)
          @controller = params.fetch("controller", "you")
          errors << "#{path}.controller: must be one of #{CONTROLLERS.join(", ")}" unless CONTROLLERS.include?(@controller)
        end

        def match?(engine, event, source)
          who = engine.names.index(event.player)
          @controller == "any" || (@controller == "you") == (who == source["controller"])
        end

        def to_s = "Whenever #{{ "you" => "you face", "opponent" => "an opponent faces" }.fetch(@controller, "a player faces")} a dilemma"
      end
    end
  end
end
