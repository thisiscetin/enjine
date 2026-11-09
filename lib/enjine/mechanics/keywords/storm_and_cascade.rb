# frozen_string_literal: true

require_relative "../abilities/play_permissions"

module Enjine
  module Mechanics
    module Triggers
      # The number of spells cast this turn before the one whose cast is being looked at (its SpellCast is
      # already in the turn's history, Engine::TurnHistory): a cast trigger's "that many" (storm, CR 702.40a).
      def self.spells_before(engine)
        engine.state.players.each_index.sum { engine.turn_log(it).fetch("spells", []).size } - 1
      end
    end

    module Effects
      # Cascade's effect (CR 702.85a): exile cards from the top of your library until you exile a nonland card
      # whose mana value is less than this spell's; you may cast it without paying its mana cost; then all
      # exiled cards not cast go on the bottom of your library in a random order. Discover's steps with
      # another limit and miss.
      class Cascade < Discover
        def self.build_for_keyword = new(to: Selector.new(:you), params: { "amount" => 0 }, errors: [], path: "cascade")

        def to_s = "cascade"

        private

        # Less than this spell's mana value (X included on the stack, CR 202.3e); if the spell has left the
        # stack, its card's mana value.
        def limit(engine, ctx)
          spell = engine.state.objects[ctx.source]
          cost = spell ? engine.chars(spell).mana_cost&.with_x(spell.x.to_i) : triggering_cost(engine, ctx)
          cost ? cost.mana_value - 1 : -1
        end

        def triggering_cost(engine, ctx)
          card = Selector.memory(engine, ctx).dig("triggering", "card")
          card && engine.catalog.fetch(card).mana_cost
        end

        def miss_type = "decline"
        def prompt = "Cascade: you may cast it without paying its mana cost"
        def miss!(_engine, _hit) = nil
      end
    end

    module Keywords
      # Storm (CR 702.40a): "When you cast this spell, copy it for each other spell that was cast before it this
      # turn. If the spell has any targets, you may choose new targets for any of the copies." Each instance
      # triggers separately (CR 702.40b).
      class Storm < Primitive
        primitive :keyword, :storm,
                  description: "When you cast this spell, copy it for each other spell cast before it this turn; you " \
                               "may choose new targets for the copies.",
                  rules: %w[702.40a 702.40b 707.10], example: { "keywords" => ["storm"] }

        ABILITY = { "triggered" => { "when" => { "cast" => { "self" => true } },
                                     "effects" => [{ "copy_spell" => { "of" => "self", "amount" => { "triggering" => "amount" },
                                                                       "new_targets" => true } }] } }.freeze

        def self.intrinsic_abilities = @intrinsic_abilities ||= [Keywords.ability_from_data(ABILITY, "storm")].freeze
      end

      # Cascade (CR 702.85a): "When you cast this spell, exile cards from the top of your library until you exile
      # a nonland card whose mana value is less than this spell's mana value. You may cast that card without
      # paying its mana cost if the resulting spell's mana value is less than this spell's mana value. Then put
      # all cards exiled this way that weren't cast on the bottom of your library in a random order." Each
      # instance triggers separately (CR 702.85c).
      class Cascade < Primitive
        primitive :keyword, :cascade,
                  description: "When you cast this spell, exile cards from the top of your library until you exile a " \
                               "nonland card with lesser mana value. You may cast it without paying its mana cost. " \
                               "Then the exiled cards not cast go on the bottom of your library in a random order.",
                  rules: %w[702.85a 702.85c 608.2g], example: { "keywords" => ["cascade"] }

        def self.intrinsic_abilities
          @intrinsic_abilities ||= begin
            trigger = Keywords.ability_from_data({ "triggered" => { "when" => { "cast" => { "self" => true } },
                                                                    "effects" => [] } }, "cascade").trigger
            [Abilities::TriggeredAbility.new(trigger: trigger, targets: [].freeze,
                                             effects: [Effects::Cascade.build_for_keyword].freeze)].freeze
          end
        end
      end
    end
  end
end
