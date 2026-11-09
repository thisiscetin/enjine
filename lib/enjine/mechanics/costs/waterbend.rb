# frozen_string_literal: true

require_relative "mana"

module Enjine
  module Mechanics
    module Costs
      # Waterbend [cost] (CR 701.67a): "Pay [cost]. For each generic mana in that cost, you may tap an untapped
      # artifact or creature you control rather than pay that mana." A mana cost, so it adds to the total cost
      # like any other (an activated ability's cost, an additional cost, kicker); while paying, the `pay_cost`
      # option `{type: "waterbend", object: id}` taps one of those permanents for {1}, at most as many times as
      # the waterbend cost has generic mana (CR 701.67b). Paying it is waterbending (CR 701.67c).
      class Waterbend < ManaPayment
        primitive :cost, :waterbend,
                  description: "Waterbend [cost]: pay this mana cost; for each generic mana in it you may instead tap " \
                               "an untapped artifact or creature you control (pay_cost option `{type: \"waterbend\", " \
                               "object: id}`). Only the waterbend cost's own generic mana can be paid this way.",
                  rules: %w[701.67a 701.67b 701.67c],
                  params: { "(value)" => "mana cost string, e.g. \"{3}\" or \"{X}\"" },
                  example: { "waterbend" => "{3}" }

        # The generic mana tapping may pay for, with X announced.
        def generic(x_value) = mana_cost.with_x(x_value).generic

        def to_s = "Waterbend #{mana_cost}"
      end
    end
  end
end
