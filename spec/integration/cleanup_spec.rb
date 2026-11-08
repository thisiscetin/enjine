# frozen_string_literal: true

RSpec.describe "Cleanup step (CR 514)" do
  let(:game) do
    build_game do
      turn 4, active: "alice", step: :end
      player("alice") do
        hand "Forest", count: 8
        hand "Island"
      end
      player("bob") { library "Forest", count: 5 }
    end
  end

  it "makes the active player discard down to seven, one card per decision (CR 514.1)" do
    pass_both(game)
    decision = game.pending_decision
    expect(decision.kind).to eq("discard")
    expect(decision.player).to eq("alice")
    expect(decision.details).to eq("count" => 2)
    expect(decision.options.size).to eq(9)

    island = ids_in(game, "alice", :hand).last
    entry = game.submit(type: "discard", object: island)
    expect(entry.events.first).to have_attributes(card: "island", from: "hand", to: "graveyard", reason: "discard")
    expect(game.pending_decision.details).to eq("count" => 1)
    game.submit(game.legal_options.first)
    expect(game.step).to eq(:upkeep)
    expect(game.turn).to eq(5)
    expect(ids_in(game, "alice", :hand).size).to eq(7)
    expect(game.view_for("bob")["players"][0]["graveyard"].size).to eq(2)
  end

  it "does not ask when the hand is at most seven" do
    g = build_game do
      turn 4, active: "alice", step: :end
      player("alice") { hand "Forest", count: 7 }
      player("bob") { library "Forest", count: 5 }
    end
    pass_both(g)
    expect(g.pending_decision.kind).to eq("priority")
    expect(g.turn).to eq(5)
  end
end
