# frozen_string_literal: true

module Enjine
  # A frozen, compiled pairing of two ready players. Compile once, spawn many games:
  #
  #   setup = Enjine::Setup.new(alice, bob)
  #   game  = setup.new_game(seed: 42)
  #
  # The catalog and decklists are captured at compile time and shared by every game,
  # so later deck edits never affect an existing Setup.
  class Setup
    attr_reader :players, :catalog, :decklists

    def initialize(*players)
      players = players.flatten
      raise ArgumentError, "a game needs exactly 2 players" unless players.size == 2
      raise ArgumentError, "player names must differ" if players.map(&:name).uniq.size != 2

      players.each { |p| raise PlayerNotReady.new(p.deck.errors, name: p.name) unless p.ready? }

      @players = players.freeze
      @catalog = Catalog.new
      players.each { |p| @catalog.merge(p.deck.catalog) }
      @catalog.freeze
      @decklists = players.map { |p| p.deck.card_ids.freeze }.freeze
      freeze
    end

    def names = @players.map(&:name)

    def new_game(seed:)
      Game.start(catalog: @catalog, names: names, decklists: @decklists, seed: seed).tap do |game|
        @players.each { |p| p.seat(game) }
      end
    end

    # Resumes a game from a snapshot produced by Game#export.
    def import(snapshot)
      Game.import(snapshot, catalog: @catalog).tap do |game|
        @players.each { |p| p.seat(game) if game.names.include?(p.name) }
      end
    end
  end
end
