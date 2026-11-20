# frozen_string_literal: true

module Enjine
  # The rules a game is set up with: how it starts and what a legal deck is. `CONSTRUCTED` is the default
  # (CR 100.2, 103.4); `DUEL_COMMANDER` is the two-player Commander variant (CR 903).
  #
  #   Enjine::Setup.new(alice, bob, format: :duel_commander)
  #
  # A format is plain data: a game keeps only its name (State#format round-trips through snapshots).
  Format = Data.define(:name, :starting_life, :deck_size, :commander) do
    # `deck_size`: the sizes a deck may have, its commander included (CR 903.5a).
    def commander? = commander

    # The most copies of `definition` a deck may hold, nil for any number. Constructed: its own limit (CR 100.2a).
    # Commander: one of each card named differently, only basic lands exempt (CR 903.5b).
    def copy_limit(definition)
      return definition.deck_limit unless commander?

      definition.supertype?(:basic) ? nil : 1
    end

    def to_s = name
  end

  class Format
    CONSTRUCTED = new(name: "constructed", starting_life: 20, deck_size: 60.., commander: false) # CR 100.2a, 103.4
    DUEL_COMMANDER = new(name: "duel_commander", starting_life: 40, deck_size: 100..100, commander: true) # CR 903.5a, 903.7
    ALL = [CONSTRUCTED, DUEL_COMMANDER].freeze

    # Whether a card may be a commander: a legendary creature, Vehicle, or Spacecraft with power and toughness
    # (CR 903.3). Cards that say they can be your commander are deferred.
    def self.commander_card?(definition)
      return false unless definition.supertype?(:legendary)

      definition.type?(:creature) || definition.subtypes.include?(:vehicle) ||
        (definition.subtypes.include?(:spacecraft) && stationed?(definition))
    end

    # A Spacecraft has power and toughness through a station symbol (CR 722.2b).
    def self.stationed?(definition)
      definition.abilities.any? { it.kind == :station_symbol && it.power }
    end
    private_class_method :stationed?

    # The format a name (or a Format) stands for.
    def self.fetch(value)
      return value if value.is_a?(Format)

      ALL.find { it.name == value.to_s } or
        raise ArgumentError, "unknown format #{value.inspect} (use #{ALL.map { ":#{it.name}" }.join(", ")})"
    end
  end
end
