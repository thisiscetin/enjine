# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Tap permanents (CR 701.26).
      class TapEffect < Effect
        primitive :effect, :tap, description: "Tap each referenced permanent.", rules: %w[701.26a],
                                 params: { "to" => "selector" }, example: { "tap" => { "to" => { "target" => 0 } } }
        def self.keys = %w[to if]
        def apply(engine, ctx) = objects(engine, ctx).each { engine.tap!(engine.object(it)) unless engine.object(it).tapped }
      end

      # Untap permanents (CR 701.26).
      class UntapEffect < Effect
        primitive :effect, :untap, description: "Untap each referenced permanent.", rules: %w[701.26b],
                                   params: { "to" => "selector" }, example: { "untap" => { "to" => "self" } }
        def self.keys = %w[to if]
        def apply(engine, ctx) = objects(engine, ctx).each { engine.untap!(engine.object(it)) }
      end
    end
  end
end
