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

      # "Target opponent skips their next X turns." (CR 614.10)
      class SkipTurns < Effect
        primitive :effect, :skip_turns,
                  description: "Each referenced player skips their next `amount` turns (extra turns included): " \
                               "each of those turns doesn't happen, and the next player in turn order takes theirs. " \
                               "Several skips add up.",
                  rules: %w[614.1b 614.10 614.10a],
                  params: { "amount" => "amount", "to" => "selector" },
                  example: { "skip_turns" => { "amount" => 1, "to" => { "target" => 0 } } }

        def apply(engine, ctx)
          n = amount_for(engine, ctx)
          players(engine, ctx).each { engine.skip_turns!(it, n) }
        end

        def to_s = "skip the next #{amount} turn(s) → #{to}"
      end

      # "After this phase, there is an additional combat phase", "... followed by an additional main phase",
      # "After this main phase, there are two additional combat phases." (CR 500.8)
      class AdditionalPhases < Effect
        primitive :effect, :additional_phases,
                  description: "Adds `phases` (in order; each \"combat\" or \"main\") directly after the current " \
                               "phase of this turn. Phases added after the same phase come most recently created " \
                               "first. An added main phase is a postcombat main phase. `attackers`: only creatures " \
                               "matching this filter can attack during the (first) added combat phase.",
                  rules: %w[500.8 505.1 508.1c],
                  params: { "phases" => "list of \"combat\" | \"main\"", "attackers" => "creature filter" },
                  example: { "additional_phases" => { "phases" => %w[combat main] } }

        attr_reader :phases, :attackers

        def self.keys = %w[phases attackers if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @attackers = Mechanics.fetch_param(params, :attackers)
          Mechanics.build_entry(:filter, @attackers, errors, "#{path}.attackers") unless @attackers.nil?
          @phases = Mechanics.list_param(params, :phases, errors, path)
          return if !@phases.empty? && @phases.all? { Engine::ADDED_PHASES.key?(it) }

          errors << "#{path}.phases: must be a non-empty list of \"combat\" | \"main\""
        end

        def apply(engine, _ctx) = engine.add_phases!(phases.dup, attackers: attackers)

        def to_s
          only = " (only #{Mechanics.build_entry(:filter, attackers, [], "")} can attack)" if attackers
          "after this phase, additional #{phases.join(" and ")} phase#{"s" if phases.size > 1}#{only}"
        end
      end

      # "End the turn." (CR 725.1)
      class EndTheTurn < Effect
        primitive :effect, :end_the_turn,
                  description: "Ends the turn: triggered abilities not yet on the stack cease to exist, every object on " \
                               "the stack is exiled (this spell too, so its later effects don't happen), state-based " \
                               "actions are checked, combat ends and the game skips to the cleanup step. Abilities " \
                               "that trigger meanwhile go on the stack during cleanup, followed by another cleanup step.",
                  rules: %w[725.1 725.1a 725.1b 725.1c 725.1d 725.1e 725.1f 514.3a],
                  example: "end_the_turn"

        def self.keys = %w[if]
        def self.default_to = "you"

        def apply(engine, _ctx) = engine.end_the_turn!
        def to_s = "end the turn"
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
