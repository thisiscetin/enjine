# frozen_string_literal: true

# Kicker and additional costs (CR 702.33, 601.2b, 601.2f-h), targets that vary with them (CR 702.33g),
# optional and distinct targets (CR 601.2c), dividing among targets (CR 601.2d), and how many modes
# may be chosen (CR 700.2).
RSpec.describe "Kicker, additional costs and target variants (CR 702.33, 601.2b-d, 700.2)" do
  let(:illogical) do
    { "name" => "Spec Logic Denial", "mana_cost" => "{1}{U}", "types" => ["instant"],
      "abilities" => [{ "kicker" => { "cost" => [{ "mana" => "{1}{U}" }] } },
                      { "spell" => { "targets" => [{ "spell" => { "mana_value" => { "at_most" => 2 } } }],
                                     "kicked_targets" => ["spell"],
                                     "effects" => [{ "counter" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:artifact_or_creature) { { "permanent" => { "any_of" => %w[artifact creature] } } }
  let(:mine) { { "permanent" => { "controller" => "you", "not" => ["land"] } } }
  let(:eject) do
    { "name" => "Spec Core Ejection", "mana_cost" => "{1}{B}", "types" => ["instant"],
      "abilities" => [{ "kicker" => { "cost" => [{ "sacrifice_permanent" => { "filter" => artifact_or_creature } }] } },
                      { "spell" => { "targets" => ["creature"], "effects" => [
                        { "pump" => { "power" => -2, "toughness" => -2, "to" => { "target" => 0 }, "if" => { "kicked" => false } } },
                        { "pump" => { "power" => -6, "toughness" => -6, "to" => { "target" => 0 }, "if" => { "kicked" => true } } }
                      ] } }] }
  end
  let(:offering) do
    { "name" => "Spec Grim Offering", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "additional_cost" => { "cost" => [{ "sacrifice_permanent" => { "filter" => "creature" } }] } },
                      { "spell" => { "effects" => [{ "draw" => { "amount" => 2 } }] } }] }
  end
  let(:ghost) do
    { "name" => "Spec Phase Ghost", "mana_cost" => "{1}{W}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => [{ "filter" => mine, "optional" => true }],
                                     "effects" => [{ "gain_life" => { "amount" => 1 } }, { "tap" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:energy) do
    { "name" => "Spec Pure Surge", "mana_cost" => "{W}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => ["creature", { "filter" => "creature", "optional" => true, "distinct_from" => [0] }],
                                     "divide" => 3, "effects" => [{ "distribute_counters" => { "counter" => "+1/+1" } }] } }] }
  end
  let(:captain) do
    { "name" => "Spec Bold Captain", "mana_cost" => "{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "choose" => 1,
                                     "choose_if" => { "if" => { "hand_size" => "you", "at_most" => 0 },
                                                      "choose" => { "min" => 1, "max" => 3 } },
                                     "modes" => [{ "effects" => [{ "gain_life" => { "amount" => 1 } }] },
                                                 { "effects" => [{ "gain_life" => { "amount" => 2 } }] },
                                                 { "effects" => [{ "gain_life" => { "amount" => 4 } }] }] } }] }
  end
  let(:catalog) { catalog_with(illogical, eject, offering, ghost, energy, captain) }

  def board(hand:, lands:, extra: [], opp_hand: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand(*hand)
        battlefield(*lands)
        battlefield(*extra) unless extra.empty?
        library "Forest", count: 5
      end
      player("bob") do
        hand(*opp_hand) unless opp_hand.empty?
        battlefield "Mountain", "Mountain", "Mountain", "Mountain"
        library "Forest", count: 5
      end
    end
  end

  def pay_all(game)
    while game.pending_decision.kind == "pay_cost"
      pay = game.legal_options.find { it[:type] == "pay_mana" }
      game.submit(pay || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  # Bob casts Hill Giant ({3}{R}, mana value 4) and passes, so Alice can respond.
  def with_giant_on_stack(hand:, lands:)
    game = board(hand: hand, lands: lands, opp_hand: ["Hill Giant"])
    game.state.active = 1
    game.state.pending = { "kind" => "priority", "player" => 1 }
    game.state.priority = 1
    game = Enjine::Game.import({ "state" => game.state.to_h }, catalog: catalog)
    game.submit(type: "cast", object: ids_in(game, "bob", :hand).first)
    pay_all(game)
    game.submit(type: "pass")
    game
  end

  it "asks whether to kick first; unkicked, it can target only small spells (CR 601.2b, 702.33g)" do
    game = with_giant_on_stack(hand: ["Spec Logic Denial"], lands: %w[Island Island Island Island])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    expect(game.pending_decision.kind).to eq("choose_kicker")
    expect(game.legal_options).to eq([{ type: "kick" }, { type: "cancel" }]) # unkicked: the Giant's mana value is 4
    game.submit(type: "kick")
    giant = game.state.stack.last
    game.submit(type: "target", target: giant)
    expect(game.pending_decision.details["remaining"]).to eq("{2}{U}{U}")
    pay_all(game)
    spell = game.state.object(game.state.stack.first)
    expect(spell.memory["kicked"]).to be(true)
    pass_both(game)
    expect(game.state.stack).to be_empty
    expect(game.state.players[1].graveyard.size).to eq(1)
  end

  it "isn't castable when only the kicked spell has targets and kicker can't be paid" do
    game = with_giant_on_stack(hand: ["Spec Logic Denial"], lands: %w[Island Island])
    expect(option_types(game)).not_to include("cast")
  end

  it "doesn't offer kick when the kicked total can't be paid" do
    game = board(hand: ["Spec Core Ejection"], lands: %w[Swamp Swamp], extra: ["Grizzly Bears"])
    game.state.objects.each_value { it.counters = {} }
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    expect(game.legal_options).to include({ type: "kick" }, { type: "no_kick" })
    lone = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Spec Logic Denial"
        battlefield "Island", "Island"
      end
      player("bob")
    end
    expect(option_types(lone)).not_to include("cast") # no spell to target at all
  end

  it "kicker with a sacrifice: chosen while casting, sacrificed as it's cast, and the kicked effect applies" do
    game = board(hand: ["Spec Core Ejection"], lands: %w[Swamp Swamp], extra: ["Bastion Golem"])
    golem = obj_id(game, "Bastion Golem")
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "kick")
    game.submit(type: "target", target: golem)
    expect(game.pending_decision.kind).to eq("choose_cost")
    game.submit(type: "cost", object: golem)
    pay_all(game)
    expect(game.state.battlefield).not_to include(golem)
    pass_both(game)
    expect(game.state.players[0].graveyard.size).to eq(2) # the spell and the Golem; its target is gone

    unkicked = board(hand: ["Spec Core Ejection"], lands: %w[Swamp Swamp], extra: ["Hill Giant"])
    unkicked.submit(type: "cast", object: ids_in(unkicked, "alice", :hand).first)
    unkicked.submit(type: "no_kick")
    unkicked.submit(type: "target", target: obj_id(unkicked, "Hill Giant"))
    pay_all(unkicked)
    pass_both(unkicked)
    giant = obj_id(unkicked, "Hill Giant")
    expect(unkicked.view_for(:observer)["battlefield"].find { it["id"] == giant }.values_at("power", "toughness")).to eq([1, 1])
  end

  it "a mandatory additional cost: not castable without a creature to sacrifice (CR 601.2f, 118.3)" do
    none = board(hand: ["Spec Grim Offering"], lands: ["Swamp"])
    expect(option_types(none)).not_to include("cast")
    game = board(hand: ["Spec Grim Offering"], lands: ["Swamp"], extra: ["Grizzly Bears"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    expect(game.pending_decision.kind).to eq("choose_cost")
    game.submit(type: "cost", object: obj_id(game, "Grizzly Bears"))
    pay_all(game)
    expect(game.state.players[0].graveyard.size).to eq(1)
    expect(game.state.object(game.state.stack.first).paid.first["subtypes"]).to eq(["bear"])
  end

  it "an 'up to one' target may be left unchosen; the spell still resolves (CR 601.2c, 608.2b)" do
    game = board(hand: ["Spec Phase Ghost", "Spec Phase Ghost"], lands: %w[Plains Plains Plains Plains], extra: ["Grizzly Bears"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    expect(game.legal_options).to include({ type: "done" }, { type: "target", target: obj_id(game, "Grizzly Bears") })
    game.submit(type: "done")
    pay_all(game)
    expect(game.state.object(game.state.stack.first).targets).to eq([nil])
    pass_both(game)
    expect(game.state.players[0].life).to eq(21)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: obj_id(game, "Grizzly Bears"))
    pay_all(game)
    pass_both(game)
    expect(game.state.object(obj_id(game, "Grizzly Bears")).tapped).to be(true)
  end

  it "one or two different targets, and the amount divided among them, each getting at least one (CR 601.2d)" do
    game = board(hand: ["Spec Pure Surge"], lands: ["Plains"], extra: ["Grizzly Bears", "Hill Giant"])
    bears = obj_id(game, "Grizzly Bears")
    giant = obj_id(game, "Hill Giant")
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: bears)
    expect(game.legal_options.map { it[:target] }).not_to include(bears)
    game.submit(type: "target", target: giant)
    expect(game.pending_decision).to have_attributes(kind: "distribute", details: { "left" => 1 })
    game.submit(type: "assign", target: giant)
    pay_all(game)
    pass_both(game)
    expect([bears, giant].map { game.state.object(it).counters["+1/+1"] }).to eq([1, 2])
  end

  it "a single target gets the whole amount" do
    game = board(hand: ["Spec Pure Surge"], lands: ["Plains"], extra: ["Grizzly Bears"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: obj_id(game, "Grizzly Bears"))
    expect(game.legal_options).to include({ type: "done" })
    game.submit(type: "done")
    pay_all(game)
    pass_both(game)
    expect(game.state.object(obj_id(game, "Grizzly Bears")).counters["+1/+1"]).to eq(3)
  end

  it "chooses one mode, or one or more when a condition holds (CR 700.2)" do
    game = board(hand: ["Spec Bold Captain", "Forest"], lands: ["Mountain"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    expect(game.pending_decision.details).to eq("choose" => 1, "chosen" => 0)
    game.submit(type: "mode", mode: 2)
    pay_all(game)
    pass_both(game)
    expect(game.state.players[0].life).to eq(24)

    empty = board(hand: ["Spec Bold Captain"], lands: ["Mountain"])
    empty.submit(type: "cast", object: ids_in(empty, "alice", :hand).first)
    expect(empty.pending_decision.details).to eq("choose" => 3, "min" => 1, "chosen" => 0)
    expect(option_types(empty)).not_to include("done")
    empty.submit(type: "mode", mode: 0)
    expect(empty.legal_options).to include({ type: "done" }, { type: "mode", mode: 2 })
    empty.submit(type: "mode", mode: 2)
    empty.submit(type: "done")
    pay_all(empty)
    pass_both(empty)
    expect(empty.state.players[0].life).to eq(25)
  end

  context "with more mode rules and kicker edge cases" do
    let(:oracle) do
      { "name" => "Spec Rotating Oracle", "mana_cost" => "{1}", "types" => %w[artifact],
        "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{1}" }], "unchosen" => true, "choose" => { "min" => 1, "max" => 2 },
                                           "modes" => [{ "effects" => [{ "gain_life" => { "amount" => 1 } }] },
                                                       { "effects" => [{ "gain_life" => { "amount" => 2 } }] },
                                                       { "effects" => [{ "gain_life" => { "amount" => 4 } }] }] } }] }
    end
    let(:catalog) { catalog_with(illogical, eject, offering, ghost, energy, captain, oracle) }

    it "may choose one or two modes, never one chosen before for the same object (choose one that hasn't been chosen)" do
      game = board(hand: [], lands: %w[Plains Plains], extra: ["Spec Rotating Oracle"])
      oracle_id = obj_id(game, "Spec Rotating Oracle")
      game.submit(type: "activate", object: oracle_id, ability: "printed:0")
      expect(game.pending_decision.details).to eq("choose" => 2, "min" => 1, "chosen" => 0)
      game.submit(type: "mode", mode: 0)
      game.submit(type: "mode", mode: 2)
      pay_all(game)
      pass_both(game)
      expect(game.state.players[0].life).to eq(25)
      expect(game.state.object(oracle_id).memory["chosen_modes"]).to eq("printed:0" => [0, 2])
      game.submit(type: "activate", object: oracle_id, ability: "printed:0")
      expect(game.legal_options).to eq([{ type: "mode", mode: 1 }, { type: "cancel" }])
      game.submit(type: "mode", mode: 1)
      expect(game.pending_decision.kind).to eq("pay_cost") # no mode left to add
      pay_all(game)
      pass_both(game)
      expect(game.legal_options).not_to include(a_hash_including(type: "activate", object: oracle_id)) # every mode used
    end

    it "offers only 'don't kick' when the kicker cost can't be paid" do
      game = board(hand: ["Spec Core Ejection"], lands: %w[Swamp Swamp])
      engine = game.instance_variable_get(:@engine)
      bear = engine.create_object("grizzly_bears", 1, :battlefield)
      engine.state.battlefield << bear.id
      game = Enjine::Game.import({ "state" => engine.state.to_h }, catalog: catalog)
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      expect(game.legal_options).to eq([{ type: "no_kick" }, { type: "cancel" }])
    end

    it "a target that became illegal gets none of the divided counters (CR 608.2b)" do
      game = board(hand: ["Spec Pure Surge", "Lightning Bolt"], lands: %w[Plains Mountain], extra: ["Grizzly Bears", "Raging Goblin"])
      goblin = obj_id(game, "Raging Goblin")
      bears = obj_id(game, "Grizzly Bears")
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(type: "target", target: bears)
      game.submit(type: "target", target: goblin)
      game.submit(type: "assign", target: bears)
      pay_all(game)
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(type: "target", target: goblin)
      pay_all(game)
      pass_both(game, 2)
      expect(game.state.object(bears).counters["+1/+1"]).to eq(2)
      expect(game.state.battlefield).not_to include(goblin)
    end
  end
end
