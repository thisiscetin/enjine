# frozen_string_literal: true

module Enjine
  # A set of card definitions keyed by id. Built per game from the players' decks;
  # there is no global card registry.
  class Catalog
    include Enumerable

    def self.from_definitions(list)
      new.tap { |c| list.each { c.add(it) } }
    end

    def initialize
      @definitions = {}
      @faces = {} # a card's other faces, by face id ("alfa/1", see CardDefinition::Faces)
    end

    # Adds a definition (CardDefinition or data Hash). Raises CatalogConflict when a
    # different definition with the same id is already present.
    def add(definition)
      defn = CardDefinition.from_h(definition)
      existing = @definitions[defn.id]
      raise CatalogConflict, "two different definitions for #{defn.name.inspect} (#{defn.id})" if existing && existing != defn

      @definitions[defn.id] ||= defn
      defn.other_faces.each { @faces[it.id] = it }
      defn.token_definitions.each { add(it) unless @definitions.key?(it.id) }
      defn
    end

    def merge(other)
      other.each { add(it) }
      self
    end

    # Accepts an id ("lightning_bolt") or a display name ("Lightning Bolt"). Ids hit an exact
    # lookup; only names pay for slugging (Unicode normalization), so the engine's hot path stays cheap.
    def fetch(ref)
      @definitions[ref] || @faces[ref] ||
        @definitions.fetch(CardDefinition.slug(ref)) { raise KeyError, "unknown card #{ref.inspect}" }
    end

    def [](ref) = @definitions[ref] || @faces[ref] || @definitions[CardDefinition.slug(ref)]
    def include?(ref) = @definitions.key?(ref) || @faces.key?(ref) || @definitions.key?(CardDefinition.slug(ref))
    def ids = @definitions.keys
    def size = @definitions.size
    def each(&) = @definitions.each_value(&)
    def to_a = @definitions.values.map(&:to_h)

    def freeze
      @definitions.freeze
      @faces.freeze
      super
    end
  end
end
