# frozen_string_literal: true

require "enjine/deck_builder"

module Enjine
  # Checks a folder of card data (require "enjine/verify"): every JSON file below `dir`, each a card or an
  # array of cards. It validates every card, builds random decks from the valid ones (one per color and color
  # pair the pool supports, plus decks that each include a handful of cards, so every card is in some deck),
  # plays rules-monitored games between them (Agents::Busy and Agents::Random seats, export/import round
  # trips), and records which cards were used: cast, played, activated, or had an ability trigger or resolve.
  # Cards still unused get decks of their own, each seated twice, for up to ROUNDS rounds in all.
  #
  #   report = Enjine::Verify.new("cards/", games: 20, seed: 1).run
  #   report["ok"]                   # => false if a card is invalid, a rules finding occurred or the engine raised
  #   puts Enjine::Verify.text(report)
  #
  # Same folder, games and seed: same report.
  class Verify
    TYPES = %w[creature instant sorcery artifact enchantment land planeswalker battle kindred].freeze
    SPELLS_PER_DECK = 6
    LANDS_PER_DECK = 3
    ROUNDS = 4
    ROUNDTRIP_EVERY = 97
    # Tiny pools still make decks: no outlier land counts, but basics may fill every slot the cards can't.
    PROFILE = { outlier_chance: 0, lands: { outliers: 20..Deck::MIN_SIZE } }.freeze
    PAIRINGS = [%i[busy busy], %i[busy random], %i[random busy]].freeze

    # One distinct card: where it was first seen, its type names, its definition (nil if invalid).
    Card = Data.define(:name, :file, :index, :types, :definition, :errors)

    def initialize(dir, games: 10, seed: 0, max_decisions: 20_000)
      raise ArgumentError, "#{dir}: not a directory" unless File.directory?(dir)

      @dir = dir
      @games = games
      @seed = seed
      @max_decisions = max_decisions
    end

    def run
      @cards = {}
      @invalid = []
      @used = Hash.new(0)
      @results = { findings: [], errors: [], unfinished: [], games: 0, decisions: 0 }
      Dir.glob("**/*.json", base: @dir).sort.each { load_file(it) }
      play_rounds unless valid.empty?
      report
    end

    # A readable report.
    def self.text(report)
      out = ["Enjine #{report["engine_version"]} (Comprehensive Rules #{report["rules_version"]}) — seed #{report["seed"]}",
             "#{report["cards"]} valid cards, #{report["games"]} games, #{report["decisions"]} decisions", "",
             "type            total  valid  exercised"]
      report["types"].each { |type, n| out << format("%-14s %6d %6d %10d", type, n["total"], n["valid"], n["exercised"]) }
      section(out, "Invalid cards", report["invalid"]) do
        "#{it["file"]}#{"[#{it["index"]}]" if it["index"]} #{it["name"]}: #{it["errors"].join("; ")}"
      end
      section(out, "Never exercised", report["unexercised"]) { "#{it["name"]} (#{it["file"]})" }
      section(out, "Rules monitor findings", report["findings"]) { "seed #{it["seed"]}: #{it["message"]} — #{it["decks"].join(" vs ")}" }
      section(out, "Engine errors", report["errors"]) { "seed #{it["seed"]}: #{it["message"]}" }
      section(out, "Unfinished games (decision cap)", report["unfinished"]) { "seed #{it["seed"]}" }
      out << "" << (report["ok"] ? "OK" : "FAILED")
      out.join("\n")
    end

    def self.section(out, title, rows, &)
      return if rows.empty?

      out << "" << "#{title} (#{rows.size}):"
      rows.each { out << "  #{yield it}" }
    end
    private_class_method :section

    private

    def valid = @cards.values.select(&:definition)

    # --- loading --------------------------------------------------------------------------------------

    def load_file(file)
      data = JSON.parse(File.read(File.join(@dir, file)))
      data.is_a?(Array) ? data.each_with_index { |card, i| add(file, i, card) } : add(file, nil, data)
    rescue JSON::ParserError => e
      @invalid << invalid(file, nil, nil, [], ["not valid JSON: #{e.message.lines.first.strip}"])
    end

    def add(file, index, data)
      return @invalid << invalid(file, index, nil, [], ["a card must be a JSON object"]) unless data.is_a?(Hash)

      defn = CardDefinition.from_h(data)
      held = @cards[defn.id]
      return @cards[defn.id] = Card.new(defn.name, file, index, type_names(data), defn, []) if held.nil?
      return if held.definition == defn # a reprint: the same card

      @invalid << invalid(file, index, defn.name, type_names(data), ["differs from #{defn.name} in #{held.file}"])
    rescue InvalidCardDefinition => e
      @invalid << invalid(file, index, data["name"], type_names(data), e.errors)
    end

    def invalid(file, index, name, types, errors) = Card.new(name, file, index, types, nil, errors)

    # Type names from the raw data, so an invalid card still counts: its own, or all its faces'.
    def type_names(data)
      types = [data, *(data["faces"].is_a?(Array) ? data["faces"] : [])].flat_map { it.is_a?(Hash) ? Array(it["types"]) : [] }
      types.grep(String).map(&:downcase).uniq
    end

    # --- decks and games ------------------------------------------------------------------------------

    def play_rounds
      @rng = Rng.from_seed(@seed)
      @builder = DeckBuilder.new(valid.map(&:definition))
      decks = coverage_decks(valid) + variety_decks
      ROUNDS.times do |round|
        play(decks, round.zero? ? @games : decks.size)
        rest = valid.reject { @used.key?(it.definition.id) }
        break if rest.empty?

        decks = coverage_decks(rest)
      end
    end

    # One deck per color and color pair the pool can fill.
    def variety_decks
      combos = Mana::COLORS.combination(1).to_a + Mana::COLORS.combination(2).to_a
      combos.filter_map do |colors|
        @builder.build(colors: colors, seed: @rng.rand(2**31), profile: PROFILE)
      rescue DeckBuilder::NotEnoughCards
        nil
      end
    end

    # Decks that together include every card in `cards`: grouped by the colors each needs (a land: the colors it
    # makes), a few spells and lands per deck. Colorless groups get random colors.
    def coverage_decks(cards)
      defns = cards.map(&:definition).reject { DeckBuilder.basic?(it) } # every deck has them
      groups = defns.group_by { it.land? ? DeckBuilder.produced_colors(it) : DeckBuilder.required_colors(it) }
      groups.sort_by { |colors, _| colors.join }.flat_map do |colors, defns|
        lands, spells = defns.partition(&:land?)
        spell_chunks = spells.each_slice(SPELLS_PER_DECK).to_a
        land_chunks = lands.each_slice(LANDS_PER_DECK).to_a
        Array.new([spell_chunks.size, land_chunks.size].max) do |i|
          including = (spell_chunks[i] || []) + (land_chunks[i] || [])
          coverage_deck(colors.empty? ? :any : colors, including.map(&:id))
        end
      end.compact
    end

    def coverage_deck(colors, including)
      @builder.build(colors: colors, seed: @rng.rand(2**31), profile: PROFILE, including: including)
    rescue Error, ArgumentError => e
      @results[:errors] << { "seed" => nil, "message" => "building a deck with #{including.join(", ")}: #{e.message}" }
      nil
    end

    # Seats every deck at least once, and plays at least `minimum` games.
    def play(decks, minimum)
      return if decks.empty?

      [minimum, (decks.size + 1) / 2].max.times do |i|
        game_seed = @seed + @results[:games]
        @results[:games] += 1
        play_game([decks[(2 * i) % decks.size], decks[((2 * i) + 1) % decks.size]], game_seed)
      end
    end

    # The rules monitor checks every decision; Snapshot invariants are the fuzz task's (they nearly halve the speed).
    def play_game(decks, seed)
      players = decks.each_with_index.map { |deck, i| Player.new(name: "p#{i + 1}", deck: deck) }
      game = Setup.new(*players).new_game(seed: seed)
      game.subscribe { use(it) }
      @results[:decisions] += Fuzz.play(game, seats(game, seed), seed, @max_decisions, ROUNDTRIP_EVERY, false, RulesMonitor.new(game))
    rescue Fuzz::Failure => e
      @results[:decisions] += e.decisions
      failure(e, decks)
    rescue Error => e
      @results[:errors] << { "seed" => seed, "message" => "#{e.class}: #{e.message}" }
    end

    def failure(error, decks)
      row = { "seed" => error.seed, "decisions" => error.decisions, "message" => error.message,
              "decks" => decks.map { it["description"] } }
      case error.kind
      when :finding then @results[:findings] << row
      when :stall then @results[:unfinished] << row
      else @results[:errors] << row
      end
    end

    # An agent for each seat, by the game's place in PAIRINGS.
    def seats(game, seed)
      agents = game.names.zip(PAIRINGS[seed % PAIRINGS.size]).to_h do |name, kind|
        [name, (kind == :busy ? Agents::Busy : Agents::Random).new(seed: seed + name.sum)]
      end
      Seats.new(agents)
    end

    Seats = Data.define(:agents) do
      def choose(decision) = agents.fetch(decision.player).choose(decision)
    end

    def use(event)
      card = case event
             when Events::SpellCast, Events::AbilityActivated, Events::AbilityTriggered, Events::Resolved then event.card
             when Events::ZoneChanged then event.card if event.reason == "play_land"
             end
      @used[card] += 1 if card
    end

    # --- report ---------------------------------------------------------------------------------------

    def report
      unused = valid.reject { @used.key?(it.definition.id) }
      { "engine_version" => VERSION, "rules_version" => RULES_VERSION, "seed" => @seed, "cards" => valid.size,
        "games" => @results[:games], "decisions" => @results[:decisions], "types" => type_counts,
        "invalid" => @invalid.map { { "file" => it.file, "index" => it.index, "name" => it.name, "errors" => it.errors } },
        "unexercised" => unused.sort_by(&:name).map { { "name" => it.name, "file" => it.file } },
        "findings" => @results[:findings], "errors" => @results[:errors], "unfinished" => @results[:unfinished],
        "ok" => @invalid.empty? && @results[:findings].empty? && @results[:errors].empty? }
    end

    def type_counts
      all = @cards.values + @invalid
      types = (TYPES & all.flat_map(&:types)) + (all.flat_map(&:types).uniq - TYPES).sort
      types.to_h do |type|
        cards = all.select { it.types.include?(type) }
        exercised = cards.count { it.definition && @used.key?(it.definition.id) }
        [type, { "total" => cards.size, "valid" => cards.count(&:definition), "exercised" => exercised }]
      end
    end
  end
end
