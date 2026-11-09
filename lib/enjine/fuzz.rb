# frozen_string_literal: true

module Enjine
  # Plays random games choosing uniformly among legal options and checks the
  # engine's invariants after every decision. A crash, a stall, a broken invariant
  # or an export/import mismatch raises Fuzz::Failure with the seed to reproduce it.
  module Fuzz
    # Raised when a fuzzed game breaks; carries the reproduction data.
    class Failure < Error
      attr_reader :seed, :decisions

      def initialize(message, seed:, decisions:)
        @seed = seed
        @decisions = decisions
        super("#{message} (seed #{seed}, after #{decisions} decisions)")
      end
    end

    Result = Data.define(:games, :decisions, :turns, :outcomes, :casts, :seconds)

    module_function

    # A random legal deck of `size` cards drawn uniformly from `cards` (card data blocks), whatever their colors,
    # plus `outside` cards its player owns outside the game (CR 400.11a; the copy limit counts both, 100.4a).
    def random_deck(cards, rng:, size: Deck::MIN_SIZE, outside: 0)
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

    # roundtrip_every: export+import and compare every N decisions (0 disables).
    def run(setup, games:, seed: 0, max_decisions: 20_000, roundtrip_every: 0, invariants: true, monitor: true)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      totals = { decisions: 0, turns: 0, outcomes: Hash.new(0), casts: Hash.new(0) }
      games.times do |i|
        game_seed = seed + i
        game = setup.new_game(seed: game_seed)
        game.subscribe { |e| totals[:casts][e.card] += 1 if e.is_a?(Events::SpellCast) || e.is_a?(Events::AbilityActivated) }
        watcher = monitor ? RulesMonitor.new(game) : nil
        decisions = play(game, Agents::Random.new(seed: game_seed), game_seed, max_decisions, roundtrip_every,
                         invariants, watcher)
        totals[:decisions] += decisions
        totals[:turns] += game.turn
        totals[:outcomes][game.result["reason"]] += 1
      end
      Result.new(games: games, decisions: totals[:decisions], turns: totals[:turns],
                 outcomes: totals[:outcomes].to_h,
                 casts: totals[:casts].sort_by do |card, n|
                   [-n, card]
                 end.to_h, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end

    def play(game, agent, seed, max_decisions, roundtrip_every, invariants, watcher = nil)
      count = 0
      until game.over?
        raise Failure.new("game exceeded #{max_decisions} decisions", seed: seed, decisions: count) if count >= max_decisions

        begin
          entry = game.submit(agent.choose(game.pending_decision))
        rescue Failure
          raise
        rescue StandardError => e
          raise Failure.new("#{e.class}: #{e.message}", seed: seed, decisions: count)
        end
        count += 1
        check!(game, seed, count) if invariants
        watch!(watcher, entry, seed, count) if watcher
        roundtrip!(game, seed, count) if roundtrip_every.positive? && (count % roundtrip_every).zero?
      end
      count
    end

    def watch!(watcher, entry, seed, count)
      found = watcher.check!(entry)
      return if found.empty?

      first = found.first
      raise Failure.new("rules finding CR #{first.rule}: #{first.message}", seed: seed, decisions: count)
    end

    def check!(game, seed, count)
      errors = Snapshot.validate(game.state.to_h, game.catalog)
      raise Failure.new("invariant broken: #{errors.join("; ")}", seed: seed, decisions: count) unless errors.empty?
    end

    def roundtrip!(game, seed, count)
      copy = Game.import(game.export, catalog: game.catalog)
      same = copy.state.to_h == game.state.to_h && copy.pending_decision&.options == game.pending_decision&.options
      raise Failure.new("export/import roundtrip changed the game", seed: seed, decisions: count) unless same
    end
  end
end
