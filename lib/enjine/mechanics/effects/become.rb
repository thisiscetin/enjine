# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "[It] becomes a Ferengi Scout with base power and toughness 3/4 and gains '...'" (CR 611.2a, 613):
      # one resolved effect that, for its duration, sets creature types (layer 4, CR 205.1a), sets base
      # power and toughness (layer 7b) and grants abilities (layer 6). The affected set is locked in as it
      # resolves (CR 611.2c). `duration: "indefinite"` lasts as long as the permanent stays on the
      # battlefield. Granted abilities are part of this card's data, referenced "<this effect's ref>:<j>"
      # (CardDefinition#effect_granted); on the permanent they are "granted:<card>:<ref>:<j>".
      class Become < Effect
        DURATIONS = %w[end_of_turn indefinite].freeze
        GRANTABLE = %i[triggered mana play_from additional_land_plays].freeze

        primitive :effect, :become,
                  description: "Each referenced permanent becomes what the parameters say, for `duration` " \
                               "(end_of_turn, default, or indefinite: as long as it stays on the battlefield): its " \
                               "creature types are exactly `creature_types` (layer 4), its base power and toughness " \
                               "are `base_power_toughness` (layer 7b), and it has the `abilities` (layer 6: " \
                               "triggered, mana, play_from or additional_land_plays abilities).",
                  rules: %w[611.2a 611.2b 611.2c 613.1d 613.1f 613.4b 205.1a 514.2],
                  params: { "creature_types" => "list of creature types (replaces the others)",
                            "base_power_toughness" => "{\"power\": n, \"toughness\": n}",
                            "abilities" => "list of abilities it gains", "duration" => DURATIONS.join(" | "),
                            "to" => "selector" },
                  example: { "become" => { "creature_types" => %w[ferengi scout],
                                           "base_power_toughness" => { "power" => 3, "toughness" => 4 },
                                           "abilities" => [{ "triggered" => { "when" => { "becomes_tapped" => {} },
                                                                              "effects" => [{ "surveil" => { "amount" => 2 } }] } }],
                                           "duration" => "indefinite", "to" => "self" } }

        attr_reader :ref, :creature_types, :base_power_toughness, :granted_abilities, :duration

        def self.keys = %w[creature_types base_power_toughness abilities duration to if]

        def setup(params, errors, path)
          @ref = "become:#{path}"
          @creature_types = parse_types(Mechanics.fetch_param(params, :creature_types), errors, path)
          @base_power_toughness = parse_power_toughness(Mechanics.fetch_param(params, :base_power_toughness), errors, path)
          @granted_abilities = parse_abilities(params, errors, path)
          @duration = Mechanics.fetch_param(params, :duration) || "end_of_turn"
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
          return unless @creature_types.nil? && @base_power_toughness.nil? && @granted_abilities.empty?

          errors << "#{path}: needs creature_types, base_power_toughness and/or abilities"
        end

        def apply(engine, ctx)
          affected = objects(engine, ctx)
          creatures = affected.select { engine.chars(it).creature? }
          duration = @duration == "indefinite" ? "permanent" : "end_of_turn"
          if creature_types
            engine.add_continuous_effect!("creature_types", ctx, creatures, "types" => creature_types, "duration" => duration)
          end
          if base_power_toughness
            engine.add_continuous_effect!("base_power_toughness", ctx, creatures, base_power_toughness.merge("duration" => duration))
          end
          return if granted_abilities.empty?

          engine.add_continuous_effect!("abilities", ctx, affected, "card" => engine.object(ctx.object).card, "ref" => ref,
                                                                    "duration" => duration)
        end

        def nested_effects = granted_abilities.flat_map(&:try_effects)

        def to_s
          bits = []
          bits << creature_types.join(" ") if creature_types
          bits << "base #{base_power_toughness.values.join("/")}" if base_power_toughness
          bits << "\"#{granted_abilities.join("; ")}\"" unless granted_abilities.empty?
          "becomes #{bits.join(", ")}#{" until end of turn" if duration == "end_of_turn"} → #{to}"
        end

        private

        def parse_types(raw, errors, path)
          return nil if raw.nil?

          ok = raw.is_a?(Array) && !raw.empty? && raw.all? { CardDefinition::SUBTYPE_FORMAT.match?(it.to_s) }
          errors << "#{path}.creature_types: must be a non-empty list of lowercase creature types" unless ok
          ok ? raw.map(&:to_s).freeze : nil
        end

        def parse_power_toughness(raw, errors, path)
          return nil if raw.nil?

          unless raw.is_a?(Hash)
            errors << "#{path}.base_power_toughness: must be {\"power\": n, \"toughness\": n}"
            return nil
          end
          sub = "#{path}.base_power_toughness"
          Mechanics.check_keys(raw, %w[power toughness], errors, sub)
          { "power" => Mechanics.integer_param(raw, :power, errors, sub, min: 0),
            "toughness" => Mechanics.integer_param(raw, :toughness, errors, sub, min: 0) }.freeze
        end

        def parse_abilities(params, errors, path)
          Mechanics.list_param(params, :abilities, errors, path).each_with_index.filter_map do |entry, j|
            ability = Mechanics.build_entry(:ability, entry, errors, "#{path}.abilities[#{j}]")
            next ability if ability.nil? || (GRANTABLE.include?(ability.kind) && !(ability.kind == :play_from && ability.self?))

            errors << "#{path}.abilities[#{j}]: only triggered, mana, play_from (for other cards) and " \
                      "additional_land_plays abilities can be gained"
            nil
          end.freeze
        end
      end
    end
  end
end
