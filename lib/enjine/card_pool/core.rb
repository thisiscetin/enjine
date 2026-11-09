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
        used += doc.fetch("outside", []).map { CardDefinition.slug(it["card"]) }
        { "cards" => cards.select { used.include?(CardDefinition.slug(it["name"])) }, "main" => doc["main"],
          "outside" => doc.fetch("outside", []), "description" => doc["description"] }
      end
    end

    # Builds random but legal decks from a card pool (a tooling helper, not game logic).
    module DeckBuilder
      module_function

      # A random deck of `size` cards drawn from the pool's cards, respecting the four-copy rule, plus
      # `outside` cards its player owns outside the game (CR 400.11a; the copy limit counts both, 100.4a).
      def random(cards, rng:, size: Deck::MIN_SIZE, outside: 0)
        definitions = cards.map { CardDefinition.from_h(it) }
        counts = Hash.new(0)
        extra = Hash.new(0)
        draw(definitions, counts, rng, size) { counts[it] += 1 }
        draw(definitions, counts, rng, outside) do |id|
          counts[id] += 1
          extra[id] += 1
        end
        doc = { "cards" => definitions.select { counts.key?(it.id) }.map(&:to_h),
                "main" => counts.filter_map { |id, n| { "card" => id, "count" => n - extra[id] } if n > extra[id] } }
        doc["outside"] = extra.map { |id, n| { "card" => id, "count" => n } } unless extra.empty?
        doc
      end

      # Picks `number` random cards that still fit the four-copy rule, yielding each one's id.
      def draw(definitions, counts, rng, number)
        number.times do
          defn = definitions[rng.rand(definitions.size)]
          defn = definitions[rng.rand(definitions.size)] until defn.deck_limit.nil? || counts[defn.id] < defn.deck_limit
          yield defn.id
        end
      end
    end
  end
end
