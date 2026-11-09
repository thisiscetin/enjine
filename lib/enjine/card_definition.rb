# frozen_string_literal: true

require_relative "card_faces"

module Enjine
  # Immutable, validated blueprint of a card, built from a data block.
  #
  #   CardDefinition.from_h({"name" => "Forest", "types" => ["land"], ...})
  #
  # Every type, supertype, subtype with rules, ability and cost is looked up in
  # Enjine.registry. Anything unknown is reported (with its path) in a single
  # InvalidCardDefinition error.
  class CardDefinition
    KEYS = %w[name mana_cost colors types supertypes subtypes keywords power toughness loyalty abilities rules_text deck_limit].freeze
    # Optional catalogue data beside the rules data, never read by the rules: rarity, and the set code and
    # collector number printed on the card ({"set" => "trk", "number" => "12"}).
    PRINT_KEYS = %w[rarity printing].freeze
    SUBTYPE_FORMAT = /\A[a-z][a-z0-9_]*\z/
    include Faces

    attr_reader :id, :name, :mana_cost, :types, :supertypes, :subtypes, :keywords, :power, :toughness, :loyalty,
                :abilities, :rules_text, :type_modules, :source, :colors, :power_amount, :toughness_amount, :rarity, :printing

    # Canonical id derived from a card name: "Jace, the Mind Sculptor" -> "jace_the_mind_sculptor".
    # A multi-face card is named by its front face: "Alfa // Bravo" -> "alfa" (see CardDefinition::Faces).
    def self.slug(name)
      name.to_s.split(" // ").first.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.delete("'’")
          .gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
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

    # `face`: [front definition, index] when building a face other than the front (CardDefinition::Faces).
    def initialize(card, errors, token_id: nil, face: nil)
      card = read_print(card, errors) if face.nil?
      if face.nil? && card.key?("faces")
        read_faces(card, errors, token_id)
      else
        read_card(card, errors, token_id, face)
        @source = normalize(card)
      end
      @rules_data = @source
      @source = deep_freeze(@source.merge("rarity" => @rarity, "printing" => @printing).compact) if @rarity || @printing
      @printed_characteristics = Characteristics.printed(self) if errors.empty?
      freeze
    end

    def read_card(card, errors, token_id, face = nil)
      (card.keys - KEYS).each { |k| errors << "#{k}: unknown field (allowed: #{(KEYS + PRINT_KEYS).join(", ")})" }
      @name = read_name(card, errors)
      @id = face ? "#{face[0].id}#{FACE_SEPARATOR}#{face[1]}" : token_id || self.class.slug(@name)
      @front, @face_index = face
      @token = !token_id.nil?
      @types, @type_modules = read_names(card, "types", :type, errors, required: true)
      @supertypes, = read_names(card, "supertypes", :supertype, errors)
      @subtypes = read_subtypes(card, errors)
      @mana_cost = card.key?("mana_cost") ? Mana.parse_cost(card["mana_cost"], errors) : nil
      @keywords, keyword_modules = read_names(card, "keywords", :keyword, errors)
      @colors = read_colors(card, errors)
      @deck_limit = read_deck_limit(card, errors)
      @power, @power_amount = read_pt(card, "power", errors)
      @toughness, @toughness_amount = read_pt(card, "toughness", errors)
      @loyalty = read_stat(card, "loyalty", errors)
      @rules_text = card["rules_text"]
      errors << "rules_text: must be a string" unless @rules_text.nil? || @rules_text.is_a?(String)
      @abilities = read_abilities(card, errors)
      @type_modules.each { |mod| mod.validate(card, errors) }
      keyword_modules.each { |mod| mod.validate(card, errors) if mod.respond_to?(:validate) }
      precompute_predicates
      validate_type_specific(errors)
    end
    private :read_card

    def type?(type) = @types.include?(type.to_sym)
    def supertype?(type) = @supertypes.include?(type.to_sym)
    def keyword?(keyword) = @keywords.include?(keyword.to_sym)

    # Predicates below are computed once at construction: they sit on the engine's hot path.
    attr_reader :spell_ability, :ability_instances

    # Characteristics as printed: the starting point of the layer system (CR 613).
    attr_reader :printed_characteristics

    # Any ability of the card by reference: printed or intrinsic, one a station symbol grants only
    # while it applies (CR 722.2a), or a delayed triggered ability one of its effects creates
    # ("delayed:<path>", see Effects::DelayedTrigger).
    def ability(ref)
      (@ability_instances.find { it.ref == ref } || @nested_instances.find { it.ref == ref })&.ability ||
        @delayed_abilities[ref] || @effect_granted.values.flatten.find { it.ref == ref }&.ability ||
        (ref.to_s.start_with?("keyword:") && CardDefinition.keyword_instances(ref.delete_prefix("keyword:")).first&.ability) || nil
    end

    # The abilities a keyword stands for ("Prowess" is a triggered ability, CR 702.108a), as instances
    # referenced "keyword:<name>"; the same for a printed keyword and one an effect grants (CR 613.1f).
    def self.keyword_instances(keyword)
      rule = Enjine.registry.fetch(:keyword, keyword.to_s)
      abilities = rule.respond_to?(:intrinsic_abilities) ? rule.intrinsic_abilities : []
      abilities.map { AbilityInstance.new(ref: "keyword:#{keyword}", ability: it) }
    end

    # Abilities an effect of this card grants for a while ("<effect ref>:<j>", see Effects::Become).
    def effect_granted(ref) = @effect_granted.fetch(ref, EMPTY)

    # Abilities the ability at `ref` grants while it applies (a station symbol's, CR 722.2).
    def nested_instances(ref) = @nested_by_ref.fetch(ref, EMPTY)
    EMPTY = [].freeze

    def permanent? = @permanent

    # CR 604.3: power and/or toughness defined by a characteristic-defining ability ("*" printed).
    def defined_pt? = !(@power_amount.nil? && @toughness_amount.nil?)
    def token? = @token

    # Token definitions this card's effects can create; catalogs register them with the card.
    def token_definitions
      (@all_effects.filter_map { it.definition if it.is_a?(Mechanics::Effects::CreateToken) } +
        @all_effects.flat_map { it.respond_to?(:created_tokens) ? it.created_tokens : [] } + # recruit, amass, ...
        @abilities.filter_map { it.token_definition if it.respond_to?(:token_definition) } +
        other_faces.flat_map(&:token_definitions)).compact.uniq(&:id)
    end

    # Every effect of every ability, including effects nested in other effects ("may", delayed triggers).
    attr_reader :all_effects

    def triggered? = @triggered
    def land? = @land
    def creature? = @creature
    def planeswalker? = @planeswalker
    def deck_limit_exempt? = @deck_limit_exempt

    # Most copies a constructed deck may hold (CR 100.2a): nil for any number (basic lands, or a card that
    # says "a deck can have any number of cards named ~").
    def deck_limit = @deck_limit_exempt ? nil : (@deck_limit || Deck::MAX_COPIES)

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

    # The canonical data form without the PRINT_KEYS: what the rules see.
    attr_reader :rules_data

    # The same card: equal rules data, whatever its rarity or printing (a reprint is the same card).
    def ==(other) = other.is_a?(CardDefinition) && other.rules_data == rules_data
    alias eql? ==

    def hash = @rules_data.hash

    private

    def precompute_predicates
      @land = @types.include?(:land)
      @creature = @types.include?(:creature)
      @planeswalker = @types.include?(:planeswalker)
      @permanent = @type_modules.any?(&:permanent?)
      @instant_speed = @type_modules.any?(&:instant_speed?) || @keywords.include?(:flash)
      @castable = !@land && !@mana_cost.nil?
      @deck_limit_exempt = @deck_limit == "any" || @supertypes.any? { Enjine.registry.fetch(:supertype, it).deck_limit_exempt? }
      @spell_ability = @abilities.find { it.kind == :spell } || aura_spell_ability
      every = @abilities + @nested_instances.map(&:ability)
      @triggered = every.any? { it.kind == :triggered }
      @all_effects = nested(every.flat_map do |ability|
        ability.respond_to?(:modes) && ability.modal? ? ability.modes.flat_map(&:effects) : ability.try_effects
      end).freeze
      @delayed_abilities = @all_effects.select { it.respond_to?(:delayed_ability) }.to_h { [it.ref, it.delayed_ability] }
                                       .merge(granted_by_effects).freeze
      @effect_granted = @all_effects.select { it.respond_to?(:granted_abilities) }.to_h do |effect|
        [effect.ref, effect.granted_abilities.each_with_index.map do |a, j|
          AbilityInstance.new(ref: "#{effect.ref}:#{j}", ability: a)
        end.freeze]
      end.freeze
    end

    def nested(effects) = effects.flat_map { [it, *nested(it.nested_effects)] }

    # Abilities effects grant ("that card gains ...", Effects::GrantAbility), referenced by the effect's path.
    def granted_by_effects
      @all_effects.select { it.respond_to?(:granted_ability) && it.granted_ability }.to_h { [it.ref, it.granted_ability] }
    end

    def validate_type_specific(errors)
      if !creature? && !@subtypes.include?(:vehicle) && (@power || @toughness) # CR 301.7a: a Vehicle has them printed
        errors << "power/toughness: only creatures and Vehicles have power and toughness"
      end
      errors << "loyalty: only planeswalkers have loyalty" if !planeswalker? && @loyalty
      @abilities.each_with_index do |ability, i|
        allowed = ability.allowed_types
        next if allowed.nil? || allowed.any? { type?(it) }

        errors << "abilities[#{i}]: #{ability.class.primitive_name} abilities need a #{allowed.join("/")} card"
      end
      validate_definition_hooks(errors)
    end

    # Rules that depend on the whole card, e.g. "an Aura has an enchant ability" (CR 303.4a).
    def validate_definition_hooks(errors)
      @subtypes.each do |sub|
        rule = Enjine.registry.fetch(:subtype, sub)
        rule.validate_definition(self, errors) if rule.respond_to?(:validate_definition)
      end
      @abilities.each_with_index do |ability, i|
        ability.validate_definition(self, errors, "abilities[#{i}]") if ability.respond_to?(:validate_definition)
      end
    end

    # CR 115.1b / 303.4a: an Aura spell targets what its enchant ability allows.
    def aura_spell_ability
      enchant = @subtypes.include?(:aura) && @abilities.find { it.kind == :enchant }
      Mechanics::Abilities::AuraSpell.for(enchant) if enchant
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

    # CR 202.2: a card's colors come from its mana cost, unless it has a color indicator (CR 204) or is a
    # token whose creating effect gives its colors (CR 111.4): `"colors": ["G"]` (`[]` for colorless).
    def read_colors(card, errors)
      return (@mana_cost.is_a?(Mana::Cost) ? Mana::COLORS.select { @mana_cost.colored.key?(it) } : []).freeze unless card.key?("colors")

      list = card["colors"]
      ok = list.is_a?(Array) && list.all? { Mana::COLORS.include?(it.to_s.upcase.to_sym) }
      errors << "colors: must be a list of W, U, B, R, G" unless ok
      ok ? Mana::COLORS.select { |c| list.map { it.to_s.upcase }.include?(c.to_s) }.freeze : [].freeze
    end

    # CR 100.2a: "a deck can have any number of cards named ~" is `"deck_limit": "any"`; "up to seven" is 7.
    # Reads the PRINT_KEYS of a whole card; returns the card without them.
    def read_print(card, errors)
      @rarity = card["rarity"]
      errors << "rarity: must be a string" unless @rarity.nil? || @rarity.is_a?(String)
      printing = card["printing"]
      printing = printing.transform_keys(&:to_s) if printing.is_a?(Hash)
      if printing.is_a?(Hash) && printing.keys.sort == %w[number set] && printing.values.all? { it.is_a?(String) || it.is_a?(Integer) }
        @printing = printing.transform_values(&:to_s).freeze
      elsif printing
        errors << "printing: must be {\"set\": code, \"number\": collector number}"
      end
      card.except(*PRINT_KEYS)
    end

    def read_deck_limit(card, errors)
      value = card["deck_limit"]
      return value if value.nil? || value == "any" || (value.is_a?(Integer) && value >= 1)

      errors << "deck_limit: must be \"any\" or an integer >= 1"
      nil
    end

    # Power/toughness: an integer, or an amount for a characteristic-defining ability ("*", CR 604.3,
    # 208.2a), e.g. {"count": {"each": {"creature": {"types": ["artifact"]}}, "controller": "you"}}.
    # Returns [printed value, amount]; the defined value is computed in layer 7a (CR 613.4a).
    def read_pt(card, key, errors)
      value = card[key]
      return [read_stat(card, key, errors), nil] unless value.is_a?(Hash)

      amount = Mechanics::Amount.build(value, errors, key, targets_count: 0)
      unless Mechanics::Amount.layer_safe?(amount)
        errors << "#{key}: a characteristic-defining amount can't read power or toughness (CR 613.8)"
      end
      [0, amount]
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
      @ability_instances = (explicit + linked_instances(explicit) + intrinsic + keyword_abilities).freeze
      read_nested_abilities(explicit)
      @ability_instances.map(&:ability).freeze
    end

    # Abilities that come with another one ("When this permanent enters, if its evoke cost was paid, ...",
    # Abilities::Evoke), referenced as "<ref>:linked:<j>".
    def linked_instances(explicit)
      explicit.flat_map do |inst|
        linked = inst.ability.respond_to?(:linked_abilities) ? inst.ability.linked_abilities : EMPTY
        linked.each_with_index.map { |a, j| AbilityInstance.new(ref: "#{inst.ref}:linked:#{j}", ability: a) }
      end
    end

    # Keyword abilities that stand for an ability ("Station" is an activated ability, CR 702.184a).
    def keyword_abilities = @keywords.flat_map { CardDefinition.keyword_instances(it) }

    # Abilities nested in another ability (a station symbol's, CR 722.2), referenced as
    # "<parent ref>:<j>". They're part of the object's characteristics only while the parent applies.
    def read_nested_abilities(explicit)
      @nested_by_ref = explicit.to_h do |inst|
        nested = inst.ability.respond_to?(:nested_abilities) ? inst.ability.nested_abilities : EMPTY
        [inst.ref, nested.each_with_index.map { |a, j| AbilityInstance.new(ref: "#{inst.ref}:#{j}", ability: a) }.freeze]
      end.freeze
      @nested_instances = @nested_by_ref.values.flatten.freeze
    end

    def normalize(card)
      out = { "name" => @name }
      out["mana_cost"] = @mana_cost.to_s if @mana_cost
      out["colors"] = @colors.map(&:to_s) if card.key?("colors")
      out["types"] = @types.map(&:to_s)
      out["supertypes"] = @supertypes.map(&:to_s) unless @supertypes.empty?
      out["subtypes"] = @subtypes.map(&:to_s) unless @subtypes.empty?
      out["keywords"] = @keywords.map(&:to_s) unless @keywords.empty?
      %w[power toughness].each { |key| out[key] = normalized_stat(card, key) unless instance_variable_get("@#{key}").nil? }
      out["loyalty"] = @loyalty unless @loyalty.nil?
      out["abilities"] = deep_stringify(card["abilities"]) if card["abilities"].is_a?(Array) && !card["abilities"].empty?
      out["rules_text"] = @rules_text if @rules_text
      out["deck_limit"] = @deck_limit if @deck_limit
      deep_freeze(out)
    end

    # An integer, or the amount of a characteristic-defining ability as given.
    def normalized_stat(card, key) = card[key].is_a?(Hash) ? deep_stringify(card[key]) : instance_variable_get("@#{key}")

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
