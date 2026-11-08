# frozen_string_literal: true

module Enjine
  # A named player with a deck. The player is #ready? when the deck is valid.
  # While seated in an unfinished game the deck cannot be edited (DeckLocked).
  class Player
    attr_reader :name, :deck

    def initialize(name:, deck:)
      raise ArgumentError, "player name must be a non-empty string" unless name.is_a?(String) && !name.empty?

      @name = name.dup.freeze
      @deck = Deck.from_h(deck)
      @games = ObjectSpace::WeakMap.new
      @deck.guard = lambda {
        raise DeckLocked, "#{@name} is seated in an unfinished game; finish or concede it first" if playing?
      }
    end

    def ready? = @deck.valid?

    # True while any game this player is seated in has not ended.
    def playing? = @games.keys.any? { |game| !game.over? }

    # @api private
    def seat(game)
      @games[game] = true
    end
  end
end
