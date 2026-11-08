# frozen_string_literal: true

module Enjine
  module Mechanics
    module Keywords
      # Sunburst (CR 702.44): enters with a counter for each color of mana spent to cast it.
      class Sunburst < Primitive
        primitive :keyword, :sunburst,
                  description: "As this permanent enters from the stack as a resolving spell, it gets a +1/+1 counter " \
                               "(a creature) or a charge counter (otherwise) for each color of mana spent to cast it.",
                  rules: %w[702.44a 702.44b], example: { "keywords" => ["sunburst"] }

        COLORS = Mana::COLORS.map(&:to_s).freeze

        # The counters a resolving spell enters with (CR 702.44a); type-changing effects are ignored,
        # so the printed card types decide the kind. CR 702.44b: only colored mana counts.
        def self.entering_counters(engine, spell)
          printed = engine.chars(spell)
          return {} unless printed.keyword?(:sunburst)

          colors = (spell.mana_spent || []).uniq & COLORS
          return {} if colors.empty?

          { printed.creature? ? "+1/+1" : "charge" => colors.size }
        end
      end
    end
  end
end
