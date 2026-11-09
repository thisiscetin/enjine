# frozen_string_literal: true

module Enjine
  module Mechanics
    module Keywords
      # Increment (CR 702.191a): "Whenever you cast a spell, if this permanent is a creature and the amount of
      # mana spent to cast that spell is greater than this creature's power or this creature's toughness, put a
      # +1/+1 counter on this creature." Each instance triggers separately (CR 702.191b).
      class Increment < Primitive
        primitive :keyword, :increment,
                  description: "Whenever you cast a spell, if this is a creature and the mana spent to cast that " \
                               "spell is greater than its power or its toughness, put a +1/+1 counter on it.",
                  rules: %w[702.191a 702.191b 603.4], example: { "keywords" => ["increment"] }

        # "greater than this creature's [stat]": mana spent - stat >= 1.
        def self.exceeds(stat)
          { "amount" => { "plus" => [{ "mana_spent" => { "of" => { "triggering" => "object" } } },
                                     { "times" => [{ stat => "self" }, -1] }] }, "at_least" => 1 }
        end

        ABILITY = { "triggered" => {
          "when" => { "cast" => { "controller" => "you" } },
          "if" => { "all" => [{ "source" => "creature" }, { "any" => [exceeds("power"), exceeds("toughness")] }] },
          "effects" => [{ "add_counters" => { "counter" => "+1/+1", "amount" => 1, "to" => "self" } }]
        } }.freeze

        def self.intrinsic_abilities = @intrinsic_abilities ||= [Keywords.ability_from_data(ABILITY, "increment")].freeze
      end
    end
  end
end
