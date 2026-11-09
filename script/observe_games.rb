# frozen_string_literal: true

# Plays games between varied decks with Enjine::RulesMonitor checking every decision,
# then prints the mechanics observed and every rules finding.
#
#   ruby -Ilib script/observe_games.rb [games=10] [seed=1]
require "enjine"
require "enjine/deck_builder"
require_relative "../spec/support/card_fixtures"

games = Integer(ARGV[0] || 10)
seed = Integer(ARGV[1] || 1)
fxa = Enjine::DeckBuilder.new(CardFixtures.pool("fxa"))
fxb = Enjine::DeckBuilder.new(CardFixtures.pool("fxb"))
both = Enjine::DeckBuilder.new(CardFixtures.pool("fxa") + CardFixtures.pool("fxb"))
fixtures = Enjine::DeckBuilder.new(CardFixtures.cards)

decks = lambda do |i|
  rng = Enjine::Rng.from_seed((seed * 100) + i)
  sample = CardFixtures.deck_names
  case i % 5
  when 0 then [CardFixtures.deck(sample[i % 3]), CardFixtures.deck(sample[(i + 1) % 3])]
  when 1 then [CardFixtures.deck(sample[i % 3]), Enjine::Fuzz.random_deck(CardFixtures.cards, rng: rng)]
  when 2 then [fxa.build(seed: i, colors: 1), fxb.build(seed: i + 50, colors: 2)]
  when 3 then [both.build(seed: i, colors: 3), both.build(seed: i + 7, colors: 2)]
  else [fixtures.build(seed: i, colors: 2), CardFixtures.deck(sample[i % 3])]
  end
end

totals = Hash.new(0)
all_findings = []
games.times do |i|
  a, b = decks.call(i)
  setup = Enjine::Setup.new(Enjine::Player.new(name: "p1", deck: a), Enjine::Player.new(name: "p2", deck: b))
  game = setup.new_game(seed: seed + i)
  monitor = Enjine::RulesMonitor.new(game)
  agent = Enjine::Agents::Random.new(seed: seed + i)
  monitor.check!(game.history.last)
  decisions = 0
  until game.over? || decisions > 20_000
    entry = game.submit(agent.choose(game.pending_decision))
    monitor.check!(entry)
    decisions += 1
  end
  monitor.stats.each { |k, v| totals[k] += v }
  all_findings.concat(monitor.findings.map { [i, it] })
  puts format("game %2d: %-28s vs %-28s %5d decisions, turn %3d, %s, findings: %d",
              i + 1, (a["name"] || a["description"] || "random pool").to_s[0, 28],
              (b["name"] || b["description"] || "random pool").to_s[0, 28],
              decisions, game.turn, game.result.inspect, monitor.findings.size)
end

puts "\nMechanics observed:"
%w[spell_cast ability_activated resolved fizzled attacker_declared blocker_declared damage_assigned damage_dealt
   damage_to_players life_changed counters_+1/+1 counters_-1/-1 counters_loyalty effect_started effects_ended
   cast_cancelled mana_paid player_lost].each { |k| puts format("  %-20s %d", k, totals[k]) }
casts = totals.select { |k, _| k.start_with?("cast:") }.sort_by { -it[1] }
puts "  distinct cards cast: #{casts.size}"
puts "\nFindings (#{all_findings.size}):"
all_findings.first(40).each { |g, f| puts "  game #{g + 1} T#{f.turn} #{f.step} ##{f.seq} CR #{f.rule}: #{f.message}" }
