# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # A mana cost for an activated ability, e.g. {"mana": "{1}{R}"} (CR 602.2b, 601.2f).
      class ManaPayment < Primitive
        primitive :cost, :mana,
                  description: "Pay mana as part of an activation. Paid during the activation by spending mana from " \
                               "your pool, tapping sources one at a time.",
                  rules: %w[601.2g 601.2h 602.2b],
                  params: { "(value)" => "mana cost string, e.g. \"{1}{R}\"" },
                  example: { "mana" => "{1}{R}" }

        attr_reader :mana_cost

        def self.scalar_params? = true

        # Accepts {"mana": "{1}{R}"}; the params object here is the cost string itself.
        def self.build(params, errors, path, **)
          new(Mana.parse_cost(params, errors, path) || Mana::Cost.new(generic: 0, colored: {}))
        end

        def initialize(mana_cost)
          super()
          @mana_cost = mana_cost
          freeze
        end

        def mana? = true
        def payable?(_engine, _object) = true
        def pay!(_engine, _object) = nil
        def to_s = mana_cost.to_s
      end
    end
  end
end
