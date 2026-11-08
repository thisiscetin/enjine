# frozen_string_literal: true

require "json"

module Enjine
  # The public face of one game.
  #
  #   decision = game.pending_decision   # => Decision(player:, kind:, options:)
  #   game.submit(decision.options.first)
  #
  # Every call either fully succeeds or raises and leaves the game untouched.
  class Game
    # The decision the engine is waiting for.
    Decision = Data.define(:player, :kind, :options, :details) do
      def to_h
        { "player" => player, "kind" => kind, "options" => options.map { it.transform_keys(&:to_s) } }
          .merge(details)
      end
    end

    attr_reader :catalog, :history

    def self.start(catalog:, names:, decklists:, seed:)
      new(catalog, State.initial(names: names, decklists: decklists, seed: seed)).tap(&:start!)
    end

    # Resumes a game from #export output (a JSON String or the parsed Hash).
    def self.import(snapshot, catalog:)
      data = snapshot.is_a?(String) ? parse_json(snapshot) : Snapshot.deep_stringify(snapshot)
      raise InvalidSnapshot, ["snapshot must contain \"state\""] unless data.is_a?(Hash) && data["state"]

      state = Snapshot.load(data["state"], catalog)
      history = Array(data["history"]).map { HistoryEntry.from_h(it) }
      game = new(catalog, state, history)
      verify_pending!(game)
      game
    rescue ArgumentError, KeyError, NoMethodError, TypeError => e
      raise InvalidSnapshot, ["malformed snapshot: #{e.message}"]
    end

    def self.parse_json(text)
      JSON.parse(text)
    rescue JSON::ParserError => e
      raise InvalidSnapshot, ["not valid JSON: #{e.message}"]
    end

    def self.verify_pending!(game)
      return if game.over? || !game.pending_decision.options.empty?

      raise InvalidSnapshot, ["pending #{game.state.pending["kind"]} decision has no legal options"]
    end
    private_class_method :parse_json, :verify_pending!

    def initialize(catalog, state, history = [])
      @catalog = catalog
      @history = history
      @subscribers = []
      @buffer = []
      @engine = Engine.new(catalog, state) { |event| @buffer << event }
    end

    # @api private
    def start!
      record(nil, nil) { @engine.start! }
    end

    def state = @engine.state
    def names = @engine.names
    def over? = state.over?
    def result = state.result&.dup
    def turn = state.turn
    def step = state.step

    def pending_decision
      pending = state.pending
      return nil unless pending

      @pending_decision = nil if @pending_for != @version
      @pending_for = @version
      @pending_decision ||= Decision.new(
        player: @engine.name(pending["player"]), kind: pending["kind"], options: @engine.options.freeze,
        details: pending.except("kind", "player")
      )
    end

    def legal_options = pending_decision&.options || []

    # Submits one option for the pending decision. Returns the HistoryEntry it produced.
    def submit(option)
      decision = pending_decision
      raise IllegalDecision, "the game is over" unless decision

      chosen = normalize(option)
      unless decision.options.include?(chosen)
        raise IllegalDecision.new("#{chosen.inspect} is not a legal option for #{decision.kind}",
                                  option: chosen, legal_options: decision.options)
      end
      record(decision.player, decision.kind, chosen) { @engine.submit!(chosen) }
    end

    # Fast-forwards through a list of options, all or nothing.
    def apply(options)
      transaction do
        options.each_with_index do |option, index|
          submit(option)
        rescue IllegalDecision => e
          raise IllegalDecision.new(e.message, option: e.option, legal_options: e.legal_options, index: index)
        end
      end
      self
    end

    # CR 104.3a: a player may concede at any time.
    def concede(player)
      raise IllegalDecision, "the game is over" if over?

      index = player_index(player)
      record(names[index], "concede", { type: "concede" }) { @engine.concede!(index) }
    end

    # Starts this game over from its opening, with the same or a new seed.
    def restart(seed: nil)
      fresh = State.initial(names: names, decklists: state.decklists, seed: seed.nil? ? state.seed : seed)
      @engine.state = fresh
      @history = []
      @buffer.clear
      start!
      self
    end

    def view_for(viewer) = View.build(@engine, viewer_key(viewer))
    def history_for(viewer) = @history.map { it.for_viewer(viewer_key(viewer)) }

    # Ids of every decision submitted so far: with the seed this replays the game.
    def decision_log = @history.reject { it.option.nil? || it.kind == "concede" }.map { it.option.transform_keys(&:to_s) }

    def subscribe(&block)
      @subscribers << block
      self
    end

    def to_h = { "state" => state.to_h, "history" => @history.map(&:to_h) }
    def export = JSON.generate(to_h)

    private

    def record(player, kind, option = nil)
      @version = @version.to_i + 1
      @buffer.clear
      before = [state.turn, state.step&.to_s]
      yield
      entry = HistoryEntry.new(seq: @history.size + 1, turn: before[0], step: before[1], player: player,
                               kind: kind, option: option, events: @buffer.dup.freeze)
      @history << entry
      deliver(entry.events) unless @in_transaction
      entry
    end

    def transaction
      saved = Marshal.dump(state)
      history_size = @history.size
      @in_transaction = true
      yield
      @in_transaction = false
      deliver(@history[history_size..].flat_map(&:events))
    rescue StandardError
      @in_transaction = false
      @engine.state = Marshal.load(saved) # rubocop:disable Security/MarshalLoad
      @version += 1
      @history = @history.first(history_size)
      raise
    end

    def deliver(events)
      events.each { |event| @subscribers.each { it.call(event) } }
    end

    def normalize(option)
      raise IllegalDecision, "an option must be a Hash, got #{option.class}" unless option.is_a?(Hash)

      option.to_h { |k, v| [k.to_sym, v.is_a?(Symbol) ? v.to_s : v] }
    end

    def player_index(player)
      names.index(player.respond_to?(:name) ? player.name : player) or
        raise ArgumentError, "unknown player #{player.inspect}"
    end

    def viewer_key(viewer)
      return :observer if viewer.to_s == "observer"

      names[player_index(viewer)]
    end
  end
end
