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
    end

    # Adds a definition (CardDefinition or data Hash). Raises CatalogConflict when a
    # different definition with the same id is already present.
    def add(definition)
      defn = CardDefinition.from_h(definition)
      existing = @definitions[defn.id]
      raise CatalogConflict, "two different definitions for #{defn.name.inspect} (#{defn.id})" if existing && existing != defn

      @definitions[defn.id] ||= defn
    end

    def merge(other)
      other.each { add(it) }
      self
    end

    def fetch(ref)
      @definitions.fetch(CardDefinition.slug(ref)) { raise KeyError, "unknown card #{ref.inspect}" }
    end

    def [](ref) = @definitions[CardDefinition.slug(ref)]
    def include?(ref) = @definitions.key?(CardDefinition.slug(ref))
    def ids = @definitions.keys
    def size = @definitions.size
    def each(&) = @definitions.each_value(&)
    def to_a = @definitions.values.map(&:to_h)

    def freeze
      @definitions.freeze
      super
    end
  end
end
