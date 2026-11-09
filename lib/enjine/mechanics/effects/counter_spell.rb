# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Counter a spell or ability (CR 701.6).
      class CounterSpell < Effect
        primitive :effect, :counter, description: "Counter each referenced spell or ability: a spell leaves the " \
                                                  "stack for its owner's graveyard without resolving, an ability " \
                                                  "ceases to exist. A spell that can't be countered stays.",
                                     rules: %w[701.6a 701.6b 101.2], params: { "to" => "selector" },
                                     example: { "counter" => { "to" => { "target" => 0 } } }
        def self.keys = %w[to if]

        def apply(engine, ctx)
          refs(engine, ctx).each { engine.counter!(it) if engine.state.stack.include?(it) }
        end
      end
    end
  end
end
