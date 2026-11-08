# frozen_string_literal: true

# Station and station cards: CR 702.184 and 722 (2026-11-06 rules; also in the pinned 2026-09-25 text).
RSpec.describe "Station (CR 702.184, 722)" do
  let(:outpost) do
    { "name" => "Relay Outpost", "mana_cost" => "{3}", "types" => ["artifact"], "subtypes" => ["spacecraft"],
      "keywords" => ["station"],
      "abilities" => [
        { "station_symbol" => { "at" => 2, "abilities" => [
          { "static" => { "affects" => { "each" => "creature", "controller" => "you" }, "pump" => { "power" => 1, "toughness" => 0 } } }
        ] } },
        { "station_symbol" => { "at" => 4, "power" => 5, "toughness" => 5, "abilities" => [
          { "triggered" => { "when" => { "attacks" => {} }, "effects" => [{ "gain_life" => { "amount" => 2 } }] } }
        ] } }
      ] }
  end
  let(:rig) do
    { "name" => "Tapping Rig", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{1}" }, "tap_another_creature"],
                                         "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
  end
  let(:catalog) { catalog_with(outpost, rig) }

  def skiff(game) = obj_id(game, "Longreach Skiff")
  def station_option(_game, id) = { type: "activate", object: id, ability: "keyword:station" }
  def life(game, name) = game.view_for(:observer)["players"].find { it["name"] == name }["life"]

  def board(step: :precombat_main, alice: [], bob_hand: [], bob_board: [])
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice") do
        alice.each { |card, opts| battlefield card, **(opts || {}) }
        library "Forest", count: 5
      end
      player("bob") do
        bob_hand.each { hand it }
        bob_board.each { battlefield it }
        library "Forest", count: 5
      end
    end
  end

  it "taps another untapped creature, even a summoning-sick one, at sorcery speed (CR 702.184a, 302.6)" do
    game = board(alice: [["Longreach Skiff"], ["Hill Giant", { controlled_since: 3 }], ["Grizzly Bears", { tapped: true }]])
    giant = obj_id(game, "Hill Giant")
    expect(game.legal_options).to include(station_option(game, skiff(game)))
    game.submit(station_option(game, skiff(game)))
    expect(game.pending_decision).to have_attributes(kind: "choose_cost",
                                                     details: { "cost" => "Tap another untapped creature you control" })
    expect(game.legal_options).to eq([{ type: "cost", object: giant }, { type: "cancel" }]) # not itself, not a tapped one
    game.submit(type: "cost", object: giant)
    expect(game.state.object(giant).tapped).to be(true)
    expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Longreach Skiff ability"])
    pass_both(game)
    expect(game.state.object(skiff(game)).counters["charge"]).to eq(3)
  end

  it "cancelling after the creature was tapped for the cost untaps it again (CR 733.1)" do
    game = board(alice: [["Tapping Rig"], ["Hill Giant"], ["Forest"]])
    giant = obj_id(game, "Hill Giant")
    rig = { type: "activate", object: obj_id(game, "Tapping Rig"), ability: "printed:0" }
    game.submit(rig)
    game.submit(type: "cost", object: giant) # paid at once (CR 601.2h) ...
    expect(game.state.object(giant).tapped).to be(true)
    expect(game.pending_decision.kind).to eq("pay_cost") # ... the mana is still owed
    game.submit(type: "cancel")
    expect(game.state.object(giant).tapped).to be(false)
    expect(game.state.stack).to be_empty
    game.submit(rig)
    game.submit(type: "cancel") # cancelling before choosing changes nothing either
    expect(game.state.object(giant).tapped).to be(false)
  end

  it "isn't offered without another untapped creature, or at instant speed" do
    game = board(alice: [["Longreach Skiff"]])
    expect(game.legal_options).not_to include(station_option(game, skiff(game)))
    combat = board(step: :beginning_of_combat, alice: [["Longreach Skiff"], ["Hill Giant"]])
    expect(combat.legal_options).not_to include(station_option(combat, skiff(combat)))
  end

  it "at N+ charge counters it's a creature with the box's base power/toughness and abilities (CR 722.2b)" do
    game = board(alice: [["Longreach Skiff", { counters: { "charge" => 2 } }], ["Grizzly Bears"]])
    engine = game.instance_variable_get(:@engine)
    expect(engine.chars(skiff(game)).creature?).to be(false)
    expect(view_of(game, skiff(game))).not_to have_key("power") # CR 722.2c-style: no P/T while not a creature
    game.submit(station_option(game, skiff(game)))
    game.submit(type: "cost", object: obj_id(game, "Grizzly Bears"))
    pass_both(game)
    expect(engine.chars(skiff(game))).to have_attributes(types: %i[artifact creature], power: 3, toughness: 3)
    expect(engine.chars(skiff(game)).keyword?(:flying)).to be(true)
    expect(view_of(game, skiff(game))).to include("power" => 3, "toughness" => 3, "counters" => { "charge" => 4 })
  end

  it "counts the creature's power when it was tapped if it's gone before resolution" do
    game = board(alice: [["Longreach Skiff"], ["Hill Giant"]], bob_hand: ["Lightning Bolt"], bob_board: ["Mountain"])
    giant = obj_id(game, "Hill Giant")
    game.submit(station_option(game, skiff(game)))
    game.submit(type: "cost", object: giant)
    game.submit(type: "pass") # bob gets priority and kills the giant in response
    game.submit(type: "cast", object: ids_in(game, "bob", :hand).first)
    game.submit(type: "target", target: giant)
    game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
    game.submit(type: "pay_mana", mana: "R")
    pass_both(game, 2)
    expect(game.state.battlefield).not_to include(giant)
    expect(game.state.object(skiff(game)).counters["charge"]).to eq(3)
  end

  it "station symbols grant static and triggered abilities only while they apply (CR 722.2a)" do
    game = board(alice: [["Relay Outpost", { counters: { "charge" => 4 } }], ["Grizzly Bears"]])
    engine = game.instance_variable_get(:@engine)
    outpost = obj_id(game, "Relay Outpost")
    expect(engine.power(engine.object(obj_id(game, "Grizzly Bears")))).to eq(3) # 2+ symbol's static
    expect(engine.power(engine.object(outpost))).to eq(6) # 5/5 base, then +1/+0 (layer 7b before 7c)
    low = board(alice: [["Relay Outpost", { counters: { "charge" => 1 } }], ["Grizzly Bears"]])
    low_engine = low.instance_variable_get(:@engine)
    expect(low_engine.power(low_engine.object(obj_id(low, "Grizzly Bears")))).to eq(2)
  end

  it "a granted triggered ability triggers and resolves from the stack (CR 722.2a, 603.2)" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :beginning_of_combat
      player("alice") do
        battlefield "Relay Outpost", counters: { "charge" => 4 }
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    outpost = obj_id(game, "Relay Outpost")
    pass_both(game)
    expect(game.pending_decision.kind).to eq("declare_attackers")
    game.submit(game.legal_options.find { it[:type] == "attack" && it[:object] == outpost })
    game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
    expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Relay Outpost ability"])
    copy = Enjine::Game.import(game.export, catalog: catalog)
    pass_both(copy)
    expect(life(copy, "alice")).to eq(22)
  end
end
