# frozen_string_literal: true

require "optparse"
require "enjine/card_pool/core"
require "enjine/deck_builder"
require_relative "cli/text"

module Enjine
  # Interactive text client. Hot-seat by default: you play both players, see what
  # the deciding player sees, pick numbered options, and after each choice see
  # exactly what happened. Seats can also be "random" (uniform legal choices).
  class CLI
    SEATS = %w[human random].freeze
    HELP = <<~HELP
      Commands:
        <number>   choose that option
        f          fast-forward: pass priority while passing is the only option
        b          show the board again          o   toggle observer view (see everything)
        h [n]      show the last n history entries (default 10)
        u          undo your last decision (replays the game from its seed)
        s FILE     save the game to FILE (JSON snapshot)
        c          concede for the deciding player
        q          quit
    HELP

    def initialize(argv, input: $stdin, output: $stdout)
      @input = input
      @out = output
      @options = { seed: Random.new_seed % (2**31), p1: "human", p2: "human", deck1: "gruul_beats",
                   deck2: "azorius_walkers", quiet: false, max_decisions: 100_000, observer: false, names: %w[alice bob],
                   sets_dir: Sets.dir }
      parser.parse!(argv)
      # `--random-deck sets=a,b colors=WU seed=7` works unquoted: the key=value words after it belong to the spec.
      @options[:random_deck] = [@options[:random_deck], *argv.grep(/=/)].compact.join(" ") if @options.key?(:random_deck)
    end

    def run
      return list_decks if @options[:list_decks]
      return validate(@options[:validate]) if @options[:validate]
      return list_sets if @options[:list_sets]
      return collection_report(@options[:collection_report]) if @options[:collection_report]
      return random_deck(@options[:random_deck]) if @options.key?(:random_deck)

      @game = start_game or return 1
      @text = Text.new(@game)
      @seats = @game.names.zip([@options[:p1], @options[:p2]]).to_h do |name, kind|
        [name, kind == "human" ? :human : Agents::Random.new(seed: @options[:seed] + name.sum)]
      end
      intro
      loop_decisions
      say @text.rule("GAME OVER: #{@text.result(@game.result)} · turn #{@game.turn}") if @game.over?
      0
    end

    private

    def parser
      OptionParser.new do |o|
        o.banner = "Usage: enjine [options]   (default: hot-seat, you play both players)"
        o.on("--seed N", Integer, "Seed for shuffling and the die roll") { @options[:seed] = it }
        o.on("--p1 SEAT", SEATS, "Seat 1: human (default) or random") { @options[:p1] = it }
        o.on("--p2 SEAT", SEATS, "Seat 2: human (default) or random") { @options[:p2] = it }
        o.on("--deck1 NAME", "Sample deck for seat 1 (default gruul_beats), or random:SPEC") { @options[:deck1] = it }
        o.on("--deck2 NAME", "Sample deck for seat 2 (default azorius_walkers), or random:SPEC") { @options[:deck2] = it }
        o.on("--random-deck [SPEC]", "Print a random deck as JSON, e.g. \"sets=trk,abc colors=WU seed=7\"") do
          @options[:random_deck] = it
        end
        o.on("--sets-dir DIR", "Directory of card set files (default: #{Sets::DEFAULT_DIR})") { @options[:sets_dir] = it }
        o.on("--list-sets", "List the card sets in the sets directory") { @options[:list_sets] = true }
        o.on("--collection FILE", "Build random decks only from the cards in this collection (JSON)") { @options[:collection] = it }
        o.on("--collection-report FILE", "Resolve a collection against the sets; prints a JSON report") do
          @options[:collection_report] = it
        end
        o.on("--names A,B", Array, "Player names (default alice,bob)") { @options[:names] = it }
        o.on("--list-decks", "List the sample decks") { @options[:list_decks] = true }
        o.on("--validate FILE", "Validate a JSON array of card data blocks; prints a JSON report") { @options[:validate] = it }
        o.on("--load FILE", "Resume a game saved with the s command") { @options[:load] = it }
        o.on("--observer", "Start in observer view (see both hands and library order)") { @options[:observer] = true }
        o.on("--quiet", "Only print the result (useful with random seats)") { @options[:quiet] = true }
        o.on("--max-decisions N", Integer, "Concede after N decisions") { @options[:max_decisions] = it }
      end
    end

    # Machine-readable validation for card-conversion pipelines. Exit code 1 if anything is invalid.
    def validate(path)
      cards = JSON.parse(File.read(path))
      cards = [cards] if cards.is_a?(Hash)
      report = { "rules_version" => RULES_VERSION, "engine_version" => VERSION, "valid" => [], "invalid" => [] }
      cards.each_with_index do |data, i|
        defn = CardDefinition.from_h(data)
        report["valid"] << { "index" => i, "id" => defn.id, "name" => defn.name, "card" => defn.to_h }
      rescue InvalidCardDefinition => e
        report["invalid"] << { "index" => i, "name" => data.is_a?(Hash) ? data["name"] : nil, "errors" => e.errors }
      end
      say JSON.pretty_generate(report)
      report["invalid"].empty? ? 0 : 1
    rescue JSON::ParserError => e
      say JSON.generate("error" => "not valid JSON: #{e.message}")
      1
    end

    def list_decks
      CardPool::Core.deck_names.each { say "#{it.ljust(18)} #{CardPool::Core.deck(it)["description"]}" }
      0
    end

    def list_sets
      today = Date.today
      Sets.all(dir: @options[:sets_dir]).each do |set|
        legal = set.standard_legal?(today) ? "standard" : "-"
        say "#{set.code.ljust(6)} #{set.name} (#{set.released_at}) · #{set.size} playable, " \
            "#{set.unsupported.size} unsupported · #{legal}"
      end
      0
    end

    # What a collection resolved to: resolved, unsupported and unknown entries. Exit code 1 if any are unknown.
    def collection_report(path)
      report = Collection.load(path, sets_dir: @options[:sets_dir]).report
      say JSON.pretty_generate(report)
      report["unknown"].empty? ? 0 : 1
    rescue Error => e
      say JSON.generate("error" => e.message)
      1
    end

    # Prints a random deck document; exit code 1 with a message if it can't be built.
    def random_deck(spec)
      say JSON.pretty_generate(build_random_deck(spec, @options[:seed]))
      0
    rescue Error, ArgumentError => e
      say "error: #{e.message}"
      1
    end

    # SPEC: whitespace- or comma-separated key=value pairs; a bare word continues the previous
    # value, so "sets=trk,abc,colors=WU" works. Keys: sets (codes, "all" or "standard"), colors
    # (letters like WU, a count 1-5, or any), seed, size, and with --collection, basics (unlimited or owned).
    def build_random_deck(spec, default_seed)
      args = parse_spec(spec.to_s)
      sets = args.delete("sets")
      DeckBuilder.build(sets: resolve_sets(sets), colors: args.delete("colors") || :any,
                        seed: Integer(args.delete("seed") || default_seed), size: Integer(args.delete("size") || 60),
                        sets_dir: @options[:sets_dir], collection: collection, basics: args.delete("basics") || :unlimited).tap do
        raise ArgumentError, "unknown random deck option(s): #{args.keys.join(", ")}" unless args.empty?
      end
    end

    def parse_spec(spec)
      key = nil
      spec.split(/[\s,;]+/).reject(&:empty?).each_with_object({}) do |word, out|
        if word.include?("=")
          key, value = word.split("=", 2)
          out[key] = value
        elsif key
          out[key] = "#{out[key]},#{word}"
        else
          raise ArgumentError, "random deck spec: expected key=value, got #{word.inspect}"
        end
      end
    end

    # The --collection, loaded once for every deck built in this run.
    def collection
      return nil unless @options[:collection]

      @collection ||= Collection.load(@options[:collection], sets_dir: @options[:sets_dir])
    end

    def resolve_sets(value)
      case value
      when nil, "all" then nil
      when "standard" then Sets.standard_legal(dir: @options[:sets_dir]).map(&:code)
      else value.split(",")
      end
    end

    def start_game
      @options[:load] ? load_game : new_game
    rescue DeckBuilder::NotEnoughCards, Sets::InvalidSet, Collection::InvalidCollection, ArgumentError => e
      say "error: #{e.message}"
      nil
    end

    def new_game
      decks = [@options[:deck1], @options[:deck2]].each_with_index.map { |name, i| deck_for(name, i) }
      players = @options[:names].zip(decks).map { |name, deck| Player.new(name: name, deck: deck) }
      @setup = Setup.new(*players)
      @setup.new_game(seed: @options[:seed])
    end

    # A sample deck by name, or "random[:SPEC]" for a generated one (seed defaults to game seed + seat).
    def deck_for(name, seat)
      return CardPool::Core.deck(name) unless name.start_with?("random")

      deck = build_random_deck(name.delete_prefix("random").delete_prefix(":"), @options[:seed] + seat)
      @options[:"deck#{seat + 1}"] = deck["description"]
      deck
    end

    def load_game
      Game.import(File.read(@options[:load]), catalog: CardPool::Core.catalog)
    end

    def intro
      return if @options[:quiet]

      say "Enjine #{VERSION} (Comprehensive Rules #{RULES_VERSION}) — seed #{@game.state.seed}"
      say "#{@game.names[0]}: #{@options[:deck1]}   #{@game.names[1]}: #{@options[:deck2]}   — type ? for help"
      show_events(@game.history.last) if @game.history.last
    end

    def loop_decisions
      count = 0
      until @game.over?
        if count >= @options[:max_decisions]
          @game.concede(@game.pending_decision.player)
          break
        end
        decision = @game.pending_decision
        seat = @seats.fetch(decision.player)
        option = seat == :human ? ask(decision) : seat.choose(decision)
        break if option == :quit
        next if option == :again

        entry = @game.submit(option)
        count += 1
        show_events(entry) unless @options[:quiet]
      end
    end

    def ask(decision)
      show_board(decision)
      loop do
        @out.print "#{decision.player}> "
        line = @input.gets
        return :quit if line.nil?

        result = command(line.strip, decision)
        return result unless result.nil?
      end
    end

    def show_board(decision)
      say @text.board(@game.view_for(viewer(decision)))
      say ""
      say @text.decision(decision)
      decision.options.each_with_index { |opt, i| say format("  %2d) %s", i + 1, @text.option(opt)) }
    end

    def viewer(decision) = @options[:observer] ? :observer : decision.player

    # Returns an option, :quit, :again (decision changed), or nil to keep asking.
    def command(line, decision)
      case line
      when /\A\d+\z/
        option = decision.options[line.to_i - 1]
        option || (say("Choose 1-#{decision.options.size}.") && nil)
      when "f" then fast_forward
      when "b" then show_board(decision) && nil
      when "o"
        @options[:observer] = !@options[:observer]
        say "Observer view #{@options[:observer] ? "on" : "off"}."
        show_board(decision)
        nil
      when /\Ah(?:\s+(\d+))?\z/ then show_history(Integer(::Regexp.last_match(1) || 10)) && nil
      when "u" then undo
      when /\As\s+(\S+)\z/ then save(::Regexp.last_match(1)) && nil
      when "c" then @game.concede(decision.player) && :again
      when "q" then :quit
      when "?", "help" then say(HELP) && nil
      else say("Unknown command. Type ? for help.") && nil
      end
    end

    def fast_forward
      passed = 0
      while !@game.over? && @game.legal_options == [{ type: "pass" }] && @seats[@game.pending_decision.player] == :human
        show_events(@game.submit(type: "pass"))
        passed += 1
      end
      say "(passed #{passed} time#{"s" unless passed == 1})"
      :again
    end

    def undo
      log = @game.decision_log
      if log.empty? || @setup.nil?
        say(@setup ? "Nothing to undo." : "Undo needs a game started in this session.")
        return nil
      end
      @game = @setup.new_game(seed: @game.state.seed).apply(log[0...-1])
      @text = Text.new(@game)
      say "Undid #{@text.option(log.last.transform_keys(&:to_sym))}."
      :again
    end

    def save(path)
      File.write(path, @game.export)
      say "Saved to #{path}. Resume with: enjine --load #{path}"
    end

    def show_history(count)
      viewer = @options[:observer] ? :observer : @game.pending_decision&.player || :observer
      @game.history_for(viewer).last(count).each do |entry|
        who = if entry["player"]
                "#{entry["player"]}: #{entry["option"] ? @text.option(entry["option"].transform_keys(&:to_sym)) : entry["kind"]}"
              else
                "(game)"
              end
        say "  ##{entry["seq"]} T#{entry["turn"]} #{entry["step"] || "pregame"} — #{who}"
        @text.events(entry["events"]).each { say "      #{it}" }
      end
    end

    def show_events(entry)
      viewer = @options[:observer] || @seats.values.none?(:human) ? :observer : entry.player || :observer
      lines = @text.events(entry.for_viewer(viewer)["events"])
      lines.each { say "  #{it}" }
    end

    def say(text)
      @out.puts(text) unless text.nil?
      true
    end
  end
end
