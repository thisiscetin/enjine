# frozen_string_literal: true

RSpec.describe "Views and history per viewer" do
  let(:game) do
    build_game do
      turn 3, active: "alice", step: :upkeep
      player("alice") do
        hand "Forest", "Island"
        library "Mountain", "Swamp"
        battlefield "Plains", tapped: true
      end
      player("bob") do
        hand "Swamp", count: 6
        library "Forest", count: 3
        graveyard "Island"
      end
    end
  end

  it "shows a player their own hand but only counts for the opponent's hand and all libraries" do
    view = game.view_for("alice")
    me, opp = view["players"]
    expect(me["hand"].map { it["name"] }).to eq(%w[Forest Island])
    expect(me).not_to have_key("library")
    expect(me["library_count"]).to eq(2)
    expect(opp).not_to have_key("hand")
    expect(opp["hand_count"]).to eq(6)
    expect(opp["graveyard"].map { it["name"] }).to eq(["Island"])
    expect(view["battlefield"].first).to include("name" => "Plains", "tapped" => true, "controller" => "alice",
                                                 "type_line" => "Basic Land — Plains")
  end

  it "shows the observer everything, including library order" do
    view = game.view_for(:observer)
    expect(view["viewer"]).to eq("observer")
    expect(view["players"][0]["library"].map { it["name"] }).to eq(%w[Mountain Swamp])
    expect(view["players"][1]["hand"].size).to eq(6)
    expect(game.view_for("observer")).to eq(view)
  end

  it "shows pending options only to the deciding player and the observer" do
    expect(game.view_for("alice")["pending"]).to eq("kind" => "priority", "player" => "alice",
                                                    "options" => [{ "type" => "pass" }])
    expect(game.view_for("bob")["pending"]).to eq("kind" => "priority", "player" => "alice")
    expect(game.view_for(:observer)["pending"]).to have_key("options")
  end

  it "redacts what an opponent drew in that opponent's history" do
    pass_both(game, 8) # alice's turn ends; bob draws in his draw step
    pass_both(game)
    draws = ->(viewer) { game.history_for(viewer).flat_map { it["events"] }.select { it["reason"] == "draw" } }
    expect(draws.call("bob").last).to include("card" => "forest")
    expect(draws.call("alice").last).to eq("type" => "zone_changed", "owner" => "bob", "from" => "library",
                                           "to" => "hand", "reason" => "draw")
    expect(draws.call(:observer).last).to include("card" => "forest")
  end

  it "serializes the pending decision for callers" do
    expect(game.pending_decision.to_h).to eq("player" => "alice", "kind" => "priority",
                                             "options" => [{ "type" => "pass" }])
  end
end
