# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

desc "Regenerate SUPPORTED.md and docs/reference from the primitive registry"
task :docs do
  require_relative "lib/enjine"
  require_relative "lib/enjine/docs"
  Enjine::Docs.write
end

desc "Check that every cited CR rule number exists: rake cr_citations[path/to/MagicCompRules.txt]"
task :cr_citations, %i[cr] do |_, args|
  require_relative "script/check_cr_citations"
  status = CrCitations.main([args[:cr]].compact)
  abort "cited CR rule numbers are missing from the CR" unless status.zero?
end

desc "Play random games checking invariants: rake fuzz[games,seed]"
task :fuzz, %i[games seed] do |_, args|
  require_relative "lib/enjine"
  require_relative "lib/enjine/card_pool/core"
  games = Integer(args[:games] || 50)
  seed = Integer(args[:seed] || 0)
  rng = Enjine::Rng.from_seed(seed)
  cards = Enjine::CardPool::Core.cards
  decks = Enjine::CardPool::Core.deck_names
  # Even seeds pit two sample decks against each other; odd seeds use random pool decks.
  players = %w[p1 p2].map do |name|
    # Random decks own 7 cards outside the game (CR 400.11a), so play_from "outside" gets exercised.
    deck = if seed.even? then Enjine::CardPool::Core.deck(decks[rng.rand(decks.size)])
           else Enjine::CardPool::DeckBuilder.random(cards, rng: rng, outside: 7)
           end
    Enjine::Player.new(name: name, deck: deck)
  end
  result = Enjine::Fuzz.run(Enjine::Setup.new(*players), games: games, seed: seed, roundtrip_every: 251)
  puts format("%<g>d games, %<d>d decisions, %<s>.2fs (%<r>.0f decisions/s) outcomes=%<o>s",
              g: result.games, d: result.decisions, s: result.seconds, r: result.decisions / result.seconds,
              o: result.outcomes)
  puts "casts/activations by card: #{result.casts}"
end

desc "Benchmark random games per second (not a CI gate)"
task :bench do
  require_relative "lib/enjine"
  require_relative "lib/enjine/card_pool/core"
  require "benchmark/ips"
  cards = Enjine::CardPool::Core.cards
  rng = Enjine::Rng.from_seed(1)
  players = %w[p1 p2].map { Enjine::Player.new(name: it, deck: Enjine::CardPool::DeckBuilder.random(cards, rng: rng)) }
  setup = Enjine::Setup.new(*players)
  seed = 0
  Benchmark.ips do |x|
    x.report("random game") do
      game = setup.new_game(seed: seed += 1)
      agent = Enjine::Agents::Random.new(seed: seed)
      game.submit(agent.choose(game.pending_decision)) until game.over?
    end
  end
end

desc "Profile random games with stackprof: rake profile[games]"
task :profile, %i[games] do |_, args|
  require_relative "lib/enjine"
  require_relative "lib/enjine/card_pool/core"
  require "stackprof"
  cards = Enjine::CardPool::Core.cards
  rng = Enjine::Rng.from_seed(1)
  players = %w[p1 p2].map { Enjine::Player.new(name: it, deck: Enjine::CardPool::DeckBuilder.random(cards, rng: rng)) }
  setup = Enjine::Setup.new(*players)
  StackProf.run(mode: :cpu, out: "tmp/stackprof.dump") do
    Integer(args[:games] || 20).times do |i|
      game = setup.new_game(seed: i)
      agent = Enjine::Agents::Random.new(seed: i)
      game.submit(agent.choose(game.pending_decision)) until game.over?
    end
  end
  puts "wrote tmp/stackprof.dump — view with: bundle exec stackprof tmp/stackprof.dump --text"
end

task default: %i[spec rubocop]
