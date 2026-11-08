# frozen_string_literal: true

require "json"
require "enjine"

module Enjine
  # Opt-in card pools used for tests, seeding and the CLI. Never loaded by default.
  module CardPool
    # The core pool: card data blocks, validated by the same path as any user card.
    module Core
      PATH = File.join(__dir__, "core.json")

      def self.cards = JSON.parse(File.read(PATH)).freeze
      def self.catalog = Catalog.from_definitions(cards)
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
