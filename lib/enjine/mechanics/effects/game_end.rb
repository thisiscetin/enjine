# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Base for effects that may end the game: once it's over, nothing else in the list happens.
      class GameEndEffect < Effect
        def self.keys = %w[to if]
        def self.default_to = "you"

        def run(engine, ctx, locals)
          super
          engine.state.over? ? :wait : :done # the game ended: resolution stops here
        end
      end

      # "You win the game." (CR 104.2b)
      class WinGame < GameEndEffect
        primitive :effect, :win_game,
                  description: "Each referenced player (default you) wins the game: every opponent loses it.",
                  rules: %w[104.2a 104.2b 104.3f],
                  params: { "to" => "selector" },
                  example: "win_game"

        def apply(engine, ctx) = players(engine, ctx).each { engine.win_game!(it) }
        def to_s = "win the game → #{to}"
      end

      # "You lose the game." (CR 104.3e)
      class LoseGame < GameEndEffect
        primitive :effect, :lose_game,
                  description: "Each referenced player (default you) loses the game.",
                  rules: %w[104.3e 104.4a],
                  params: { "to" => "selector" },
                  example: "lose_game"

        def apply(engine, ctx) = players(engine, ctx).each { engine.lose_game!(it) }
        def to_s = "lose the game → #{to}"
      end
    end
  end
end
