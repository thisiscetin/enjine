# frozen_string_literal: true

# Determinism harness for performance work: plays many seeded random games and prints one digest per game
# covering every decision's kind, player, details and legal option list (in order), the chosen option, periodic
# probes (views for both players and the observer, export/import, a rolled-back apply, a fork played on) and the
# final export. A performance change must leave every digest unchanged (same legal options in the same order,
# same RNG consumption, same results).
#
#   ruby -Ilib script/determinism_digest.rb [games_per_config=80] [out=tmp/digests.txt] [workers=8]
#
# Configs: constructed example decks, constructed random fixture decks (with outside cards), constructed random
# decks of the hand-written real cards, and Duel Commander random decks. Compare two runs with `diff`.
require "digest"
require "fileutils"
require "enjine"
require_relative "../spec/support/card_fixtures"

GAMES = Integer(ARGV[0] || 80)
OUT = ARGV[1] || "tmp/digests.txt"
WORKERS = Integer(ARGV[2] || 8)
MAX_DECISIONS = 20_000
SNAPSHOT_EVERY = 97
VIEW_EVERY = 13
APPLY_EVERY = 7

# Looks at the game the ways a caller may (views, export/import, a failed apply that rolls back, a fork played on)
# and hashes what it sees, so a cache that goes stale on any of those paths changes the digest. Nothing here
# changes the game itself.
def probe(game, sha, seed, count)
  engine = game.instance_variable_get(:@engine)
  (game.names + ["observer"]).each { sha << JSON.generate(game.view_for(it)) } if (count % VIEW_EVERY).zero?
  return unless (count % SNAPSHOT_EVERY).zero?

  sha << game.export
  copy = Enjine::Game.import(game.export, catalog: game.catalog)
  sha << Marshal.dump(copy.pending_decision&.options)
  # a transaction that fails after one legal submission rolls the same engine back
  begin
    game.apply([game.legal_options.first, { type: "no such option" }])
  rescue Enjine::IllegalDecision
    sha << Marshal.dump(game.pending_decision.options)
  end
  side = game.fork # play a fork on; the original must be unaffected
  helper = Enjine::Agents::Random.new(seed: (seed * 7919) + count)
  5.times { side.submit(helper.choose(side.pending_decision)) unless side.over? }
  sha << side.export
  sha << Marshal.dump(engine.options) # recomputed, not the memoized decision
end

def real_pool
  @real_pool ||= CardFixtures.real_cards.select do |card|
    Enjine::CardDefinition.from_h(card)
    true
  rescue Enjine::Error
    false
  end
end

def players_for(config, seed)
  rng = Enjine::Rng.from_seed(seed)
  decks = CardFixtures.deck_names
  format = config == "commander" ? Enjine::Format.fetch("duel_commander") : Enjine::Format::CONSTRUCTED
  players = %w[p1 p2].map do |name|
    deck = case config
           when "examples" then CardFixtures.deck(decks[rng.rand(decks.size)])
           when "fixtures" then Enjine::Fuzz.random_deck(CardFixtures.cards, rng: rng, outside: 7)
           when "real" then Enjine::Fuzz.random_deck(real_pool + CardFixtures.cards.select { it["supertypes"]&.include?("basic") },
                                                     rng: rng)
           else Enjine::Fuzz.random_commander_deck(CardFixtures.cards, rng: rng)
           end
    Enjine::Player.new(name: name, deck: deck)
  end
  Enjine::Setup.new(*players, format: format)
end

def play(config, seed)
  game = players_for(config, seed).new_game(seed: seed)
  agent = Enjine::Agents::Random.new(seed: seed)
  sha = Digest::SHA256.new
  count = 0
  until game.over? || count >= MAX_DECISIONS
    decision = game.pending_decision
    sha << Marshal.dump([decision.kind, decision.player, decision.details.to_a.sort_by(&:first).inspect, decision.options])
    probe(game, sha, seed, count)
    choice = agent.choose(decision)
    sha << choice.inspect
    (count % APPLY_EVERY).zero? ? game.apply([choice]) : game.submit(choice)
    count += 1
  end
  sha << game.export
  sha << game.decision_log.inspect
  format("%-9s %6d %6d %s", config, seed, count, sha.hexdigest)
rescue StandardError => e
  format("%-9s %6d ERROR %s: %s", config, seed, e.class, e.message[0, 200])
end

jobs = %w[examples fixtures real commander].flat_map { |config| (1..GAMES).map { [config, it] } }
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
slices = jobs.each_with_index.group_by { |_, i| i % WORKERS }.values.map { |pairs| pairs.map(&:first) }
readers = slices.map do |slice|
  reader, writer = IO.pipe
  fork do
    reader.close
    slice.each { writer.puts(play(*it)) }
    writer.close
  end
  writer.close
  reader
end
lines = readers.flat_map { it.read.lines.map(&:chomp) }.sort_by { |l| [l[0, 9], l[10, 6].to_i] }
Process.waitall
FileUtils.mkdir_p(File.dirname(OUT))
File.write(OUT, "#{lines.join("\n")}\n")
puts format("%d games in %.1fs -> %s (%d errors)", lines.size, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
            OUT, lines.count { it.include?("ERROR") })
