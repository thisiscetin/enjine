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
  let(:catalog) { catalog_with(cursetosser, goblin, dealer) }

  def board(hand: [], field: [], lands: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand(*hand)
        battlefield(*field)
        lands.each { battlefield it }
        library "Swamp", count: 5
      end
      player("bob") { library "Swamp", count: 5 }
    end
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
end
