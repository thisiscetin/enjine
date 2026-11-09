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

      # CR 702.126a-c: improvise. For each generic mana in the spell's total cost, an untapped artifact you control
      # may be tapped instead of paying it (a `pay_cost` option `{type: "improvise", object: id}`).
      class Improvise < Primitive
        primitive :keyword, :improvise,
                  description: "Improvise: while paying this spell's total cost you may tap untapped artifacts you " \
                               "control, each paying for {1} of its generic part (pay_cost option `{type: " \
                               "\"improvise\", object: id}`). It isn't an alternative or additional cost.",
                  rules: %w[702.126a 702.126b 702.126c],
                  example: { "keywords" => ["improvise"] }
      end
    end
  end
end
