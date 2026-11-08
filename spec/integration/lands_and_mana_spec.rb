# frozen_string_literal: true

RSpec.describe "Playing lands and mana abilities (CR 305, 605, 106)" do
  let(:game) do
    build_game do
      turn 2, active: "alice", step: :precombat_main
      player("alice") do
        hand "Forest", "Island"
        battlefield "Mountain"
        library "Forest", count: 5
      end
      player("bob") do
        hand "Swamp", count: 6
        battlefield "Plains"
        library "Forest", count: 5
      end
    end
  end

  let(:forest_in_hand) { ids_in(game, "alice", :hand).first }
  let(:mountain) { game.state.battlefield.first }
  let(:plains) { game.state.battlefield.last }

  it "offers each land in hand plus mana abilities of untapped permanents you control" do
    expect(game.legal_options).to eq([
                                       { type: "pass" },
                                       { type: "play_land", object: ids_in(game, "alice", :hand)[0] },
                                       { type: "play_land", object: ids_in(game, "alice", :hand)[1] },
                                       { type: "activate_mana", object: mountain, ability: mana_ref(game, mountain) }
                                     ])
  end

  it "puts the land onto the battlefield untapped as a new object (CR 305.1, 400.7)" do
    entry = game.submit(type: "play_land", object: forest_in_hand)
    moved = entry.events.grep(Enjine::Events::ZoneChanged).first
    expect(moved).to have_attributes(card: "forest", old_id: forest_in_hand, from: "hand", to: "battlefield",
                                     reason: "play_land")
    expect(moved.new_id).not_to eq(forest_in_hand)
    expect(game.state.battlefield).to include(moved.new_id)
    expect(game.state.object(moved.new_id).tapped).to be(false)
    expect(game.pending_decision.player).to eq("alice") # CR 117.3c
  end

  it "allows only one land per turn (CR 305.2)" do
    game.submit(type: "play_land", object: forest_in_hand)
    expect(option_types(game)).not_to include("play_land")
    expect(game.view_for("alice")["players"][0]["lands_played"]).to eq(1)
  end

  it "does not allow playing lands outside your main phase or on the opponent's turn (CR 305.1)" do
    pass_both(game) # -> beginning of combat
    expect(option_types(game)).not_to include("play_land")
    game.submit(type: "pass")
    expect(game.pending_decision.player).to eq("bob")
    expect(option_types(game)).to eq(%w[pass activate_mana])
  end

  it "adds mana immediately and taps the source; a tapped source has no mana option (CR 605.3)" do
    entry = game.submit(type: "activate_mana", object: mountain, ability: mana_ref(game, mountain))
    expect(entry.events.map(&:type)).to eq(%w[tapped mana_added])
    expect(game.view_for("alice")["players"][0]["mana_pool"]).to eq("R" => 1)
    expect(game.legal_options).not_to include(a_hash_including(type: "activate_mana"))
  end

  it "lets the non-active player tap mana while holding priority" do
    game.submit(type: "pass")
    game.submit(type: "activate_mana", object: plains, ability: mana_ref(game, plains))
    expect(game.view_for("bob")["players"][1]["mana_pool"]).to eq("W" => 1)
  end

  it "empties mana pools at the end of each step (CR 500.4)" do
    game.submit(type: "activate_mana", object: mountain, ability: mana_ref(game, mountain))
    entry = nil
    2.times { entry = game.submit(type: "pass") }
    expect(entry.events.grep(Enjine::Events::ManaEmptied).map(&:to_h)).to eq(
      [{ "type" => "mana_emptied", "player" => "alice", "mana" => "{R}" }]
    )
    expect(game.state.players[0].mana_pool.values.sum).to eq(0)
  end

  it "untaps only the active player's permanents in the untap step (CR 502.3)" do
    game.submit(type: "activate_mana", object: mountain, ability: mana_ref(game, mountain))
    game.submit(type: "pass")
    game.submit(type: "activate_mana", object: plains, ability: mana_ref(game, plains))
    pass_both(game, 7) # through alice's turn into bob's upkeep
    expect(game.view_for(:observer)["active"]).to eq("bob")
    expect(game.state.object(plains).tapped).to be(false)
    expect(game.state.object(mountain).tapped).to be(true)
  end

  it "uses explicit mana abilities from card data (Wastes)" do
    g = build_game do
      turn 1, active: "alice", step: :precombat_main
      player("alice") { battlefield "Wastes" }
      player("bob")
    end
    g.submit(type: "activate_mana", object: g.state.battlefield.first, ability: mana_ref(g, g.state.battlefield.first))
    expect(g.state.players[0].mana_pool[:C]).to eq(1)
  end
end
