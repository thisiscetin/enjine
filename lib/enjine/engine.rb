# frozen_string_literal: true

module Enjine
  # The rules state machine.
  #
  # No Ruby call stack ever holds game progress: everything lives in State, so a
  # game can be exported at any decision and resumed elsewhere. #advance! runs the
  # game forward until a player must decide something (state.pending) or the game ends.
  class Engine
    HAND_SIZE = 7
    MAX_MULLIGANS = 7

    attr_accessor :state
    attr_reader :catalog

    def initialize(catalog, state, &emit)
      @catalog = catalog
      @state = state
      @emit = emit
    end

    def emit(event)
      touch! if volatile_layers? || Characteristics::LAYER_EVENTS.include?(event.class)
      record_history!(event) # before triggers look at it (see Engine::TurnHistory)
      @emit.call(event)
      watch_triggers!(event) unless event.is_a?(Events::AbilityTriggered)
    end

    def name(index) = state.players[index].name
    def names = state.players.map(&:name)
    def player(index) = state.players[index]
    def active_player = state.players[state.active]
    def definition(object) = catalog.fetch(object.card)
    def object(id) = state.objects.fetch(id)
    def ask!(pending) = state.pending = pending
    def step = Steps.fetch(state.step)
    def attackers = state.attackers

    # ---- decisions --------------------------------------------------------------

    def options
      return [] unless state.pending

      @options_memo = {}
      Decisions.fetch(state.pending["kind"]).options(self, state.pending)
    ensure
      @options_memo = nil
    end

    def submit!(option)
      Decisions.fetch(state.pending["kind"]).submit(self, state.pending, option)
      advance!
    end
  end
end
