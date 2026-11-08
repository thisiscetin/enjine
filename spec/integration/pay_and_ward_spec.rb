# frozen_string_literal: true

# Paying while resolving (CR 118.12), "counter unless its controller pays" (CR 701.6a, 118.12a),
# countering abilities (CR 701.6a), "can't be countered" (CR 101.2) and ward (CR 702.21a).
RSpec.describe "Pay while resolving, counter unless pays, ward (CR 118.12, 701.6, 702.21)" do
  let(:directive) do
    { "name" => "Spec Tax Denial", "mana_cost" => "{1}{U}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["spell"],
                                     "effects" => [{ "counter_unless_pays" => { "mana" => "{2}", "to" => { "target" => 0 } } }] } }] }
  end
  let(:toll) do
    { "name" => "Spec Toll Booth", "mana_cost" => "{W}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "pay" => { "mana" => "{1}", "then" => [{ "draw" => { "amount" => 1 } }],
                                                                "otherwise" => [{ "gain_life" => { "amount" => 1 } }] } }] } }] }
  end
  let(:blood_toll) do
    { "name" => "Spec Blood Toll", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "may" => { "effects" => [
        { "pay" => { "life" => 3, "then" => [{ "draw" => { "amount" => 2 } }] } }
      ] } }] } }] }
  end
  let(:stubborn) do
    { "name" => "Spec Stubborn Ox", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "keywords" => ["cant_be_countered"] }
  end
  let(:vulcan) do
    { "name" => "Spec Logic Officer", "mana_cost" => "{U}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => [{ "stack_ability" => { "kind" => "activated" } }],
                                     "effects" => [{ "counter" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:whale) do
    { "name" => "Spec Warded Whale", "mana_cost" => "{3}{U}", "types" => ["creature"], "power" => 3, "toughness" => 3,
      "abilities" => [{ "ward" => { "cost" => "{2}" } }] }
  end
  let(:orphan) do
    { "name" => "Spec Twin Spark", "mana_cost" => "{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "add_mana" => { "color" => "any_one", "colors" => %w[R G] } }] } }] }
  end
  let(:scholar) do
    then_list = [{ "scry" => { "amount" => 1 } }, { "draw" => { "amount" => 1 } }]
    { "name" => "Spec Paid Scholar", "mana_cost" => "{U}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [
        { "may" => { "effects" => [{ "pay" => { "mana" => "{1}", "then" => then_list } }] } },
        { "pay" => { "mana" => "{1}", "if" => { "life" => "you", "at_most" => 5 }, "then" => [{ "draw" => { "amount" => 3 } }] } }
      ] } }] }
  end
  let(:catalog) { catalog_with(directive, toll, blood_toll, stubborn, vulcan, whale, orphan, scholar) }

  it "a payment inside a may, followed by effects that ask; a payment whose condition is false doesn't ask" do
    game = board(alice_hand: ["Spec Paid Scholar"], alice_lands: %w[Island Island])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay_all(game)
    pass_both(game)
    game.submit(type: "yes")
    game.submit(type: "pay")
    pay_all(game)
    expect(game.pending_decision.kind).to eq("effect_choice") # the scry
    game.submit(game.legal_options.first)
    expect(game.pending_decision.kind).to eq("priority")
    expect(ids_in(game, "alice", :hand).size).to eq(1)
  end

  it "cancelling a resolution payment counts as not paying, and rewinds its mana" do
    game = board(alice_hand: ["Spec Toll Booth"], alice_lands: %w[Plains Plains])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay_all(game)
    pass_both(game)
    game.submit(type: "pay")
    plains = game.legal_options.find { it[:type] == "activate_mana" }
    game.submit(plains)
    entry = game.submit(type: "cancel")
    expect(entry.events.map(&:type)).to include("untapped", "payment_finished")
    expect(game.state.players[0].life).to eq(21) # otherwise
    expect(game.state.object(plains[:object]).tapped).to be(false)
  end

  it "ward ignores spells that target something else" do
    game = board(alice_hand: ["Lightning Bolt"], alice_lands: ["Mountain"], bob_field: ["Spec Warded Whale"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: "player:bob")
    pay_all(game)
    expect(game.state.stack.size).to eq(1)
  end

  def pay_all(game)
    while game.pending_decision&.kind == "pay_cost"
      pay = game.legal_options.find { it[:type] == "pay_mana" }
      game.submit(pay || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def board(alice_hand:, alice_lands:, bob_hand: [], bob_lands: [], bob_field: [], life: 20)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", life: life) do
        hand(*alice_hand)
        battlefield(*alice_lands)
        library "Forest", count: 5
      end
      player("bob") do
        hand(*bob_hand) unless bob_hand.empty?
        battlefield(*bob_lands) unless bob_lands.empty?
        battlefield(*bob_field) unless bob_field.empty?
        library "Forest", count: 5
      end
    end
  end

  # Alice casts her first card; Bob gets priority with `response` to cast.
  def respond(game)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay_all(game)
    game.submit(type: "pass")
    game
  end

  it "counters the spell unless its controller pays; they may pay with mana abilities (CR 118.12a, 605.3a)" do
    game = respond(board(alice_hand: ["Grizzly Bears"], alice_lands: %w[Forest Forest Forest Forest],
                         bob_hand: ["Spec Tax Denial"], bob_lands: %w[Island Island]))
    bears = game.state.stack.first
    game.submit(type: "cast", object: ids_in(game, "bob", :hand).first)
    game.submit(type: "target", target: bears)
    pay_all(game)
    pass_both(game)
    expect(game.pending_decision).to have_attributes(kind: "effect_choice", player: "alice")
    expect(game.legal_options).to eq([{ type: "pay" }, { type: "decline" }])
    game.submit(type: "pay")
    expect(game.pending_decision).to have_attributes(kind: "pay_cost", details: { "remaining" => "{2}" })
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(Enjine::Snapshot.validate(copy.state.to_h, catalog)).to eq([])
    pay_all(game)
    expect(game.state.stack).to eq([bears])
    pass_both(game)
    expect(game.state.battlefield.map { game.state.object(it).card }).to include("grizzly_bears")
  end

  it "declining (or cancelling the payment) counters it; without the mana only decline is offered" do
    game = respond(board(alice_hand: ["Grizzly Bears"], alice_lands: %w[Forest Forest Forest Forest],
                         bob_hand: ["Spec Tax Denial"], bob_lands: %w[Island Island]))
    bears = game.state.stack.first
    game.submit(type: "cast", object: ids_in(game, "bob", :hand).first)
    game.submit(type: "target", target: bears)
    pay_all(game)
    pass_both(game)
    game.submit(type: "pay")
    forest = game.legal_options.find { it[:type] == "activate_mana" }
    game.submit(forest)
    game.submit(type: "cancel")
    expect(game.state.object(forest[:object]).tapped).to be(false)
    expect(game.state.stack).to be_empty
    expect(game.state.players[0].graveyard.size).to eq(1)

    broke = respond(board(alice_hand: ["Grizzly Bears"], alice_lands: %w[Forest Forest],
                          bob_hand: ["Spec Tax Denial"], bob_lands: %w[Island Island]))
    target = broke.state.stack.first
    broke.submit(type: "cast", object: ids_in(broke, "bob", :hand).first)
    broke.submit(type: "target", target: target)
    pay_all(broke)
    pass_both(broke)
    expect(broke.legal_options).to eq([{ type: "decline" }])
    broke.submit(type: "decline")
    expect(broke.state.stack).to be_empty
  end

  it "a spell that can't be countered stays on the stack (CR 101.2)" do
    game = respond(board(alice_hand: ["Spec Stubborn Ox"], alice_lands: %w[Forest Forest],
                         bob_hand: ["Counterspell"], bob_lands: %w[Island Island]))
    ox = game.state.stack.first
    game.submit(type: "cast", object: ids_in(game, "bob", :hand).first)
    game.submit(type: "target", target: ox)
    pay_all(game)
    pass_both(game)
    expect(game.state.stack).to eq([ox])
  end

  it "pay {1}: if you do, then; if you don't, otherwise" do
    game = board(alice_hand: ["Spec Toll Booth", "Spec Toll Booth"], alice_lands: %w[Plains Plains Plains])
    respond_and_resolve = lambda do |answer|
      toll = ids_in(game, "alice", :hand).find { game.state.object(it).card == "spec_toll_booth" }
      game.submit(type: "cast", object: toll)
      pay_all(game)
      pass_both(game)
      game.submit(type: answer)
      pay_all(game)
    end
    respond_and_resolve.call("pay")
    expect(ids_in(game, "alice", :hand).size).to eq(2)
    respond_and_resolve.call("decline")
    expect(game.state.players[0].life).to eq(21)
  end

  it "pays life inside a may, only with enough life (CR 119.4)" do
    game = board(alice_hand: ["Spec Blood Toll"], alice_lands: ["Swamp"], life: 5)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay_all(game)
    pass_both(game)
    game.submit(type: "yes")
    game.submit(type: "pay")
    expect(game.state.players[0].life).to eq(2)
    expect(ids_in(game, "alice", :hand).size).to eq(2)

    poor = board(alice_hand: ["Spec Blood Toll"], alice_lands: ["Swamp"], life: 2)
    poor.submit(type: "cast", object: ids_in(poor, "alice", :hand).first)
    pay_all(poor)
    pass_both(poor)
    poor.submit(type: "yes")
    expect(poor.legal_options).to eq([{ type: "decline" }])
  end

  it "counters an activated ability on the stack (CR 701.6a)" do
    game = board(alice_hand: [], alice_lands: %w[Mountain Mountain Mountain], bob_hand: ["Spec Logic Officer"], bob_lands: ["Island"])
    game = Enjine::Game.import({ "state" => game.state.to_h.merge(
      "players" => game.state.to_h["players"]
    ) }, catalog: catalog)
    engine = game.instance_variable_get(:@engine)
    pyro = engine.create_object("prodigal_pyromancer", 0, :battlefield)
    engine.state.battlefield << pyro.id
    pyro.controlled_since = 0
    game = Enjine::Game.import({ "state" => engine.state.to_h }, catalog: catalog)
    game.submit(type: "activate", object: pyro.id, ability: "printed:0")
    game.submit(type: "target", target: "player:bob")
    game.submit(type: "pass")
    ability = game.state.stack.first
    game.submit(type: "cast", object: ids_in(game, "bob", :hand).first)
    expect(game.legal_options).to include({ type: "target", target: ability })
    game.submit(type: "target", target: ability)
    pay_all(game)
    entry = nil
    2.times { entry = game.submit(type: "pass") }
    expect(entry.events.map(&:type)).to include("ability_countered")
    expect(game.state.stack).to be_empty
    expect(game.state.players[1].life).to eq(20)
  end

  it "ward: an opponent's spell targeting it is countered unless they pay (CR 702.21a)" do
    game = board(alice_hand: ["Lightning Bolt", "Lightning Bolt"], alice_lands: %w[Mountain Mountain Mountain],
                 bob_field: ["Spec Warded Whale"])
    whale = obj_id(game, "Spec Warded Whale")
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: whale)
    pay_all(game)
    expect(game.state.stack.size).to eq(2) # the ward trigger is on top
    ward = game.state.object(game.state.stack.first)
    expect(ward.memory["targeted_by"]).to eq(game.state.stack.last)
    pass_both(game)
    expect(game.pending_decision.player).to eq("alice")
    game.submit(type: "pay")
    pay_all(game)
    pass_both(game)
    expect(game.state.players[1].graveyard.size).to eq(1) # the Whale took 3
  end

  it "ward doesn't trigger for its controller's own spells, and declining counters the spell" do
    own = board(alice_hand: ["Giant Growth"], alice_lands: ["Forest"])
    engine = own.instance_variable_get(:@engine)
    whale = engine.create_object("spec_warded_whale", 0, :battlefield)
    engine.state.battlefield << whale.id
    own = Enjine::Game.import({ "state" => engine.state.to_h }, catalog: catalog)
    own.submit(type: "cast", object: ids_in(own, "alice", :hand).first)
    own.submit(type: "target", target: whale.id)
    pay_all(own)
    expect(own.state.stack.size).to eq(1)

    game = board(alice_hand: ["Lightning Bolt"], alice_lands: ["Mountain"], bob_field: ["Spec Warded Whale"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: obj_id(game, "Spec Warded Whale"))
    pay_all(game)
    pass_both(game)
    expect(game.legal_options).to eq([{ type: "decline" }])
    game.submit(type: "decline")
    expect(game.state.stack).to be_empty
    expect(game.state.players[0].graveyard.size).to eq(1)
  end

  it "a ward trigger from a cancelled cast is dropped (CR 733.1)" do
    game = board(alice_hand: ["Lightning Bolt"], alice_lands: ["Mountain"], bob_field: ["Spec Warded Whale"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: obj_id(game, "Spec Warded Whale"))
    expect(game.state.pending_triggers.size).to eq(1)
    game.submit(type: "cancel")
    expect(game.state.pending_triggers).to be_empty
    expect(game.state.stack).to be_empty
  end

  it "adds one mana of a listed color" do
    game = board(alice_hand: ["Spec Twin Spark"], alice_lands: ["Mountain"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay_all(game)
    pass_both(game)
    expect(game.legal_options).to eq([{ type: "color", color: "R" }, { type: "color", color: "G" }])
    game.submit(type: "color", color: "G")
    expect(game.state.players[0].mana_pool[:G]).to eq(1)
  end
end
