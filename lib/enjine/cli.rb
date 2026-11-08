# frozen_string_literal: true

require "optparse"
require "enjine/card_pool/core"

module Enjine
  # Text interface: plays one game between two seats (human or random) using random
  # decks from the core card pool.
  class CLI
    SEATS = %w[human random].freeze

    def initialize(argv, input: $stdin, output: $stdout)
      @input = input
      @out = output
      @options = { seed: Random.new_seed % (2**32), p1: "human", p2: "random", quiet: false,
                   max_decisions: 100_000 }
      parser.parse!(argv)
    end

    def run
      game = build_setup.new_game(seed: @options[:seed])
      seats = { game.names[0] => seat(@options[:p1], 1), game.names[1] => seat(@options[:p2], 2) }
      log_viewer = log_viewer_for(seats)
      game.subscribe { |event| say(Text.event(event.for_viewer(log_viewer))) } unless @options[:quiet]
      say "Enjine #{VERSION} — seed #{@options[:seed]} — #{game.names.join(" vs ")}"
      say Text.history_entry(game.history.last, log_viewer) unless @options[:quiet]
      play(game, seats)
      say "Game over: #{Text.result(game.result)} (turn #{game.turn})"
      0
    end

    private

    def parser
      OptionParser.new do |o|
        o.banner = "Usage: enjine [options]"
        o.on("--seed N", Integer, "Random seed (decks and game)") { @options[:seed] = it }
        o.on("--p1 SEAT", SEATS, "Seat 1: human or random (default human)") { @options[:p1] = it }
        o.on("--p2 SEAT", SEATS, "Seat 2: human or random (default random)") { @options[:p2] = it }
        o.on("--quiet", "Only print the result") { @options[:quiet] = true }
        o.on("--max-decisions N", Integer, "Stop after N decisions") { @options[:max_decisions] = it }
      end
    end

    def build_setup
      rng = Rng.from_seed(@options[:seed])
      cards = CardPool::Core.cards
      players = %w[p1 p2].map { |n| Player.new(name: n, deck: CardPool::DeckBuilder.random(cards, rng: rng)) }
      Setup.new(*players)
    end

    def seat(kind, number) = kind == "human" ? :human : Agents::Random.new(seed: @options[:seed] + number)

    def log_viewer_for(seats)
      humans = seats.select { |_, s| s == :human }.keys
      humans.size == 1 ? humans.first : :observer
    end

    def play(game, seats)
      count = 0
      until game.over? || count >= @options[:max_decisions]
        decision = game.pending_decision
        seat = seats.fetch(decision.player)
        option = seat == :human ? ask(game, decision) : seat.choose(decision)
        break if option == :quit

        game.submit(option)
        count += 1
      end
      game.concede(game.pending_decision.player) unless game.over?
    end

    def ask(game, decision)
      say Text.board(game.view_for(decision.player))
      details = decision.details.map { |key, value| "#{key}: #{value}" }.join(", ")
      say "#{decision.player} — #{decision.kind}#{" (#{details})" unless details.empty?}:"
      decision.options.each_with_index { |opt, i| say "  #{i + 1}. #{Text.option(game, opt)}" }
      loop do
        @out.print "> "
        line = @input.gets
        return :quit if line.nil? || line.strip == "q"

        choice = Integer(line.strip, exception: false)
        return decision.options[choice - 1] if choice&.between?(1, decision.options.size)

        say "Enter 1-#{decision.options.size}, or q to concede."
      end
    end

    def say(text)
      @out.puts(text) if text
    end

    # Plain-text rendering of views, options and events.
    module Text
      module_function

      def board(view)
        lines = ["", "── Turn #{view["turn"]} · #{view["step"] || "pregame"} · active: #{view["active"] || "-"} ──"]
        view["players"].each do |pl|
          pool = pl["mana_pool"].map { |t, n| "{#{t}}" * n }.join
          lines << "#{pl["name"]}: life #{pl["life"]} · library #{pl["library_count"]} · hand #{pl["hand_count"]}" \
                   "#{" · pool #{pool}" unless pool.empty?}"
          lines << "  hand: #{pl["hand"].map { card(it) }.join(", ")}" if pl["hand"]
          lines << "  graveyard: #{pl["graveyard"].map { card(it) }.join(", ")}" unless pl["graveyard"].empty?
          perms = view["battlefield"].select { it["controller"] == pl["name"] }
          lines << "  battlefield: #{perms.map { card(it) }.join(", ")}" unless perms.empty?
        end
        lines.join("\n")
      end

      def card(obj) = "#{obj["name"]}#{" (tapped)" if obj["tapped"]} [#{obj["id"]}]"

      def option(game, opt)
        name = ->(id) { "#{game.catalog.fetch(game.state.object(id).card).name} [#{id}]" }
        case opt[:type]
        when "pass" then "Pass priority"
        when "play_land" then "Play #{name.call(opt[:object])}"
        when "activate_mana"
          ability = game.catalog.fetch(game.state.object(opt[:object]).card).abilities[opt[:ability]]
          "Activate #{name.call(opt[:object])}: #{ability}"
        when "discard", "bottom" then "#{opt[:type].capitalize} #{name.call(opt[:object])}"
        when "keep" then "Keep hand"
        when "mulligan" then "Mulligan"
        when "play", "draw" then "#{opt[:type].capitalize} first"
        else opt.inspect
        end
      end

      def history_entry(entry, viewer) = entry.for_viewer(viewer)["events"].map { event(it) }.join("\n")

      def event(event)
        case event["type"]
        when "zone_changed" then zone_changed(event)
        when "step_began" then "  · #{event["step"]}"
        when "turn_began" then "== Turn #{event["turn"]} (#{event["active"]}) =="
        when "priority_passed", "tapped", "untapped", "library_shuffled" then nil
        when "mana_added" then "#{event["player"]} adds #{event["mana"]}"
        when "player_lost" then "#{event["player"]} loses (#{event["reason"]})"
        else "#{event["type"]}: #{event.except("type").map { |k, v| "#{k}=#{v}" }.join(" ")}"
        end
      end

      def zone_changed(event)
        what = event["card"] ? "#{event["card"]} [#{event["new_id"]}]" : "a card"
        case event["reason"]
        when "draw" then "#{event["owner"]} draws #{what}"
        when "play_land" then "#{event["owner"]} plays #{what}"
        when "mulligan" then nil
        else "#{event["owner"]}: #{what} #{event["from"]} → #{event["to"]} (#{event["reason"]})"
        end
      end

      def result(result)
        result["winner"] ? "#{result["winner"]} wins by #{result["reason"]}" : "draw (#{result["reason"]})"
      end
    end
  end
end
