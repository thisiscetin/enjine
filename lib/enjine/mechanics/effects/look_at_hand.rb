# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Looking at a player's hand (CR 701.20e): the controller sees those cards; others don't.
      class LookAtHand < Effect
        primitive :effect, :look_at_hand,
                  description: "You look at each referenced player's hand (other players don't see the cards).",
                  rules: %w[701.20e], params: { "to" => "selector of players" },
                  example: { "look_at_hand" => { "to" => { "target" => 0 } } }
        def self.keys = %w[to if]
        def apply(engine, ctx) = players(engine, ctx).each { engine.look_at!(ctx.controller, it, engine.player(it).hand) }
      end
    end
  end
end
