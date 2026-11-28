# frozen_string_literal: true

require_relative "kicker"

module Enjine
  module Mechanics
    module Abilities
      # Offspring (CR 702.175a-b): "You may pay an additional [cost] as you cast this spell" and "When this
      # permanent enters, if its offspring cost was paid, create a token that's a copy of it, except it's 1/1."
      # The cost is announced like kicker (the `choose_kicker` decision) without making the spell kicked; the
      # triggered ability comes with the keyword (linked, like evoke's). `{"cast_with": "offspring"}` holds when
      # it was paid.
      class Offspring < SpellCost
        primitive :ability, :offspring,
                  description: "Offspring: as you cast this spell you may also pay `cost` (announced with the " \
                               "`choose_kicker` decision; the spell isn't kicked). When the permanent enters, if its " \
                               "offspring cost was paid, create a 1/1 token copy of it (a triggered ability that comes " \
                               "with the keyword). `{\"cast_with\": \"offspring\"}` holds if it was paid.",
                  rules: %w[702.175a 702.175b 601.2b 601.2f 601.2h 707.9b 603.4],
                  params: { "cost" => "mana cost string, or a list of costs" },
                  example: { "offspring" => { "cost" => "{2}" } }

        TOKEN = { "triggered" => { "when" => { "enters" => {} }, "if" => { "cast_with" => "offspring" },
                                   "effects" => [{ "create_token_copy" => { "of" => "self",
                                                                            "except" => { "power" => 1, "toughness" => 1 } } }] } }.freeze

        attr_reader :linked_abilities

        # `{"cost": "{2}"}` or `{"cost": [{"mana": "{2}"}, ...]}`.
        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost], errors, path)
          raw = Mechanics.fetch_param(params, :cost)
          raw = [{ "mana" => raw }] if raw.is_a?(String)
          linked = [Mechanics.build_entry(:ability, TOKEN, errors, "#{path}.token")].compact.freeze
          new(super({ "cost" => raw }, errors, path).costs, linked)
        end

        def initialize(costs, linked = [].freeze)
          @linked_abilities = linked
          super(costs, optional: true)
        end

        def kind = :kicker
        def to_s = "Offspring #{costs.join(", ")}"
      end
    end
  end
end
