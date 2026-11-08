# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # {T}: tap this permanent (CR 107.5, 602.5a).
      class Tap < Primitive
        primitive :cost, :tap,
                  description: "{T} — tap the permanent the ability belongs to. Requires it to be untapped.",
                  rules: %w[107.5 602.5a],
                  example: "tap"

        INSTANCE = new.freeze

        def self.build(params, errors, path)
          Mechanics.check_keys(params, [], errors, path)
          INSTANCE
        end

        def payable?(engine, object) = !object.tapped && !engine.summoning_sick_for_tap?(object)

        def pay!(engine, object)
          engine.tap!(object)
        end

        def to_s = "{T}"
      end
    end
  end
end
