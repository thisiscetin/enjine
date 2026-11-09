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
    end
  end
end
