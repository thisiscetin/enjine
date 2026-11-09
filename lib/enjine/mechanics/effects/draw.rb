# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Draw cards (CR 121).
      class Draw < Effect
        primitive :effect, :draw, description: "Each referenced player draws `amount` cards (default: you).",
                                  rules: %w[121.1 121.2], params: { "amount" => "integer", "to" => "selector" },
                                  example: { "draw" => { "amount" => 2 } }
        def self.default_to = "you"
        def apply(engine, ctx) = players(engine, ctx).each { |i| amount_for(engine, ctx).times { engine.draw!(i) } }
      end
    end
  end
end
