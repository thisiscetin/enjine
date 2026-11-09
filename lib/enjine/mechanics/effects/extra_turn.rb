# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "Take an extra turn after this one." (CR 500.7)
      class ExtraTurn < Effect
        primitive :effect, :extra_turn,
                  description: "Each referenced player (default you) takes an extra turn after this one. Extra " \
                               "turns are taken most recently created first.",
                  rules: %w[500.7],
                  params: { "to" => "selector" },
                  example: { "extra_turn" => { "if" => { "began_extra_turn" => false } } }

        def self.keys = %w[to if]
        def self.default_to = "you"

        def apply(engine, ctx) = players(engine, ctx).each { engine.add_extra_turn!(it) }
        def to_s = "take an extra turn after this one → #{to}"
      end

      # "After this phase, there is an additional combat phase", "... followed by an additional main phase",
      # "After this main phase, there are two additional combat phases." (CR 500.8)
      class AdditionalPhases < Effect
        primitive :effect, :additional_phases,
                  description: "Adds `phases` (in order; each \"combat\" or \"main\") directly after the current " \
                               "phase of this turn. Phases added after the same phase come most recently created " \
                               "first. An added main phase is a postcombat main phase.",
                  rules: %w[500.8 505.1],
                  params: { "phases" => "list of \"combat\" | \"main\"" },
                  example: { "additional_phases" => { "phases" => %w[combat main] } }

        attr_reader :phases

        def self.keys = %w[phases if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @phases = Mechanics.list_param(params, :phases, errors, path)
          return if !@phases.empty? && @phases.all? { Engine::ADDED_PHASES.key?(it) }

          errors << "#{path}.phases: must be a non-empty list of \"combat\" | \"main\""
        end

        def apply(engine, _ctx) = engine.add_phases!(phases.dup)
        def to_s = "after this phase, additional #{phases.join(" and ")} phase#{"s" if phases.size > 1}"
      end
    end

    class Condition
      # "If you haven't begun an extra turn this game" (CR 500.7): {"began_extra_turn": false}.
      class BeganExtraTurn
        def initialize(wanted)
          @wanted = wanted
          freeze
        end

        def true?(engine, ctx) = engine.began_extra_turn?(ctx.controller) == @wanted
        def to_s = @wanted ? "you've begun an extra turn this game" : "you haven't begun an extra turn this game"
      end

      # "If it's the first combat phase of the turn" (CR 500.8): {"first_combat_phase": true}.
      class FirstCombatPhase
        def self.build(data, errors, path)
          Mechanics.check_keys(data, %w[first_combat_phase], errors, path)
          errors << "#{path}.first_combat_phase: must be true or false" unless [true, false].include?(data["first_combat_phase"])
          new(data["first_combat_phase"] != false)
        end

        def initialize(wanted)
          @wanted = wanted
          freeze
        end

        def true?(engine, _ctx) = engine.first_combat_phase? == @wanted
        def to_s = @wanted ? "it's the first combat phase of the turn" : "it isn't the first combat phase of the turn"
      end
    end
  end
end
