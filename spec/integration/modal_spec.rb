# frozen_string_literal: true

RSpec.describe "Modal spells and abilities (CR 700.2, 601.2b, 603.3c)" do
  let(:charm) do
    { "name" => "Ember Charm", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "modes" => [
        { "targets" => ["creature"], "effects" => [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }] },
        { "effects" => [{ "draw" => { "amount" => 1 } }] },
        { "effects" => [{ "lose_life" => { "amount" => 2, "to" => "each_opponent" } }] }
      ] } }] }
  end
  let(:double) do
    { "name" => "Twin Edict", "mana_cost" => "{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "choose" => 2, "modes" => [
        { "effects" => [{ "gain_life" => { "amount" => 3 } }] },
        { "targets" => ["player"], "effects" => [{ "deal_damage" => { "amount" => 1, "to" => { "target" => 0 } } }] },
        { "effects" => [{ "draw" => { "amount" => 1 } }] }
      ] } }] }
  end
  let(:herald) do
    { "name" => "Choice Herald", "mana_cost" => "{R}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} }, "modes" => [
        { "effects" => [{ "gain_life" => { "amount" => 2 } }] },
        { "targets" => ["creature"], "effects" => [{ "pump" => { "power" => 2, "toughness" => 0, "to" => { "target" => 0 } } }] }
      ] } }] }
  end
  let(:catalog) { catalog_with(charm, double, herald) }

  def game_with(hand, bob_board: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand.each { hand it }
        battlefield "Mountain", count: 2
        library "Forest", count: 5
      end
      player("bob") do
        bob_board.each { battlefield it }
        library "Forest", count: 5
      end
    end
  end

  def pay(game)
    land = game.state.battlefield.find { game.state.object(it).card == "mountain" && !game.state.object(it).tapped }
    game.submit(type: "activate_mana", object: land, ability: "intrinsic:mountain")
    game.submit(type: "pay_mana", mana: "R")
  end

  def life(game, who) = game.view_for(:observer)["players"].find { it["name"] == who }["life"]

  it "asks for the mode first, then only that mode's targets; modes without legal targets aren't offered" do
    game = game_with(["Ember Charm"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    expect(game.pending_decision).to have_attributes(kind: "choose_mode", details: { "choose" => 1, "chosen" => 0 })
    expect(game.legal_options).to eq([{ type: "mode", mode: 1 }, { type: "mode", mode: 2 }, { type: "cancel" }]) # no creature: mode 0 out
    game.submit(type: "mode", mode: 2)
    expect(game.pending_decision.kind).to eq("pay_cost") # mode 2 has no targets
    pay(game)
    pass_both(game)
    expect(life(game, "bob")).to eq(18)
  end

  it "a targeted mode resolves against its own target" do
    game = game_with(["Ember Charm"], bob_board: ["Grizzly Bears"])
    bears = obj_id(game, "Grizzly Bears")
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "mode", mode: 0)
    expect(game.legal_options.map { it[:target] }.compact).to eq([bears])
    game.submit(type: "target", target: bears)
    pay(game)
    pass_both(game)
    expect(game.state.battlefield).not_to include(bears)
  end

  it "choose two: distinct modes, effects in printed order with per-mode targets" do
    game = game_with(["Twin Edict"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "mode", mode: 2)
    expect(game.legal_options).not_to include(type: "mode", mode: 2)
    game.submit(type: "mode", mode: 1)
    game.submit(type: "target", target: "player:bob")
    pay(game)
    hand = ids_in(game, "alice", :hand).size
    pass_both(game)
    expect(life(game, "bob")).to eq(19)
    expect(ids_in(game, "alice", :hand).size).to eq(hand + 1)
    expect(game.state.players[0].graveyard.size).to eq(1)
  end

  it "cancel at the mode choice rewinds the cast" do
    game = game_with(["Ember Charm"])
    hand = ids_in(game, "alice", :hand).dup
    game.submit(type: "cast", object: hand.first)
    game.submit(type: "cancel")
    expect(ids_in(game, "alice", :hand)).to eq(hand)
  end

  it "a modal triggered ability chooses its mode when put on the stack, without cancel" do
    game = game_with(["Choice Herald"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay(game)
    pass_both(game) # Herald enters; its trigger asks for a mode
    expect(game.pending_decision.kind).to eq("choose_mode")
    expect(game.legal_options).to eq([{ type: "mode", mode: 0 }, { type: "mode", mode: 1 }])
    game.submit(type: "mode", mode: 1)
    herald = obj_id(game, "Choice Herald")
    game.submit(type: "target", target: herald)
    pass_both(game)
    expect(view_of(game, herald)["power"]).to eq(3)
  end

  it "validates modal data" do
    expect { Enjine::CardDefinition.from_h(charm.merge("abilities" => [{ "spell" => { "modes" => [{ "effects" => [] }] } }])) }
      .to raise_error(Enjine::InvalidCardDefinition, /at least two modes/)
    bad = { "spell" => { "choose" => 5, "targets" => [], "modes" => [{ "effects" => [] }, { "effects" => [] }] } }
    expect { Enjine::CardDefinition.from_h(charm.merge("abilities" => [bad])) }
      .to raise_error(Enjine::InvalidCardDefinition, /not both.*|can't exceed/m)
    expect(Enjine::CardDefinition.from_h(double).spell_ability.to_s).to start_with("choose 2 — ")
  end
end
