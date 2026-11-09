# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Mill N cards (CR 701.17).
      class Mill < Effect
        primitive :effect, :mill, description: "Each referenced player puts the top `amount` cards of their library " \
                                               "into their graveyard (default: you).",
                                  rules: %w[701.17a], params: { "amount" => "integer", "to" => "selector" },
                                  example: { "mill" => { "amount" => 2, "to" => "each_opponent" } }
        def self.default_to = "you"

        def apply(engine, ctx)
          players(engine, ctx).each do |index|
            engine.player(index).library.first(amount_for(engine, ctx)).each { engine.move!(it, :graveyard, reason: "mill") }
          end
        end
      end
    end
  end
end
