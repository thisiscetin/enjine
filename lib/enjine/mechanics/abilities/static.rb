# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # A static ability that modifies permanents while its source is on the battlefield (CR 604,
      # 611.3, 613): "Creatures you control get +1/+1", "Other Elves you control have reach",
      # a keyword only during your turn, an Aura that sets creature types, creatures that gain a mana
      # ability. Unlike a resolved effect, the set of affected
      # objects is re-evaluated continuously (CR 611.3a).
      class StaticAbility < Primitive
        primitive :ability, :static,
                  description: "While its source is on the battlefield (and its `if` condition holds), every permanent " \
                               "it `affects` gets `pump` (fixed or computed amounts, layer 7c), the `keywords` and " \
                               "granted `abilities` (layer 6, triggered, activated or mana abilities), and with " \
                               "`creature_types` has exactly those creature types (layer 4); `loses_abilities: true` " \
                               "removes the abilities it had before (layer 6, in timestamp order: later grants and " \
                               "keyword counters stay, CR 613.7), `colors` sets its colors (layer 5) and " \
                               "`base_power_toughness` its base power and toughness (layer 7b); `types` are card " \
                               "types it has in addition " \
                               "to its other types (\"this Vehicle is an artifact creature\", layer 4) and `subtypes` subtypes it has in " \
                               "addition to its other types (\"is a Wizard in addition to its other types\", layer 4). " \
                               "`affects` is " \
                               "{\"each\": filter, " \
                               "\"controller\": you|opponent|any, \"other\": true} (relative to the source's " \
                               "controller), \"self\", or \"attached\" (\"equipped/enchanted creature\").",
                  rules: %w[604.1 604.2 611.3a 612.8 613.1c 205.1a 613.1d 613.1e 613.1f 613.4b 613.4c 613.7a 613.8a 205.1a 205.1b 301.5f 303.4m],
                  params: { "affects" => "{\"each\": filter, \"controller\": ..., \"other\": bool}, \"self\" or \"attached\"",
                            "if" => "condition (\"as long as ...\", \"during your turn\")",
                            "pump" => "{\"power\": amount, \"toughness\": amount} (\"gets +1/+1 for each ...\")",
                            "keywords" => "list of keywords", "creature_types" => "list of creature types (replaces the others)",
                            "types" => "list of card types it also has (in addition to its other types)",
                            "subtypes" => "list of subtypes it also has (in addition to its other types), or \"chosen\": " \
                                          "the type chosen as its source entered",
                            "abilities" => "list of triggered, activated or mana abilities the affected permanents have",
                            "loses_abilities" => "true: it loses all abilities (\"loses all abilities\")",
                            "colors" => "list of W, U, B, R, G: its colors are exactly these ([] for colorless)",
                            "base_power_toughness" => "{\"power\": n, \"toughness\": n}",
                            "set_types" => "list of card types: its card types are exactly these",
                            "name" => "its name (\"named Humble Merchant\")" },
                  example: { "static" => { "affects" => { "each" => "creature", "controller" => "you" },
                                           "pump" => { "power" => 1, "toughness" => 1 } } }

        GRANTABLE = %i[triggered mana activated hexproof_from protection_from tapping_power].freeze
        # Data that would make the layer pass depend on its own result (CR 613.8).
        LIVE = %w[power toughness greatest_power attacking blocking tapped].freeze
        KEYS = %w[affects if pump keywords creature_types abilities types subtypes loses_abilities colors
                  base_power_toughness set_types name].freeze

        attr_reader :filter, :controller, :other, :keywords, :creature_types, :condition, :granted, :card_types, :subtypes,
                    :colors, :base_power_toughness, :set_types, :name

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, KEYS, errors, path)
          affects = Mechanics.fetch_param(params, :affects)
          filter, controller, other = parse_affects(affects, errors, path)
          raw_if = Mechanics.fetch_param(params, :if)
          errors << "#{path}.if: can't depend on power, toughness or combat status (CR 613.8)" if live?(raw_if)
          condition = raw_if && Condition.build(raw_if, errors, "#{path}.if")
          pump = parse_pump(params, errors, path)
          keywords = parse_keywords(params, errors, path)
          types = parse_subtypes(params, :creature_types, errors, path)
          granted = parse_granted(params, errors, path)
          card_types = Effects::Become.names_param(params, :types, :type, errors, path, allowed: Effects::Become::ADDABLE_TYPES)
          chosen = Mechanics.fetch_param(params, :subtypes) == "chosen" # "is the chosen type in addition" (CR 607.2d)
          subtypes = chosen ? [] : parse_subtypes(params, :subtypes, errors, path) || []
          sets = parse_sets(params, errors, path).merge(chosen_subtype: chosen)
          if pump.empty? && keywords.empty? && types.nil? && granted.empty? && card_types.empty? && subtypes.empty? &&
             sets.values.none?
            errors << "#{path}: needs at least one of #{(KEYS - %w[affects if]).join(", ")}"
          end
          new(filter: filter, controller: controller, other: other, pump: pump, keywords: keywords, creature_types: types,
              condition: condition, granted: granted, card_types: card_types, subtypes: subtypes, **sets)
        end

        # "loses all abilities and is a black 1/1" (layers 5, 6 and 7b): the same shapes as Effects::Become.
        def self.parse_sets(params, errors, path)
          loses = Mechanics.fetch_param(params, :loses_abilities)
          errors << "#{path}.loses_abilities: must be true (or absent)" unless [nil, true].include?(loses)
          { loses_abilities: loses == true,
            colors: Effects::Become.parse_colors(Mechanics.fetch_param(params, :colors), errors, path),
            set_types: params.key?("set_types") ? Effects::Become.names_param(params, :set_types, :type, errors, path,
                                                                             allowed: Effects::Become::ADDABLE_TYPES) : nil,
            name: parse_name(params, errors, path),
            base_power_toughness: Effects::Become.parse_power_toughness(Mechanics.fetch_param(params, :base_power_toughness),
                                                                        errors, path) }
        end

        # "named Legitimate Businessperson" (CR 612.8): a non-empty string.
        def self.parse_name(params, errors, path)
          name = Mechanics.fetch_param(params, :name)
          return nil if name.nil?

          errors << "#{path}.name: must be a non-empty string" unless name.is_a?(String) && !name.strip.empty?
          name.is_a?(String) ? name.freeze : nil
        end

        def self.parse_affects(affects, errors, path)
          return [affects.to_sym, "any", false] if %w[attached self].include?(affects)

          unless affects.is_a?(Hash) && affects["each"]
            errors << "#{path}.affects: must be {\"each\": filter, ...}, \"self\" or \"attached\""
            affects = { "each" => "creature" }
          end
          Mechanics.check_keys(affects, %w[each controller other], errors, "#{path}.affects")
          filter = Mechanics.build_entry(:filter, affects["each"], errors, "#{path}.affects.each")
          live = filter ? filter.live_keys : []
          # CR 613.8: these would make the layer pass depend on its own result.
          errors << "#{path}.affects.each: #{live.join(", ")} can't be used in a static ability yet" unless live.empty?
          [filter, affects.fetch("controller", "any"), affects["other"] == true]
        end

        def self.live?(data)
          case data
          when Hash then data.any? { |k, v| LIVE.include?(k.to_s) || live?(v) }
          when Array then data.any? { live?(it) }
          else false
          end
        end

        # {"power": amount, "toughness": amount}; an amount is counted during the layer pass, so it can't read
        # power or toughness itself (CR 613.8).
        def self.parse_pump(params, errors, path)
          raw = Mechanics.fetch_param(params, :pump) || {}
          return {} if raw.empty?

          Mechanics.check_keys(raw, %w[power toughness], errors, "#{path}.pump")
          %w[power toughness].to_h do |key|
            amount = Effects::Pump.signed(raw, key, errors, "#{path}.pump", targets_count: 0)
            errors << "#{path}.pump.#{key}: can't read power or toughness (CR 613.8)" unless Amount.layer_safe?(amount)
            [key, amount]
          end
        end

        def self.parse_keywords(params, errors, path)
          keywords = Array(Mechanics.fetch_param(params, :keywords)).map { it.to_s.downcase.tr(" -", "__") }
          keywords.each { errors << "#{path}.keywords: unknown keyword #{it.inspect}" unless Enjine.registry.fetch(:keyword, it) }
          keywords.map(&:to_sym)
        end

        def self.parse_subtypes(params, key, errors, path)
          raw = Mechanics.fetch_param(params, key)
          return nil if raw.nil?

          ok = raw.is_a?(Array) && !raw.empty? && raw.all? { CardDefinition::SUBTYPE_FORMAT.match?(it.to_s) }
          errors << "#{path}.#{key}: must be a non-empty list of lowercase subtypes" unless ok
          ok ? raw.map(&:to_sym).freeze : nil
        end

        # Granted abilities are part of this card's data, referenced as "<this ability's ref>:<j>" (like a
        # station symbol's, see CardDefinition#nested_instances).
        def self.parse_granted(params, errors, path)
          Mechanics.list_param(params, :abilities, errors, path).each_with_index.filter_map do |entry, j|
            ability = Mechanics.build_entry(:ability, entry, errors, "#{path}.abilities[#{j}]")
            next ability if ability.nil? || GRANTABLE.include?(ability.kind)

            errors << "#{path}.abilities[#{j}]: only #{GRANTABLE.join(", ")} abilities can be granted yet"
            nil
          end.freeze
        end

        def initialize(filter:, controller:, other:, pump:, keywords:, creature_types:, condition:, granted:, card_types: [],
                       subtypes: [], loses_abilities: false, colors: nil, base_power_toughness: nil, chosen_subtype: false,
                       set_types: nil, name: nil)
          super()
          @set_types = set_types
          @name = name
          @chosen_subtype = chosen_subtype
          @card_types = card_types.freeze
          @subtypes = subtypes.freeze
          @loses_abilities = loses_abilities
          @colors = colors
          @base_power_toughness = base_power_toughness
          @filter = filter
          @controller = controller
          @other = other
          @pump = pump.freeze
          @keywords = keywords.freeze
          @creature_types = creature_types
          @condition = condition
          @granted = granted
          freeze
        end

        def kind = :static
        def attached? = @filter == :attached
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        def nested_abilities = @granted
        def pump? = !@pump.empty?
        def loses_abilities? = @loses_abilities
        def adds_subtypes? = @chosen_subtype || !@subtypes.empty?
        # Whether it changes layers 3-4: the name, card types or subtypes.
        def type_changes? = !@creature_types.nil? || !@card_types.empty? || adds_subtypes? || !@set_types.nil? || !@name.nil?

        # The subtypes it adds: its own, or the type its source chose as it entered (CR 607.2d, 614.12).
        def added_subtypes(source) = @chosen_subtype ? [source.memory["chosen_type"]].compact.map(&:to_sym) : @subtypes
        # Whether it changes layer 6: abilities removed or added.
        def ability_changes? = @loses_abilities || !@keywords.empty? || !@granted.empty?
        def computed? = @pump.values.any? { !it.is_a?(Amount::Fixed) }

        # The fixed bonus, for display and for data readers (computed bonuses are Amounts).
        def power = fixed(@pump["power"])
        def toughness = fixed(@pump["toughness"])

        # The bonus for this layer pass: [power, toughness] (CR 608.2h doesn't apply: statics aren't locked in).
        def bonus(engine, source)
          ctx = context(source)
          [@pump.fetch("power", ZERO).value(engine, ctx), @pump.fetch("toughness", ZERO).value(engine, ctx)]
        end

        ZERO = Amount::Fixed.new(0)

        # Whether the ability applies now: its "as long as" / "during your turn" condition (CR 604.2).
        def active?(engine, source) = @condition.nil? || @condition.true?(engine, context(source))

        # Matches on characteristics and counters (Filters::Facts), so the layer pass never depends on its
        # own result.
        def affects?(object, source, facts)
          return source.attached_to == object.id if attached?
          return object.id == source.id if @filter == :self
          return false if @other && object.id == source.id
          return false unless @controller == "any" || (@controller == "you") == (object.controller == source.controller)

          @filter.matches_facts?(@filter.uses_chosen? ? facts.with(chosen: source.memory) : facts) # CR 607.2d
        end

        def to_s
          bits = []
          bits << "loses all abilities" if loses_abilities?
          bits << "named #{name}" if name
          bits << "card types exactly #{set_types.join(" ")}" if set_types
          bits << "colors #{colors.empty? ? "colorless" : colors.join}" if colors
          bits << "base #{base_power_toughness.values.join("/")}" if base_power_toughness
          bits << "#{Effects::Pump.signed_text(@pump["power"] || ZERO)}/#{Effects::Pump.signed_text(@pump["toughness"] || ZERO)}" if pump?
          bits << keywords.join(", ") unless keywords.empty?
          bits << "creature type #{creature_types.join(" ")}" if creature_types
          bits << "types #{card_types.join(" ")}" unless card_types.empty?
          bits << "subtypes #{@chosen_subtype ? "the chosen type" : subtypes.join(" ")}" if adds_subtypes?
          bits << "\"#{granted.join("; ")}\"" unless granted.empty?
          "#{who} get#{"s" if %i[attached self].include?(@filter)} #{bits.join(" and ")}#{" as long as #{condition}" if condition}"
        end

        private

        def fixed(amount) = amount.is_a?(Amount::Fixed) ? amount.n : 0

        def context(source) = EffectContext.new(source.controller, source.id, source.id, [], [])

        def who
          return "the attached permanent" if attached?
          return "it" if @filter == :self

          "#{"other " if other}#{filter.respond_to?(:primitive_name) ? filter.primitive_name : filter}s " \
          "#{{ "you" => "you control ", "opponent" => "opponents control " }[controller]}".strip
        end
      end
    end

    module Effects
      # "gains flying until end of turn" (CR 611.2, 613.1f): grant keywords to a locked set.
      class Grant < Effect
        primitive :effect, :grant,
                  description: "Each referenced permanent gains the `keywords` until end of turn.",
                  rules: %w[611.2a 611.2c 613.1f 514.2],
                  params: { "keywords" => "list of keywords", "to" => "selector" },
                  example: { "grant" => { "keywords" => ["flying"], "to" => { "target" => 0 } } }

        attr_reader :keywords

        def self.keys = %w[keywords to if]

        def setup(params, errors, path)
          @keywords = Array(Mechanics.fetch_param(params, :keywords)).map { it.to_s.downcase.tr(" -", "__") }
          errors << "#{path}.keywords: needs at least one keyword" if @keywords.empty?
          @keywords.each { errors << "#{path}.keywords: unknown keyword #{it.inspect}" unless Enjine.registry.fetch(:keyword, it) }
        end

        def apply(engine, ctx)
          engine.add_continuous_effect!("grant", ctx, objects(engine, ctx), "keywords" => keywords)
        end

        def to_s = "gains #{keywords.join(", ")} until end of turn → #{to}"
      end

      # Setting a creature's creature types until end of turn; its other creature types are lost (CR 205.1a, 613.1d).
      class SetCreatureTypes < Effect
        primitive :effect, :set_creature_types,
                  description: "Until end of turn, each referenced creature's creature types are exactly `types` (its " \
                               "other subtypes, such as artifact types, stay). The affected set is locked in.",
                  rules: %w[205.1a 613.1d 611.2c 514.2],
                  params: { "types" => "list of creature types", "to" => "selector" },
                  example: { "set_creature_types" => { "types" => ["doctor"], "to" => { "target" => 0 } } }

        attr_reader :types

        def self.keys = %w[types to if]

        def setup(params, errors, path)
          raw = Mechanics.fetch_param(params, :types)
          ok = raw.is_a?(Array) && !raw.empty? && raw.all? { CardDefinition::SUBTYPE_FORMAT.match?(it.to_s) }
          errors << "#{path}.types: must be a non-empty list of lowercase creature types" unless ok
          @types = ok ? raw.map(&:to_s).freeze : []
        end

        def apply(engine, ctx)
          affected = objects(engine, ctx).select { engine.chars(it).creature? }
          engine.add_continuous_effect!("creature_types", ctx, affected, "types" => types)
        end

        def to_s = "becomes #{types.join(" ")} until end of turn → #{to}"
      end

      # Setting base power and toughness to fixed numbers (CR 613.4b): a setting effect, until end of turn or for
      # as long as the permanent stays on the battlefield (`duration: "indefinite"`, CR 611.2a-b).
      class SetBasePowerToughness < Effect
        DURATIONS = %w[end_of_turn indefinite].freeze

        primitive :effect, :set_base_power_toughness,
                  description: "Each referenced creature's base power and toughness become `power`/`toughness` " \
                               "(layer 7b; counters and pumps still apply), until end of turn or, with `duration: " \
                               "\"indefinite\"`, for as long as it stays on the battlefield.",
                  rules: %w[613.4b 611.2a 611.2b 611.2c],
                  params: { "power" => "integer", "toughness" => "integer", "duration" => DURATIONS.join(" | "),
                            "to" => "selector" },
                  example: { "set_base_power_toughness" => { "power" => 7, "toughness" => 9, "duration" => "indefinite",
                                                             "to" => "self" } }

        attr_reader :power, :toughness, :duration

        def self.keys = %w[power toughness duration to if]

        def setup(params, errors, path)
          @power = Mechanics.integer_param(params, :power, errors, path, min: 0)
          @toughness = Mechanics.integer_param(params, :toughness, errors, path, min: 0)
          @duration = Mechanics.fetch_param(params, :duration) || "end_of_turn"
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
        end

        def apply(engine, ctx)
          affected = objects(engine, ctx).select { engine.chars(it).creature? }
          engine.add_continuous_effect!("base_power_toughness", ctx, affected,
                                        { "power" => power, "toughness" => toughness,
                                          "duration" => @duration == "indefinite" ? "permanent" : "end_of_turn" })
        end

        def to_s = "base power and toughness become #{power}/#{toughness}#{" until end of turn" if duration == "end_of_turn"} → #{to}"
      end
    end
  end
end
