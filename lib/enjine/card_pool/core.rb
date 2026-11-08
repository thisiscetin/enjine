# frozen_string_literal: true

require "json"
require "enjine"

module Enjine
  # Opt-in card pools used for tests, seeding and the CLI. Never loaded by default.
  module CardPool
    # The core pool: card data blocks, validated by the same path as any user card.
    module Core
      PATH = File.join(__dir__, "core.json")

      DECKS = File.join(__dir__, "decks")

      def self.cards = JSON.parse(File.read(PATH)).freeze
      def self.catalog = Catalog.from_definitions(cards)

      # Names of the bundled sample decks.
      def self.deck_names = Dir[File.join(DECKS, "*.json")].map { File.basename(it, ".json") }.sort

      # A sample deck as a deck document: its decklist plus the card definitions it uses.
      def self.deck(name)
        path = File.join(DECKS, "#{name}.json")
        raise ArgumentError, "unknown sample deck #{name.inspect} (have: #{deck_names.join(", ")})" unless File.exist?(path)

        doc = JSON.parse(File.read(path))
        used = doc["main"].map { CardDefinition.slug(it["card"]) }
        { "cards" => cards.select { used.include?(CardDefinition.slug(it["name"])) }, "main" => doc["main"],
          "description" => doc["description"] }
      end
    end

    # Builds random but legal decks from a card pool (a tooling helper, not game logic).
    module DeckBuilder
      module_function

      # A random deck of `size` cards drawn from the pool's cards, respecting the four-copy rule.
      def random(cards, rng:, size: Deck::MIN_SIZE)
        definitions = cards.map { CardDefinition.from_h(it) }
        counts = Hash.new(0)
        while counts.values.sum < size
          defn = definitions[rng.rand(definitions.size)]
          next if !defn.deck_limit_exempt? && counts[defn.id] >= Deck::MAX_COPIES

          counts[defn.id] += 1
        end
        { "cards" => definitions.select { counts.key?(it.id) }.map(&:to_h),
          "main" => counts.map { |id, n| { "card" => id, "count" => n } } }
      end
    end
  end
end
