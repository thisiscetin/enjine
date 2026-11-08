# frozen_string_literal: true

RSpec.describe "Regressions found by the design reviews" do
  it "E1: apply with an illegal option on a freshly imported game raises IllegalDecision and rolls back" do
    game = basics_setup.new_game(seed: 1)
    copy = Enjine::Game.import(game.export, catalog: game.catalog)
    before = copy.export
    expect { copy.apply([{ type: "nonsense" }]) }.to raise_error(Enjine::IllegalDecision, /decision #0/)
    expect(copy.export).to eq(before)
  end

  it "E2: the opponent can read history after a concession" do
    game = basics_setup.new_game(seed: 1)
    game.concede("alice")
    expect(game.history_for("bob").last).to include("kind" => "concede", "option" => { "type" => "concede" })
    expect(game.history_for("alice").last["player"]).to eq("alice")
  end

  it "E13: engine errors while checking an imported position propagate instead of looking like bad input" do
    game = basics_setup.new_game(seed: 1)
    allow(Enjine::Decisions::PlayOrDraw).to receive(:options).and_raise(NoMethodError, "engine bug")
    expect { Enjine::Game.import(game.export, catalog: game.catalog) }.to raise_error(NoMethodError, "engine bug")
  end
end

RSpec.describe "State#fork and Game#fork (P3)" do
  it "copies everything: the fork serializes identically and diverges independently" do
    setup = basics_setup
    game = setup.new_game(seed: 9)
    agent = Enjine::Agents::Random.new(seed: 9)
    300.times { game.submit(agent.choose(game.pending_decision)) unless game.over? }
    copy = game.fork
    expect(copy.state.to_h).to eq(game.state.to_h)
    expect(copy.pending_decision).to eq(game.pending_decision)
    copy.submit(copy.legal_options.first)
    expect(copy.state.to_h).not_to eq(game.state.to_h)
    expect(game.history.size).to eq(copy.history.size - 1)
  end

  it "deep-copies mid-cast context, combat and effects" do
    game = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Grizzly Bears"
        battlefield "Forest", "Forest"
      end
      player("bob")
    end
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    copy = game.state.fork
    copy.casting["remaining"]["generic"] = 99
    copy.players[0].mana_pool[:G] = 5
    copy.objects.each_value { it.tapped = true }
    expect(game.state.casting["remaining"]["generic"]).to eq(1)
    expect(game.state.players[0].mana_pool[:G]).to eq(0)
    expect(game.state.objects.values.none?(&:tapped)).to be(true)
  end
end
