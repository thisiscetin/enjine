# frozen_string_literal: true

module Enjine
  # Base class of every error raised by Enjine.
  class Error < StandardError; end

  # Raised when an error carries a list of individual problems.
  class ErrorList < Error
    attr_reader :errors

    def initialize(errors, prefix)
      @errors = errors.freeze
      super("#{prefix}:\n" + errors.map { |e| "  - #{e}" }.join("\n"))
    end
  end

  # A submitted option is not legal for the pending decision.
  class IllegalDecision < Error
    attr_reader :option, :legal_options, :index

    def initialize(message, option: nil, legal_options: [], index: nil)
      @option = option
      @legal_options = legal_options
      @index = index
      super(index.nil? ? message : "decision ##{index}: #{message}")
    end
  end

  # A card data block failed validation. #errors lists every problem with its path.
  class InvalidCardDefinition < ErrorList
    def initialize(errors, name: nil)
      super(errors, "invalid card definition#{" (#{name})" if name}")
    end
  end

  # A deck document is malformed or references unknown cards.
  class InvalidDeck < ErrorList
    def initialize(errors)
      super(errors, "invalid deck")
    end
  end

  # A player whose deck is not valid tried to take a seat.
  class PlayerNotReady < ErrorList
    def initialize(errors, name:)
      super(errors, "player #{name} is not ready")
    end
  end

  # A snapshot could not be imported because it is inconsistent.
  class InvalidSnapshot < ErrorList
    def initialize(errors)
      super(errors, "invalid snapshot")
    end
  end

  # Two definitions with the same id but different contents.
  class CatalogConflict < Error; end

  # A deck was edited while its player is seated in an unfinished game.
  class DeckLocked < Error; end
end
