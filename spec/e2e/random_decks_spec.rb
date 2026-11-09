# frozen_string_literal: true

RSpec.describe "Full games between random pool decks" do
  def setup_for(seed, pools1, pools2)
    alice = Enjine::Player.new(name: "alice", deck: build_deck(pools1, colors: :any, seed: seed))
    bob = Enjine::Player.new(name: "bob", deck: build_deck(pools2, colors: :any, seed: seed + 1))
    Enjine::Setup.new(alice, bob)
  end

  it "plays random agents to the end with decks from each pool and from both" do
    [[%w[fxa], %w[fxb]], [%w[fxa fxb], %w[fxa]], [%w[fxb], %w[fxa fxb]]].each_with_index do |(one, two), i|
      game = setup_for(10 + i, one, two).new_game(seed: i)
      agents = game.names.to_h { [it, Enjine::Agents::Random.new(seed: i + it.sum)] }
      decisions = 0
      until game.over?
        game.submit(agents.fetch(game.pending_decision.player).choose(game.pending_decision))
        decisions += 1
        raise "game #{i} did not finish" if decisions > 20_000
      end
      expect(game.result["reason"]).to be_a(String)
    end
  end

  it "survives the fuzzer: invariants after every decision, export/import roundtrips" do
    result = Enjine::Fuzz.run(setup_for(3, %w[fxa fxb], %w[fxa fxb]), games: 3, seed: 40, roundtrip_every: 113)
    expect(result.outcomes.values.sum).to eq(3)
    expect(result.casts).not_to be_empty
  end
end
