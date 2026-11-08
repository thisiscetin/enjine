# frozen_string_literal: true

RSpec.describe "Full games between collection-built decks" do
  let(:collection) { Enjine::Collection.load(DeckBuilderHelpers::BINDER, sets_dir: DeckBuilderHelpers::SET_FIXTURES) }

  it "plays random agents to the end with no rules findings" do
    [%w[R WU], [2, "WU"], [:any, 2]].each_with_index do |(one, two), i|
      alice = Enjine::Player.new(name: "alice", deck: build_deck(collection: collection, colors: one, seed: 20 + i))
      bob = Enjine::Player.new(name: "bob", deck: build_deck(collection: collection, colors: two, seed: 30 + i,
                                                             basics: two == "WU" ? :owned : :unlimited))
      game = Enjine::Setup.new(alice, bob).new_game(seed: i)
      monitor = Enjine::RulesMonitor.new(game)
      agents = game.names.to_h { [it, Enjine::Agents::Random.new(seed: i + it.sum)] }
      decisions = 0
      until game.over?
        monitor.check!(game.submit(agents.fetch(game.pending_decision.player).choose(game.pending_decision)))
        decisions += 1
        raise "game #{i} did not finish" if decisions > 20_000
      end
      expect(game.result["reason"]).to be_a(String)
      expect(monitor.findings).to eq([])
      expect(monitor.stats["spell_cast"]).to be_positive
    end
  end
end
