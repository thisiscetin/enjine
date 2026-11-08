# frozen_string_literal: true

RSpec.describe "Atomic submit and transactional apply" do
  let(:game) do
    build_game do
      turn 2, active: "alice", step: :precombat_main
      player("alice") do
        hand "Forest"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
  end

  it "rejects illegal options without changing anything and lists the legal ones" do
    before = game.export
    expect { game.submit(type: "play_land", object: "island#99") }
      .to raise_error(Enjine::IllegalDecision) { |e| expect(e.legal_options).to eq(game.legal_options) }
    expect { game.submit("pass") }.to raise_error(Enjine::IllegalDecision, /must be a Hash/)
    expect(game.export).to eq(before)
  end

  it "accepts string keys and symbol values, as from JSON" do
    game.submit("type" => :pass)
    expect(game.pending_decision.player).to eq("bob")
  end

  it "applies a list of decisions in order" do
    forest = ids_in(game, "alice", :hand).first
    game.apply([{ "type" => "play_land", "object" => forest }, { "type" => "pass" }, { "type" => "pass" }])
    expect(game.step).to eq(:beginning_of_combat)
    expect(game.state.battlefield.size).to eq(1)
  end

  it "rolls everything back when any decision is illegal, reporting its index" do
    before = game.export
    events = []
    game.subscribe { events << it }
    expect { game.apply([{ type: "pass" }, { type: "pass" }, { type: "play_land", object: "forest#1" }]) }
      .to raise_error(Enjine::IllegalDecision, /decision #2/) { |e| expect(e.index).to eq(2) }
    expect(game.export).to eq(before)
    expect(events).to be_empty
    expect(game.pending_decision.options).to include(a_hash_including(type: "play_land"))
  end

  it "delivers events to subscribers after a successful apply" do
    events = []
    game.subscribe { events << it.type }
    game.apply([{ type: "pass" }])
    expect(events).to eq(["priority_passed"])
  end
end
