# frozen_string_literal: true

module Enjine
  # A player's deck: the card definitions it uses plus the main decklist.
  #
  #   Deck.from_h({"cards" => [{...Forest...}], "main" => [{"card" => "Forest", "count" => 60}]})
  #
  # Constructed rules (CR 100.2a): at least 60 cards, at most 4 copies of any card
  # that is not exempt (basic lands). An invalid deck can still be built and edited;
  # it is simply not #valid?, so its player is not ready.
  class Deck
    MIN_SIZE = 60
    MAX_COPIES = 4

    attr_reader :catalog
    attr_writer :guard

    def self.from_h(hash)
      return hash if hash.is_a?(Deck)
      raise InvalidDeck.new(["deck must be an object"]) unless hash.is_a?(Hash)

      doc = hash.transform_keys(&:to_s).except("name", "description")
      cards = doc.fetch("cards", [])
      main = doc.fetch("main", [])
      raise InvalidDeck.new(["cards: must be a list"]) unless cards.is_a?(Array)
      raise InvalidDeck.new(["main: must be a list"]) unless main.is_a?(Array)

      new(cards: cards, main: main)
    end

    def initialize(cards: [], main: [])
      @catalog = Catalog.new
      cards.each { @catalog.add(it) }
      @entries = {}
      @reference_errors = []
      main.each_with_index { |entry, i| load_entry(entry, i) }
    end

    # Ordered {id => count}.
    def entries = @entries.dup.freeze
    def size = @entries.values.sum
    def count(card) = @entries.fetch(CardDefinition.slug(card), 0)

    # Flat list of definition ids, one per physical card.
    def card_ids = @entries.flat_map { |id, n| [id] * n }

    def errors
      errs = @reference_errors.dup
      errs << "deck has #{size} cards; at least #{MIN_SIZE} are required (CR 100.2a)" if size < MIN_SIZE
      @entries.each do |id, n|
        next if n <= MAX_COPIES || @catalog.fetch(id).deck_limit_exempt?

        errs << "#{@catalog.fetch(id).name}: #{n} copies; at most #{MAX_COPIES} are allowed (CR 100.2a)"
      end
      errs
    end

    def valid? = errors.empty?

    # Adds a card definition this deck can then use.
    def define(definition)
      check_guard!
      @catalog.add(definition)
    end

    def add(card, count: 1)
      check_guard!
      id = resolve!(card)
      @entries[id] = @entries.fetch(id, 0) + positive!(count)
      self
    end

    def remove(card, count: 1)
      check_guard!
      id = resolve!(card)
      have = @entries.fetch(id, 0)
      raise InvalidDeck.new(["cannot remove #{count} #{card}: deck has #{have}"]) if have < positive!(count)

      have == count ? @entries.delete(id) : @entries[id] = have - count
      self
    end

    # Swaps cards between games; no limit on how many.
    def swap(out:, in:, count: 1)
      incoming = binding.local_variable_get(:in)
      check_guard!
      resolve!(incoming)
      remove(out, count: count)
      add(incoming, count: count)
    end

    def to_h
      { "cards" => @catalog.to_a, "main" => @entries.map { |id, n| { "card" => id, "count" => n } } }
    end

    private

    def load_entry(entry, index)
      card, count = entry.is_a?(Hash) ? entry.transform_keys(&:to_s).values_at("card", "count") : []
      unless card.is_a?(String) && count.is_a?(Integer) && count.positive?
        return @reference_errors << "main[#{index}]: must be {\"card\": name, \"count\": positive integer}"
      end
      return @reference_errors << "main[#{index}]: card #{card.inspect} is not defined in cards" unless @catalog.include?(card)

      id = CardDefinition.slug(card)
      @entries[id] = @entries.fetch(id, 0) + count
    end

    def resolve!(card)
      raise InvalidDeck.new(["card #{card.inspect} is not defined in this deck"]) unless @catalog.include?(card)

      CardDefinition.slug(card)
    end

    def positive!(count)
      raise ArgumentError, "count must be a positive integer" unless count.is_a?(Integer) && count.positive?

      count
    end

    def check_guard!
      @guard&.call
    end
  end
end
