# frozen_string_literal: true

module Enjine
  # Immutable, validated blueprint of a card, built from a data block.
  #
  #   CardDefinition.from_h({"name" => "Forest", "types" => ["land"], ...})
  #
  # Every type, supertype, subtype with rules, ability and cost is looked up in
  # Enjine.registry. Anything unknown is reported (with its path) in a single
  # InvalidCardDefinition error.
  class CardDefinition
    KEYS = %w[name mana_cost types supertypes subtypes keywords power toughness loyalty abilities rules_text].freeze
    SUBTYPE_FORMAT = /\A[a-z][a-z0-9_]*\z/

    attr_reader :id, :name, :mana_cost, :types, :supertypes, :subtypes, :keywords, :power, :toughness, :loyalty,
                :abilities, :rules_text, :type_modules, :source

    # Canonical id derived from a card name: "Jace, the Mind Sculptor" -> "jace_the_mind_sculptor".
    def self.slug(name)
      name.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.delete("'’").gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    end

    # A token definition (CR 111.1). Its id is derived from its data so two different tokens
    # with the same name ("Soldier" 1/1 and "Soldier" 2/2) never collide in a catalog.
    def self.token(data)
      card = data.transform_keys(&:to_s)
      digest = Digest::SHA256.hexdigest(JSON.generate(card))[0, 8]
      errors = []
      new(card, errors, token_id: "#{slug(card["name"])}_token_#{digest}").tap do
        raise InvalidCardDefinition.new(errors, name: card["name"]) unless errors.empty?
      end
    end

    def self.from_h(hash)
      return hash if hash.is_a?(CardDefinition)

      errors = []
      raise InvalidCardDefinition.new(["card definition must be an object, got #{hash.class}"]) unless hash.is_a?(Hash)

      card = hash.transform_keys(&:to_s)
      new(card, errors).tap do
        raise InvalidCardDefinition.new(errors, name: card["name"]) unless errors.empty?
      end
    end

    def initialize(card, errors, token_id: nil)
      (card.keys - KEYS).each { |k| errors << "#{k}: unknown field (allowed: #{KEYS.join(", ")})" }
      @name = read_name(card, errors)
      @id = token_id || self.class.slug(@name)
      @token = !token_id.nil?
      @types, @type_modules = read_names(card, "types", :type, errors, required: true)
      @supertypes, = read_names(card, "supertypes", :supertype, errors)
      @subtypes = read_subtypes(card, errors)
      @mana_cost = card.key?("mana_cost") ? Mana.parse_cost(card["mana_cost"], errors) : nil
      @keywords, = read_names(card, "keywords", :keyword, errors)
      @power = read_stat(card, "power", errors)
      @toughness = read_stat(card, "toughness", errors)
      @loyalty = read_stat(card, "loyalty", errors)
      @rules_text = card["rules_text"]
      errors << "rules_text: must be a string" unless @rules_text.nil? || @rules_text.is_a?(String)
      @abilities = read_abilities(card, errors)
      @type_modules.each { |mod| mod.validate(card, errors) }
      precompute_predicates
      validate_type_specific(errors)
      @source = normalize(card)
      @printed_characteristics = Characteristics.printed(self) if errors.empty?
      freeze
    end

    def type?(type) = @types.include?(type.to_sym)
    def supertype?(type) = @supertypes.include?(type.to_sym)
    def keyword?(keyword) = @keywords.include?(keyword.to_sym)

    # Predicates below are computed once at construction: they sit on the engine's hot path.
    attr_reader :spell_ability, :ability_instances

    # Characteristics as printed: the starting point of the layer system (CR 613).
    attr_reader :printed_characteristics

    # A printed or intrinsic ability, or a delayed triggered ability one of its effects creates
    # ("delayed:<path>", see Effects::DelayedTrigger).
    def ability(ref) = @ability_instances.find { it.ref == ref }&.ability || @delayed_abilities[ref]

    def permanent? = @permanent
    def token? = @token

    # Token definitions this card's effects can create; catalogs register them with the card.
    def token_definitions
      @all_effects.filter_map { it.definition if it.is_a?(Mechanics::Effects::CreateToken) }.uniq(&:id)
    end

    # Every effect of every ability, including effects nested in other effects ("may", delayed triggers).
    attr_reader :all_effects

    def triggered? = @triggered
    def land? = @land
    def creature? = @creature
    def planeswalker? = @planeswalker
    def deck_limit_exempt? = @deck_limit_exempt

    # Whether this card can be cast at instant speed (CR 304.1, 702.8a).
    def instant_speed? = @instant_speed

    # Lands are played, not cast; a card without a mana cost can't be cast normally (CR 202.1b).
    def castable? = @castable

    def mana_abilities = @ability_instances.map(&:ability).select(&:mana_ability?)

    def type_line
      left = (@supertypes + @types).map { |t| t.to_s.capitalize }.join(" ")
      right = @subtypes.map { |t| t.to_s.split("_").map(&:capitalize).join(" ") }.join(" ")
      right.empty? ? left : "#{left} — #{right}"
    end

    # Canonical data form; CardDefinition.from_h(defn.to_h) == defn.
    def to_h = @source

    def ==(other) = other.is_a?(CardDefinition) && other.to_h == to_h
    alias eql? ==

    def hash = @source.hash

    private

    def precompute_predicates
      @land = @types.include?(:land)
      @creature = @types.include?(:creature)
      @planeswalker = @types.include?(:planeswalker)
      @permanent = @type_modules.any?(&:permanent?)
      @instant_speed = @type_modules.any?(&:instant_speed?) || @keywords.include?(:flash)
      @castable = !@land && !@mana_cost.nil?
      @deck_limit_exempt = @supertypes.any? { Enjine.registry.fetch(:supertype, it).deck_limit_exempt? }
      @spell_ability = @abilities.find { it.kind == :spell }
      @triggered = @abilities.any? { it.kind == :triggered }
      @all_effects = nested(@abilities.flat_map do |ability|
        ability.respond_to?(:modes) && ability.modal? ? ability.modes.flat_map(&:effects) : ability.try_effects
      end).freeze
      @delayed_abilities = @all_effects.select { it.respond_to?(:delayed_ability) }.to_h { [it.ref, it.delayed_ability] }.freeze
    end

    def nested(effects) = effects.flat_map { [it, *nested(it.nested_effects)] }

    def validate_type_specific(errors)
      errors << "power/toughness: only creatures have power and toughness" if !creature? && (@power || @toughness)
      errors << "loyalty: only planeswalkers have loyalty" if !planeswalker? && @loyalty
      @abilities.each_with_index do |ability, i|
        allowed = ability.allowed_types
        next if allowed.nil? || allowed.any? { type?(it) }

        errors << "abilities[#{i}]: #{ability.class.primitive_name} abilities need a #{allowed.join("/")} card"
      end
    end

    def read_name(card, errors)
      name = card["name"]
      return name if name.is_a?(String) && !self.class.slug(name).empty?

      errors << "name: required, must be a non-empty string"
      "?"
    end

    def read_names(card, key, category, errors, required: false)
      list = card.fetch(key, [])
      if !list.is_a?(Array) || (required && list.empty?)
        errors << "#{key}: must be a #{"non-empty " if required}list"
        return [[].freeze, [].freeze]
      end

      modules = list.each_with_index.filter_map do |raw, i|
        Enjine.registry.fetch(category, raw.to_s.downcase.tr(" -", "__")).tap do |mod|
          unless mod
            errors << "#{key}[#{i}]: unknown #{category} #{raw.inspect} " \
                      "(supported: #{Enjine.registry.names(category).join(", ")})"
          end
        end
      end
      [modules.map { |m| m.primitive_name.to_sym }.uniq.freeze, modules.uniq.freeze]
    end

    def read_subtypes(card, errors)
      list = card.fetch("subtypes", [])
      unless list.is_a?(Array)
        errors << "subtypes: must be a list"
        return [].freeze
      end

      list.each_with_index.filter_map do |raw, i|
        sub = raw.to_s.downcase.tr(" -", "__")
        unless SUBTYPE_FORMAT.match?(sub)
          errors << "subtypes[#{i}]: invalid subtype #{raw.inspect}"
          next
        end

        rule = Enjine.registry.fetch(:subtype, sub)
        if rule && !rule.applies_to.intersect?(@types)
          errors << "subtypes[#{i}]: #{sub} is only valid for #{rule.applies_to.join("/")} cards (CR 205.3d)"
        end
        sub.to_sym
      end.uniq.freeze
    end

    def read_stat(card, key, errors)
      return nil unless card.key?(key)

      value = card[key]
      errors << "#{key}: must be an integer" unless value.is_a?(Integer)
      value
    end

    def read_abilities(card, errors)
      list = card.fetch("abilities", [])
      unless list.is_a?(Array)
        errors << "abilities: must be a list"
        list = []
      end

      explicit = list.each_with_index.filter_map do |entry, i|
        ability = Mechanics.build_entry(:ability, entry, errors, "abilities[#{i}]")
        AbilityInstance.new(ref: "printed:#{i}", ability: ability) if ability
      end
      intrinsic = @subtypes.flat_map do |sub|
        rule = Enjine.registry.fetch(:subtype, sub)
        abilities = rule.respond_to?(:intrinsic_abilities) ? rule.intrinsic_abilities : []
        abilities.each_with_index.map { |a, i| AbilityInstance.new(ref: "intrinsic:#{sub}#{":#{i}" if i.positive?}", ability: a) }
      end
      @ability_instances = (explicit + intrinsic).freeze
      @ability_instances.map(&:ability).freeze
    end

    def normalize(card)
      out = { "name" => @name }
      out["mana_cost"] = @mana_cost.to_s if @mana_cost
      out["types"] = @types.map(&:to_s)
      out["supertypes"] = @supertypes.map(&:to_s) unless @supertypes.empty?
      out["subtypes"] = @subtypes.map(&:to_s) unless @subtypes.empty?
      out["keywords"] = @keywords.map(&:to_s) unless @keywords.empty?
      out["power"] = @power unless @power.nil?
      out["toughness"] = @toughness unless @toughness.nil?
      out["loyalty"] = @loyalty unless @loyalty.nil?
      out["abilities"] = deep_stringify(card["abilities"]) if card["abilities"].is_a?(Array) && !card["abilities"].empty?
      out["rules_text"] = @rules_text if @rules_text
      deep_freeze(out)
    end

    def deep_stringify(value)
      case value
      when Hash then value.to_h { |k, v| [k.to_s, deep_stringify(v)] }
      when Array then value.map { deep_stringify(it) }
      when Symbol then value.to_s
      else value
      end
    end

    def deep_freeze(value)
      case value
      when Hash then value.each_value { deep_freeze(it) }
      when Array then value.each { deep_freeze(it) }
      end
      value.freeze
    end
  end
end
