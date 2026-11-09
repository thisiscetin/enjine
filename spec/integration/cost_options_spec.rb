# frozen_string_literal: true

# Choosing between costs (cost `one_of`, CR 601.2b, 601.2f, 118.3): announced while casting or activating.
RSpec.describe "Choosing between costs (CR 601.2b, 601.2f, 118.3)" do
  def goblin_or_two = { "one_of" => [{ "behold" => { "card" => { "subtypes" => ["goblin"] } } }, { "mana" => "{2}" }] }

  let(:cursetosser) do
    { "name" => "Spec Cursetosser", "mana_cost" => "{B}", "types" => ["creature"], "subtypes" => ["goblin"],
      "power" => 2, "toughness" => 1, "abilities" => [{ "additional_cost" => { "cost" => [goblin_or_two] } }] }
  end
  let(:goblin) do
    { "name" => "Spec Hand Goblin", "mana_cost" => "{3}{B}", "types" => ["creature"], "subtypes" => ["goblin"],
      "power" => 1, "toughness" => 1 }
  end
  let(:dealer) do
    { "name" => "Spec Dart Dealer", "mana_cost" => "{2}{B}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "abilities" => [{ "activated" => {
        "cost" => [{ "mana" => "{1}" }, "tap", { "one_of" => [{ "sacrifice_permanent" => { "filter" => "artifact" } },
                                                              { "discard" => { "card" => { "not_types" => ["land"] } } }] }],
        "targets" => ["any_target"], "effects" => [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }]
      } }] }
  end
  def warded(name, cost) = { "name" => name, "mana_cost" => "{1}{B}", "types" => ["creature"], "power" => 3, "toughness" => 3,
                              "abilities" => [{ "ward" => { "cost" => cost } }] }

  let(:courier) do
    { "name" => "Spec Scrap Courier", "mana_cost" => "{1}{R}", "types" => ["creature"], "power" => 2, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} }, "effects" => [{ "pay" => {
        "cost" => [{ "one_of" => [{ "sacrifice_permanent" => { "filter" => "artifact" } }, "discard"] }],
        "then" => [{ "draw" => { "amount" => 1 } }]
      } }] } }] }
  end
  let(:catalog) do
    catalog_with(cursetosser, goblin, dealer, courier, { "name" => "Spec Bauble", "mana_cost" => "{0}", "types" => ["artifact"] },
                 warded("Spec Life Warden", [{ "pay_life" => 2 }]),
                 warded("Spec Toll Titan", [{ "one_of" => [{ "discard" => {} }, { "mana" => "{2}" }] }]),
                 warded("Spec Venom Society", [{ "get_counters" => { "counter" => "poison", "amount" => 5 } }]))
  end

  def board(hand: [], field: [], lands: [], theirs: [], life: 20)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", life: life) do
        hand(*hand)
        battlefield(*field)
        lands.each { battlefield it }
        library "Swamp", count: 5
      end
      player("bob") do
        theirs.each { battlefield it }
        library "Swamp", count: 5
      end
    end
  end

  # Alice casts Lightning Bolt at bob's warded creature; the ward trigger resolves and asks alice.
  def bolt_at(game, name)
    cast(game, "Lightning Bolt")
    game.submit(type: "target", target: obj_id(game, name))
    pay_all(game)
    pass_both(game)
  end

  def cast(game, name) = game.submit(type: "cast", object: obj_id(game, name, zone: :hand, player: "alice"))

  def pay_all(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { %w[pay_mana activate_mana].include?(it[:type]) })
    end
  end

  it "offers only the options that could be paid: no Goblin to behold and only {B} means no cast (CR 118.3)" do
    game = board(hand: ["Spec Cursetosser"], lands: ["Swamp"])
    expect(game.legal_options.none? { it[:type] == "cast" }).to be(true)
  end

  it "pays {2} more when that option is chosen (CR 601.2f)" do
    game = board(hand: ["Spec Cursetosser"], lands: %w[Swamp Swamp Swamp])
    cast(game, "Spec Cursetosser")
    expect(game.pending_decision.kind).to eq("choose_cost_option")
    expect(game.pending_decision.details["costs"]).to eq(["Behold a Goblin", "Pay {2}"])
    expect(game.legal_options).to include({ type: "cost_option", option: 1 })
    expect(game.legal_options).not_to include({ type: "cost_option", option: 0 })
    expect(Enjine::CLI::Text.new(game).option({ type: "cost_option", option: 1 })).to eq("Pay {2}")
    game.submit(type: "cost_option", option: 1)
    expect(game.pending_decision.details["remaining"]).to eq("{2}{B}")
    pay_all(game)
    expect(game.state.stack.size).to eq(1)
  end

  it "beholds a Goblin card from the hand instead, revealing it (CR 701.4a)" do
    game = board(hand: ["Spec Cursetosser", "Spec Hand Goblin"], lands: ["Swamp"])
    cast(game, "Spec Cursetosser")
    expect(game.legal_options).to eq([{ type: "cost_option", option: 0 }, { type: "cancel" }])
    game.submit(type: "cost_option", option: 0)
    expect(game.pending_decision.kind).to eq("choose_cost")
    game.submit(type: "cost", object: obj_id(game, "Spec Hand Goblin", zone: :hand, player: "alice"))
    entry = nil
    entry = game.submit(game.legal_options.find { %w[pay_mana activate_mana].include?(it[:type]) }) while game.pending_decision.kind == "pay_cost"
    expect(game.state.stack.size).to eq(1)
    expect(entry.events.map(&:type)).to include("spell_cast")
  end

  it "an activated ability's cost: sacrifice an artifact or discard a nonland card (CR 602.2b)" do
    game = board(hand: %w[Swamp Forest], field: ["Spec Dart Dealer"], lands: ["Swamp"])
    expect(game.legal_options.none? { it[:type] == "activate" }).to be(true) # only lands to discard

    game = board(hand: ["Spec Hand Goblin"], field: ["Spec Dart Dealer"], lands: ["Swamp"])
    game.submit(game.legal_options.find { it[:type] == "activate" })
    expect(game.legal_options).to eq([{ type: "cost_option", option: 1 }, { type: "cancel" }])
    game.submit(type: "cost_option", option: 1)
    game.submit(type: "target", target: "player:bob")
    game.submit(game.legal_options.find { it[:type] == "cost" })
    pay_all(game)
    expect(game.state.players[0].graveyard.map { game.state.object(it).card }).to eq(["spec_hand_goblin"])
    pass_both(game)
    expect(game.state.players[1].life).to eq(18)
  end

  describe "paying while resolving (CR 118.12)" do
    it "Ward—Pay 2 life: the targeting player may pay life instead of mana (CR 702.21a, 119.4)" do
      game = board(hand: ["Lightning Bolt"], lands: ["Mountain"], theirs: ["Spec Life Warden"])
      expect(game.catalog.fetch("spec_life_warden").abilities.first.to_s).to eq("Ward—Pay 2 life")
      bolt_at(game, "Spec Life Warden")
      expect(game.legal_options).to eq([{ type: "pay" }, { type: "decline" }])
      game.submit(type: "pay")
      expect(game.state.players[0].life).to eq(18)
      pass_both(game)
      expect(game.state.players[1].graveyard.size).to eq(1)
    end

    it "Ward—Pay 2 life can't be paid with 1 life: the spell is countered (CR 118.3)" do
      game = board(hand: ["Lightning Bolt"], lands: ["Mountain"], theirs: ["Spec Life Warden"], life: 1)
      bolt_at(game, "Spec Life Warden")
      expect(game.legal_options).to eq([{ type: "decline" }])
      game.submit(type: "decline")
      expect(game.state.stack).to be_empty
    end

    it "Ward—Discard a card or pay {2}: each open way is a choice; the card is chosen, then discarded" do
      game = board(hand: ["Lightning Bolt", "Forest"], lands: ["Mountain"], theirs: ["Spec Toll Titan"])
      bolt_at(game, "Spec Toll Titan")
      expect(game.legal_options).to eq([{ type: "pay", option: 0, cost: "Discard a card" }, { type: "decline" }])
      game.submit(type: "pay", option: 0, cost: "Discard a card")
      forest = obj_id(game, "Forest", zone: :hand, player: "alice")
      expect(game.legal_options).to eq([{ type: "cost", object: forest }])
      game.submit(type: "cost", object: forest)
      expect(game.state.players[0].graveyard.map { game.state.object(it).card }).to include("forest")
      expect(game.state.stack.size).to eq(1)
    end

    it "Ward—Discard a card or pay {2}: paying the mana; cancelling it counts as not paying" do
      game = board(hand: ["Lightning Bolt"], lands: %w[Mountain Swamp Swamp], theirs: ["Spec Toll Titan"])
      bolt_at(game, "Spec Toll Titan")
      game.submit(type: "pay", option: 1, cost: "{2}")
      pay_all(game)
      expect(game.state.stack.size).to eq(1)

      game = board(hand: ["Lightning Bolt"], lands: %w[Mountain Swamp Swamp], theirs: ["Spec Toll Titan"])
      bolt_at(game, "Spec Toll Titan")
      game.submit(type: "pay", option: 1, cost: "{2}")
      game.submit(type: "cancel")
      expect(game.state.stack).to be_empty
    end

    it "Ward—Get five poison counters (CR 122.1)" do
      game = board(hand: ["Lightning Bolt"], lands: ["Mountain"], theirs: ["Spec Venom Society"])
      bolt_at(game, "Spec Venom Society")
      game.submit(type: "pay")
      expect(game.state.players[0].poison).to eq(5)
      expect(game.state.stack.size).to eq(1)
    end

    it "\"you may sacrifice an artifact or discard a card. If you do, draw a card\"" do
      game = board(hand: ["Spec Scrap Courier", "Forest"], field: ["Spec Bauble"], lands: %w[Mountain Mountain])
      cast(game, "Spec Scrap Courier")
      pay_all(game)
      pass_both(game) # the creature resolves; its trigger goes on the stack
      pass_both(game)
      expect(game.legal_options.map { it[:type] }).to eq(%w[pay pay decline])
      game.submit(game.legal_options.first)
      game.submit(type: "cost", object: obj_id(game, "Spec Bauble"))
      expect(game.state.players[0].graveyard.map { game.state.object(it).card }).to eq(["spec_bauble"])
      expect(game.state.players[0].hand.size).to eq(2)
    end
  end
end
