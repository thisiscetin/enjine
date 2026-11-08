# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # "If [cause] causes a triggered ability of a permanent you control to trigger, that ability triggers
      # an additional time" (CR 603.2d). A static ability; the engine asks it each time a triggered ability
      # of a permanent triggers (Engine#additional_triggers). Delayed and reflexive triggered abilities are
      # never affected.
      class AdditionalTriggers < Primitive
        CAUSES = %w[you_gain_life].freeze

        primitive :ability, :additional_triggers,
                  description: "While this permanent is on the battlefield, a triggered ability of a permanent its " \
                               "controller controls that triggers because of `cause` triggers an additional time. " \
                               "`cause`: you_gain_life (its controller gaining life).",
                  rules: %w[603.2d 119.9],
                  params: { "cause" => CAUSES.join(" | ") },
                  example: { "additional_triggers" => { "cause" => "you_gain_life" } }

        attr_reader :cause

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cause], errors, path)
          cause = Mechanics.fetch_param(params, :cause)
          errors << "#{path}.cause: must be one of #{CAUSES.join(", ")}" unless CAUSES.include?(cause)
          new(cause)
        end

        def initialize(cause)
          super()
          @cause = cause
          freeze
        end

        def kind = :additional_triggers
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        def to_s = "triggered abilities of your permanents that trigger from you gaining life trigger an additional time"

        # `holder`: the permanent with this ability; `source`: the triggering ability's source (a permanent).
        def additional_trigger?(engine, event, holder, source)
          return false unless source["controller"] == holder.controller

          event.is_a?(Events::LifeChanged) && event.gain.positive? && engine.names.index(event.player) == holder.controller
        end
      end
    end
  end
end
