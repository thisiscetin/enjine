# frozen_string_literal: true

RSpec.describe "Full games from Setup" do
  let(:pool) { Enjine::CardPool::Core.cards }

  def random_setup(seed)
    rng = Enjine::Rng.from_seed(seed)
    players = %w[alice bob].map { Enjine::Player.new(name: it, deck: Enjine::CardPool::DeckBuilder.random(pool, rng: rng)) }
    Enjine::Setup.new(*players)
  end

  it "plays a scripted game where both players only pass, until the second player decks out" do
    game = basics_setup.new_game(seed: 1)
    game.submit(type: "play")
    game.submit(type: "keep")
    game.submit(type: "keep")
    until game.over?
      option = game.legal_options.find { it[:type] == "pass" } || game.legal_options.first
      game.submit(option)
    end
    starter = game.state.starting_player
    # The non-starting player draws first on turn 2 and runs out one turn earlier.
    expect(game.result).to eq("winner" => game.names[starter], "reason" => "empty_library")
    expect(game.turn).to eq(108)
  end

  it "fuzzes random games with invariants checked after every decision and export/import roundtrips" do
    result = Enjine::Fuzz.run(random_setup(1), games: 3, seed: 100, roundtrip_every: 97)
    expect(result.games).to eq(3)
    expect(result.outcomes.values.sum).to eq(3)
    expect(result.decisions).to be > 1_500
  end

  it "replays every fuzzed game identically from seed + decision log" do
    setup = random_setup(2)
    agent = Enjine::Agents::Random.new(seed: 7)
    game = setup.new_game(seed: 7)
    game.submit(agent.choose(game.pending_decision)) until game.over?
    replay = setup.new_game(seed: 7).apply(game.decision_log)
    expect(replay.state.to_h).to eq(game.state.to_h)
    expect(replay.history_for(:observer)).to eq(game.history_for(:observer))
  end

  it "reports a fuzz failure with the seed when a game runs too long" do
    expect { Enjine::Fuzz.run(random_setup(3), games: 1, seed: 5, max_decisions: 10) }
      .to raise_error(Enjine::Fuzz::Failure, /seed 5/) { |e| expect(e.seed).to eq(5) }
  end

  it "wraps engine errors raised mid-game as fuzz failures" do
    allow(Enjine::Actions::Pass).to receive(:perform).and_raise(RuntimeError, "boom")
    expect { Enjine::Fuzz.run(basics_setup, games: 1, seed: 1) }.to raise_error(Enjine::Fuzz::Failure, /boom/)
  end

  it "flags broken invariants" do
    allow(Enjine::Snapshot).to receive(:validate).and_return(["bad"])
    expect { Enjine::Fuzz.run(basics_setup, games: 1, seed: 1) }.to raise_error(Enjine::Fuzz::Failure, /invariant broken/)
  end

  it "flags export/import mismatches" do
    allow(Enjine::Game).to receive(:import).and_wrap_original do |original, *args, **kw|
      original.call(*args, **kw).tap { it.state.players[0].life = 1 }
    end
    expect { Enjine::Fuzz.run(basics_setup, games: 1, seed: 1, roundtrip_every: 5) }
      .to raise_error(Enjine::Fuzz::Failure, /roundtrip/)
  end
end
