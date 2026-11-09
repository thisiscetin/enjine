# frozen_string_literal: true

module Enjine
  module Mechanics
    # A description of a card by its characteristics, for effects that look at cards in any
    # zone ("a basic land card", "a Swamp card", "an Aura or Equipment card"; CR 701.23a,
    # 702.29e). Data forms:
    #
    #   "card"                                          any card
    #   {"types": ["land"], "supertypes": ["basic"]}    every listed quality must match
    #   {"subtypes": ["swamp"]} / {"name": "Card Name"}
    #   {"not_types": ["creature", "land"]}             "noncreature, nonland card"
    #   {"permanent": true}                             "permanent card": any permanent card type (CR 110.4a)
    #   {"mana_value": {"at_most": 3}}                  also at_least / equal; each bound an amount (CR 202.3)
    #   {"colors": ["B"]}                               a black card: it has any of the listed colors (CR 105.2)
    #   {"color_count": {"equal": 1}}                   monocolored (1), multicolored (at least 2), colorless (0)
    #   {"any_of": [spec, spec, ...]}                   at least one spec must match
    class CardSpec
      KEYS = %w[types not_types subtypes supertypes name any_of permanent mana_value colors color_count].freeze
      SUBTYPE = /\A[a-z][a-z0-9_]*\z/
      # CR 110.4a: the permanent card types (battles have no primitive yet, so none matches that way).
      PERMANENT_TYPES = %i[artifact battle creature enchantment land planeswalker].freeze
      BOUNDS = %w[at_least at_most equal].freeze

      attr_reader :types, :not_types, :subtypes, :supertypes, :name, :any_of, :permanent, :mana_value, :colors, :color_count

      def self.build(data, errors, path)
        return ANY if data.nil? || data == "card"
        return (errors << "#{path}: must be \"card\" or an object (#{KEYS.join(", ")})") && ANY unless data.is_a?(Hash)

        data = data.transform_keys(&:to_s)
        Mechanics.check_keys(data, KEYS, errors, path)
        errors << "#{path}: needs at least one of #{KEYS.join(", ")}" if data.empty?
        new(types: names(data, "types", :type, errors, path), supertypes: names(data, "supertypes", :supertype, errors, path),
            subtypes: subtype_list(data, errors, path), name: name_param(data, errors, path),
            any_of: alternatives(data, errors, path), not_types: names(data, "not_types", :type, errors, path),
            permanent: permanent_param(data, errors, path), mana_value: bounds_param(data, "mana_value", errors, path),
            colors: colors_param(data, errors, path), color_count: bounds_param(data, "color_count", errors, path))
      end

      def self.colors_param(data, errors, path)
        list(data, "colors", errors, path).filter_map do |raw|
          color = raw.to_s.upcase.to_sym
          next color if Mana::COLORS.include?(color)

          errors << "#{path}.colors: unknown color #{raw.inspect} (W, U, B, R, G)"
          nil
        end
      end

      def self.names(data, key, category, errors, path)
        list(data, key, errors, path).filter_map do |raw|
          name = raw.to_s.downcase.tr(" -", "__")
          next name.to_sym if Enjine.registry.fetch(category, name)

          errors << "#{path}.#{key}: unknown #{category} #{raw.inspect}"
          nil
        end
      end

      def self.subtype_list(data, errors, path)
        list(data, "subtypes", errors, path).filter_map do |raw|
          sub = raw.to_s.downcase.tr(" -", "__")
          next sub.to_sym if SUBTYPE.match?(sub)

          errors << "#{path}.subtypes: invalid subtype #{raw.inspect}"
          nil
        end
      end

      def self.list(data, key, errors, path)
        value = data.fetch(key, [])
        return value if value.is_a?(Array)

        errors << "#{path}.#{key}: must be a list"
        []
      end

      def self.name_param(data, errors, path)
        value = data["name"]
        errors << "#{path}.name: must be a card name" unless value.nil? || (value.is_a?(String) && !value.empty?)
        value.is_a?(String) ? value : nil
      end

      def self.alternatives(data, errors, path)
        return [] unless data.key?("any_of")

        specs = list(data, "any_of", errors, path)
        errors << "#{path}.any_of: must list at least two specs" if specs.size < 2
        specs.each_with_index.map { |spec, i| build(spec, errors, "#{path}.any_of[#{i}]") }
      end

      def self.permanent_param(data, errors, path)
        value = data["permanent"]
        errors << "#{path}.permanent: must be true" unless value.nil? || value == true
        value == true
      end

      # {"at_least"|"at_most"|"equal": amount}: each bound is an Amount, computed as the card is looked at.
      def self.bounds_param(data, key, errors, path)
        raw = data[key]
        return {} if raw.nil?

        unless raw.is_a?(Hash) && !raw.empty? && (raw.keys.map(&:to_s) - BOUNDS).empty?
          errors << "#{path}.#{key}: must be {\"at_least\"|\"at_most\"|\"equal\": amount}"
          return {}
        end
        raw.to_h { |bound, n| [bound.to_s, Amount.build(n, errors, "#{path}.#{key}.#{bound}", targets_count: 0)] }
      end

      def initialize(types: [], subtypes: [], supertypes: [], name: nil, any_of: [], not_types: [], permanent: false,
                     mana_value: {}, colors: [], color_count: {})
        @colors = colors.freeze
        @color_count = color_count.freeze
        @types = types.freeze
        @not_types = not_types.freeze
        @subtypes = subtypes.freeze
        @supertypes = supertypes.freeze
        @name = name
        @any_of = any_of.freeze
        @permanent = permanent
        @mana_value = mana_value.freeze
        freeze
      end

      # True when the spec states no quality: "a card" (CR 701.23d).
      def any?
        types.empty? && not_types.empty? && subtypes.empty? && supertypes.empty? && name.nil? && any_of.empty? &&
          !permanent && mana_value.empty? && colors.empty? && color_count.empty?
      end

      # Whether a card object matches, by its current characteristics (CR 109.3). `ctx` (an EffectContext)
      # computes mana value bounds given as amounts; without one, only fixed bounds can be met.
      def match?(engine, object, ctx = nil)
        return false unless object.kind == "card"

        chars = engine.chars(object)
        types.all? { chars.type?(it) } && not_types.none? { chars.type?(it) } &&
          subtypes.all? { chars.subtypes.include?(it) } && supertypes.all? { chars.supertypes.include?(it) } &&
          (name.nil? || chars.name == name) && (!permanent || chars.types.intersect?(PERMANENT_TYPES)) &&
          (colors.empty? || colors.intersect?(chars.colors)) && bounded?(mana_value, chars.mana_cost&.mana_value.to_i, engine, ctx) &&
          bounded?(color_count, chars.colors.size, engine, ctx) && (any_of.empty? || any_of.any? { it.match?(engine, object, ctx) })
      end

      def to_s
        return "#{any_of.map { it.to_s.delete_suffix(" card") }.join(" or ")} card" unless any_of.empty?
        return "card named #{name}" if name

        words = not_types.map { "non#{it}" } + colors + supertypes + subtypes.map { it.to_s.capitalize } + types
        words << "permanent" if permanent
        text = (words.map { it.to_s.tr("_", " ") } + ["card"]).join(" ")
        bounds = { "mana value" => mana_value, "number of colors" => color_count }.reject { |_, b| b.empty? }
        return text if bounds.empty?

        "#{text} with #{bounds.map { |what, b| "#{what} #{b.map { |bound, n| "#{bound.tr("_", " ")} #{n}" }.join(" and ")}" }.join(", ")}"
      end

      private

      # CR 202.3: a card's mana value (0 without a mana cost, CR 202.3a), or its number of colors (CR 105.2), within
      # the bounds.
      def bounded?(bounds, value, engine, ctx)
        bounds.all? do |bound, amount|
          n = ctx ? amount.value(engine, ctx) : fixed(amount)
          next false if n.nil?

          { "at_least" => value >= n, "at_most" => value <= n, "equal" => value == n }.fetch(bound)
        end
      end

      def fixed(amount) = amount.is_a?(Amount::Fixed) ? amount.n : nil
    end

    # "card": any card.
    CardSpec::ANY = CardSpec.new
  end
end
