# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "[It] becomes a Ferengi Scout with base power and toughness 3/4 and gains '...'" (CR 611.2a, 613):
      # one resolved effect that, for its duration, adds card types, supertypes and subtypes "in addition to
      # its other types" and sets creature types (layer 4, CR 205.1a-b), sets colors (layer 5), grants keywords
      # and abilities (layer 6) and sets base power and toughness (layer 7b). "This land becomes a 3/3 red
      # Elemental creature with haste until end of turn. It's still a land." is one `become`. The affected set
      # is locked in as it resolves (CR 611.2c). `duration: "indefinite"` lasts as long as the permanent stays
      # on the battlefield. Granted abilities are part of this card's data, referenced "<this effect's ref>:<j>"
      # (CardDefinition#effect_granted); on the permanent they are "granted:<card>:<ref>:<j>".
      class Become < Effect
        DURATIONS = %w[end_of_turn until_your_next_turn indefinite while_source_on_battlefield
                       while_you_control_source].freeze
        GRANTABLE = %i[triggered mana activated play_from additional_land_plays hexproof_from protection_from].freeze
        # Card types an effect can add (CR 205.1b); instants, sorceries and planeswalkers aren't permanents it makes.
        ADDABLE_TYPES = %w[artifact creature enchantment land].freeze
        CHANGES = %w[types supertypes subtypes creature_types colors loses_abilities keywords base_power_toughness
                     abilities].freeze

        primitive :effect, :become,
                  description: "Each referenced permanent becomes what the parameters say, for `duration` " \
                               "(end_of_turn, default; until_your_next_turn: until your next turn begins; indefinite: " \
                               "as long as it stays on the battlefield; " \
                               "while_source_on_battlefield: for as long as this effect's source remains on the " \
                               "battlefield; while_you_control_source: for as long as you control it): it has " \
                               "the card `types`, `supertypes` and `subtypes` in addition to its other types (layer 4, " \
                               "\"becomes an artifact creature\"), its creature types are exactly `creature_types` " \
                               "(layer 4), its colors are `colors` (layer 5), with `loses_abilities: true` it loses all " \
                               "the abilities it had (layer 6; abilities granted later, keyword counters put on it " \
                               "later and this effect's own `keywords` and `abilities` stay, CR 613.7), it has the " \
                               "`keywords` and `abilities` " \
                               "(layer 6: triggered, activated, mana, play_from or additional_land_plays abilities) and " \
                               "its base " \
                               "power and toughness are `base_power_toughness` (layer 7b). A permanent that becomes a " \
                               "creature has its printed power and toughness (a Vehicle's), or 0/0.",
                  rules: %w[611.2a 611.2b 611.2c 613.1d 613.1e 613.1f 613.4b 613.7b 205.1a 205.1b 301.7b 514.2],
                  params: { "types" => "card types it also has: #{ADDABLE_TYPES.join(", ")}",
                            "supertypes" => "supertypes it also has (\"legendary\")",
                            "subtypes" => "subtypes it also has (\"in addition to its other types\")",
                            "creature_types" => "list of creature types (replaces the others)",
                            "colors" => "list of W, U, B, R, G (replaces its colors)",
                            "loses_abilities" => "true: it loses all abilities (\"loses all abilities\")",
                            "keywords" => "list of keywords it gains",
                            "base_power_toughness" => "{\"power\": n, \"toughness\": n}",
                            "abilities" => "list of abilities it gains", "duration" => DURATIONS.join(" | "),
                            "to" => "selector" },
                  example: { "become" => { "types" => ["creature"], "creature_types" => ["elemental"], "colors" => ["R"],
                                           "base_power_toughness" => { "power" => 3, "toughness" => 3 },
                                           "keywords" => ["haste"], "to" => "self" } }

        attr_reader :ref, :creature_types, :base_power_toughness, :granted_abilities, :duration, :card_types,
                    :supertypes, :subtypes, :colors, :keywords

        UNTIL = { "end_of_turn" => " until end of turn", "until_your_next_turn" => " until your next turn" }.freeze

        def self.keys = CHANGES + %w[duration to if]

        # A list of registered names (card types, supertypes, keywords) as symbols; [] when absent.
        def self.names_param(params, key, category, errors, path, allowed: nil)
          raw = Mechanics.fetch_param(params, key)
          return [].freeze if raw.nil?

          names = raw.is_a?(Array) ? raw.map { it.to_s.downcase.tr(" -", "__") } : []
          ok = !names.empty? && names.all? { Enjine.registry.fetch(category, it) && (allowed.nil? || allowed.include?(it)) }
          unless ok
            choices = allowed || Enjine.registry.names(category)
            errors << "#{path}.#{key}: must be a non-empty list of #{category}s (#{choices.join(", ")})"
            return [].freeze
          end
          names.uniq.map(&:to_sym).freeze
        end

        def setup(params, errors, path)
          @ref = "become:#{path}"
          @card_types = Become.names_param(params, :types, :type, errors, path, allowed: ADDABLE_TYPES)
          @supertypes = Become.names_param(params, :supertypes, :supertype, errors, path)
          @subtypes = parse_types(Mechanics.fetch_param(params, :subtypes), errors, "#{path}.subtypes", "subtypes") || []
          @creature_types = parse_types(Mechanics.fetch_param(params, :creature_types), errors, "#{path}.creature_types",
                                        "creature types")
          @colors = Become.parse_colors(Mechanics.fetch_param(params, :colors), errors, path)
          @loses_abilities = Mechanics.fetch_param(params, :loses_abilities)
          errors << "#{path}.loses_abilities: must be true (or absent)" unless [nil, true].include?(@loses_abilities)
          @keywords = Become.names_param(params, :keywords, :keyword, errors, path)
          @base_power_toughness = Become.parse_power_toughness(Mechanics.fetch_param(params, :base_power_toughness), errors, path)
          @granted_abilities = parse_abilities(params, errors, path)
          @duration = Mechanics.fetch_param(params, :duration) || "end_of_turn"
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
          return unless CHANGES.all? { Mechanics.fetch_param(params, it).nil? }

          errors << "#{path}: needs at least one of #{CHANGES.join(", ")}"
        end

        def loses_abilities? = @loses_abilities == true

        # The state.effects duration and the details it needs. "For as long as [source] remains on the
        # battlefield" does nothing if the source has already left as this resolves (CR 611.2b).
        def duration_details(engine, ctx)
          case @duration
          when "indefinite" then { "duration" => "permanent" }
          when "end_of_turn", "until_your_next_turn" then { "duration" => @duration } # CR 611.2a, 500.1
          else
            holds = engine.source_duration_holds?(@duration, ctx.source, ctx.controller)
            holds ? { "duration" => @duration, "source" => ctx.source } : nil
          end
        end

        def apply(engine, ctx)
          affected = objects(engine, ctx)
          lasting = duration_details(engine, ctx) or return
          add = ->(kind, details) { engine.add_continuous_effect!(kind, ctx, affected, details.merge(lasting)) }
          # Removal first: this effect's own keywords and abilities come after it (CR 613.7b).
          add.call("lose_abilities", {}) if loses_abilities?
          unless card_types.empty? && supertypes.empty? && subtypes.empty?
            add.call("add_types", "types" => card_types.map(&:to_s), "supertypes" => supertypes.map(&:to_s), "subtypes" => subtypes)
          end
          creatures = affected.select { engine.chars(it).creature? } # after the types above are added
          engine.add_continuous_effect!("creature_types", ctx, creatures, { "types" => creature_types }.merge(lasting)) if creature_types
          add.call("colors", "colors" => colors) if colors
          add.call("grant", "keywords" => keywords.map(&:to_s)) unless keywords.empty?
          engine.add_continuous_effect!("base_power_toughness", ctx, creatures, base_power_toughness.merge(lasting)) if base_power_toughness
          return if granted_abilities.empty?

          add.call("abilities", "card" => engine.object(ctx.object).card, "ref" => ref)
        end

        def nested_effects = granted_abilities.flat_map(&:try_effects)

        def to_s
          bits = []
          bits << "loses all abilities" if loses_abilities?
          bits << [*supertypes, *colors, *subtypes, *card_types].join(" ") unless (card_types + supertypes + subtypes).empty?
          bits << creature_types.join(" ") if creature_types
          bits << "base #{base_power_toughness.values.join("/")}" if base_power_toughness
          bits << keywords.join(", ") unless keywords.empty?
          bits << "\"#{granted_abilities.join("; ")}\"" unless granted_abilities.empty?
          "becomes #{bits.join(", ")}#{UNTIL[duration]} → #{to}"
        end

        def self.parse_colors(raw, errors, path)
          return nil if raw.nil?

          ok = raw.is_a?(Array) && raw.all? { Mana::COLORS.include?(it.to_s.upcase.to_sym) }
          errors << "#{path}.colors: must be a list of W, U, B, R, G ([] for colorless)" unless ok
          ok ? raw.map { it.to_s.upcase }.uniq.freeze : nil
        end

        def self.parse_power_toughness(raw, errors, path)
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

        private

        def parse_types(raw, errors, path, noun)
          return nil if raw.nil?

          ok = raw.is_a?(Array) && !raw.empty? && raw.all? { CardDefinition::SUBTYPE_FORMAT.match?(it.to_s) }
          errors << "#{path}: must be a non-empty list of lowercase #{noun}" unless ok
          ok ? raw.map(&:to_s).freeze : nil
        end

        def parse_abilities(params, errors, path)
          Mechanics.list_param(params, :abilities, errors, path).each_with_index.filter_map do |entry, j|
            ability = Mechanics.build_entry(:ability, entry, errors, "#{path}.abilities[#{j}]")
            next ability if ability.nil? || (GRANTABLE.include?(ability.kind) && !(ability.kind == :play_from && ability.self?))

            errors << "#{path}.abilities[#{j}]: only triggered, activated, mana, play_from (for other cards), " \
                      "additional_land_plays, hexproof_from and protection_from abilities can be gained"
            nil
          end.freeze
        end
      end
    end
  end
end
