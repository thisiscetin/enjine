# frozen_string_literal: true

require_relative "../triggers/base"
require_relative "../keywords/station"

module Enjine
  module Mechanics
    module Effects
      # The effect of a class level bar's activated ability (CR 717.2a): "This Class's level becomes N."
      class GainClassLevel < Effect
        def self.keys = %w[to]

        attr_reader :level

        def setup(params, _errors, _path) = @level = params["level"]
        def apply(engine, ctx) = objects(engine, ctx).each { engine.set_class_level!(engine.object(it), level) }
        def to_s = "this Class's level becomes #{level}"
      end
    end

    module Abilities
      # A class level bar "[Cost]: Level N — [Abilities]" (CR 717.2a): "[Cost]: This Class's level becomes N.
      # Activate only if this Class is level N-1 and only as a sorcery" and "As long as this Class is level N or
      # greater, it has [abilities]." Abilities printed in its text box section are its `abilities` and
      # `keywords`; those above the first level bar are ordinary abilities (CR 717.3).
      class ClassLevel < ActivatedAbility
        primitive :ability, :class_level,
                  description: "A class level bar: `cost` (a mana cost string or a list of costs): this permanent's " \
                               "level becomes `level`; activate only if its level is `level` - 1, as a sorcery. While " \
                               "its level is `level` or greater it has `keywords` and `abilities`. A permanent " \
                               "without a level is level 1.",
                  rules: %w[717.2a 717.2b 717.2d 717.3 602.5d],
                  params: { "level" => "integer >= 2", "cost" => "mana cost string or list of costs",
                            "keywords" => "list of keywords", "abilities" => "list of abilities" },
                  example: { "class_level" => { "level" => 2, "cost" => "{1}{R}",
                                                "abilities" => [{ "triggered" => {
                                                  "when" => { "discards" => {} },
                                                  "effects" => [{ "deal_damage" => { "amount" => 2, "to" => "each_opponent" } }]
                                                } }] } }

        attr_reader :level, :keywords, :nested_abilities

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[level cost keywords abilities], errors, path)
          level = Mechanics.integer_param(params, :level, errors, path, min: 2).to_i
          raw = Mechanics.fetch_param(params, :cost)
          costs = raw.is_a?(String) ? [Costs::ManaPayment.build(raw, errors, "#{path}.cost")] : parse_costs(params, errors, path)
          errors << "#{path}.cost: required" if raw.nil?
          keywords = StationSymbol.build_keywords(params, errors, path)
          nested = StationSymbol.build_abilities(params, errors, path)
          nested.each_with_index do |ability, i|
            errors << "#{path}.abilities[#{i}]: class level bars can't be nested" if ability.is_a?(ClassLevel)
          end
          effect = Effects::GainClassLevel.new(to: Selector.new(:self), params: { "level" => level }, errors: errors, path: path)
          new(sorcery: true, targets: [].freeze, costs: costs.compact.freeze, effects: [effect].freeze,
              level: level, keywords: keywords.freeze, nested_abilities: nested.freeze)
        end

        def initialize(level:, keywords:, nested_abilities:, **)
          @level = level
          @keywords = keywords
          @nested_abilities = nested_abilities
          super(**)
        end

        # No power/toughness box (Engine::Characteristics#station_symbol_layers reads it).
        def power = nil

        # CR 717.2a: only if this Class is level N-1.
        def restriction_met?(engine, index, source)
          engine.class_level(engine.object(source)) == level - 1 && super
        end

        def to_s
          bits = keywords.map(&:to_s) + nested_abilities.map(&:to_s)
          "#{costs.join(", ")}: Level #{level}#{" — #{bits.join("; ")}" unless bits.empty?}"
        end
      end
    end

    module Triggers
      # "When this Class becomes level N" (CR 717.2a): its level bar for N resolved.
      class BecomesLevel < Trigger
        primitive :trigger, :becomes_level,
                  description: "This permanent's level becomes `level` (a class level bar's ability resolves).",
                  rules: %w[717.2a 603.2],
                  params: { "level" => "integer >= 2" },
                  example: { "becomes_level" => { "level" => 3 } }

        def self.keys = %w[level]
        def event_class = Events::ClassLevelChanged

        def setup(params, errors, path)
          @level = Mechanics.integer_param(params, :level, errors, path, min: 2)
        end

        def match?(_engine, event, source) = event.object == source["id"] && event.level == @level
        def to_s = "When this becomes level #{@level}"
      end
    end
  end
end
