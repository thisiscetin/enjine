# frozen_string_literal: true

module Enjine
  module Mechanics
    module Keywords
      # CR 702.51a-d: convoke. While paying the spell's total cost, each untapped creature you control may be
      # tapped to pay {1} or one mana of one of its colors (a `pay_cost` option `{type: "convoke", object: id}`).
      class Convoke < Primitive
        primitive :keyword, :convoke,
                  description: "Convoke: while paying this spell's total cost you may tap untapped creatures you " \
                               "control, each paying for {1} or one mana of one of its colors (pay_cost option " \
                               "`{type: \"convoke\", object: id}`). It isn't an alternative or additional cost.",
                  rules: %w[702.51a 702.51b 702.51c 702.51d],
                  example: { "keywords" => ["convoke"] }
      end
    end
  end
end
