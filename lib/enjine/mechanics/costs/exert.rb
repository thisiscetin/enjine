# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # "Exert [this permanent]" as a cost (CR 701.43a): it won't untap during your next untap step. It can be
      # exerted tapped or untapped, and again before that untap step (one untap step is skipped, CR 701.43b);
      # only a permanent can be (CR 701.43c).
      class Exert < Primitive
        primitive :cost, :exert,
                  description: "Exert this permanent: it doesn't untap during your next untap step.",
                  rules: %w[701.43a 701.43b 701.43c],
                  example: "exert"

        INSTANCE = new.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          INSTANCE
        end

        def payable?(_engine, object) = object.zone == :battlefield
        def pay!(engine, object) = engine.exert!(object)
        def mana? = false
        def to_s = "Exert this"
      end
    end
  end
end
