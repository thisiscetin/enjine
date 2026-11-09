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

    module Effects
      # "For as long as [this] remains tapped, if a triggered ability of that creature triggers, that ability
      # triggers an additional time" (CR 603.2d, 611.2b): a resolved effect on the referenced permanents
      # (locked in, CR 611.2c). It ends for good when its source untaps, leaves the battlefield or phases out
      # (Engine#end_while_source_effects!); delayed and reflexive triggered abilities are never affected.
      class AdditionalTriggersEffect < Effect
        DURATIONS = %w[while_source_tapped].freeze

        primitive :effect, :additional_triggers,
                  description: "For `duration` (while_source_tapped: for as long as the source remains tapped), each " \
                               "triggered ability of each referenced permanent triggers an additional time.",
                  rules: %w[603.2d 611.2b 611.2c],
                  params: { "to" => "selector", "duration" => DURATIONS.join(" | ") },
                  example: { "additional_triggers" => { "to" => { "target" => 0 }, "duration" => "while_source_tapped" } }

        def self.keys = %w[to duration if]

        def setup(params, errors, path)
          @duration = Mechanics.fetch_param(params, :duration)
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
        end

        # CR 611.2b: if the source isn't tapped (or is gone) as this resolves, the duration never starts.
        def apply(engine, ctx)
          source = engine.state.objects[ctx.source]
          return unless source && engine.state.battlefield.include?(source.id) && source.tapped

          engine.add_continuous_effect!("additional_triggers", ctx, objects(engine, ctx),
                                        "duration" => @duration, "source" => ctx.source)
        end

        def to_s = "its triggered abilities trigger an additional time while the source remains tapped → #{to}"
      end
    end
  end
end
