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
    #   {"any_of": [spec, spec, ...]}                   at least one spec must match
    class CardSpec
      KEYS = %w[types subtypes supertypes name any_of].freeze
      SUBTYPE = /\A[a-z][a-z0-9_]*\z/

      attr_reader :types, :subtypes, :supertypes, :name, :any_of

      def self.build(data, errors, path)
        return ANY if data.nil? || data == "card"
        return (errors << "#{path}: must be \"card\" or an object (#{KEYS.join(", ")})") && ANY unless data.is_a?(Hash)

        data = data.transform_keys(&:to_s)
        Mechanics.check_keys(data, KEYS, errors, path)
        errors << "#{path}: needs at least one of #{KEYS.join(", ")}" if data.empty?
        new(types: names(data, "types", :type, errors, path), supertypes: names(data, "supertypes", :supertype, errors, path),
            subtypes: subtype_list(data, errors, path), name: name_param(data, errors, path),
            any_of: alternatives(data, errors, path))
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

      def initialize(types: [], subtypes: [], supertypes: [], name: nil, any_of: [])
        @types = types.freeze
        @subtypes = subtypes.freeze
        @supertypes = supertypes.freeze
        @name = name
        @any_of = any_of.freeze
        freeze
      end

      # True when the spec states no quality: "a card" (CR 701.23d).
      def any? = types.empty? && subtypes.empty? && supertypes.empty? && name.nil? && any_of.empty?

      # Whether a card object matches, by its current characteristics (CR 109.3).
      def match?(engine, object)
        return false unless object.kind == "card"

        chars = engine.chars(object)
        types.all? { chars.type?(it) } && subtypes.all? { chars.subtypes.include?(it) } &&
          supertypes.all? { chars.supertypes.include?(it) } && (name.nil? || chars.name == name) &&
          (any_of.empty? || any_of.any? { it.match?(engine, object) })
      end

      def to_s
        return "#{any_of.map { it.to_s.delete_suffix(" card") }.join(" or ")} card" unless any_of.empty?
        return "card named #{name}" if name

        words = supertypes + subtypes.map { it.to_s.capitalize } + types
        (words.map { it.to_s.tr("_", " ") } + ["card"]).join(" ")
      end

      ANY = new
    end
  end
end
