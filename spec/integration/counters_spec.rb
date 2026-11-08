# frozen_string_literal: true

RSpec.describe "Counters with rules (CR 122) and entering with counters (CR 614.1c)" do
  def spell(name, effects, targets = [])
    { "name" => name, "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? } }] }
  end

  def creature(name, power, toughness, abilities = [])
    { "name" => name, "mana_cost" => "{1}", "types" => ["creature"], "power" => power, "toughness" => toughness,
      "abilities" => abilities }.reject { |_, v| v == [] }
  end

  let(:catalog) do
    catalog_with(
      spell("Doom Ray", [{ "destroy" => { "to" => { "target" => 0 } } }], ["creature"]),
      spell("Wake Pulse", [{ "untap" => { "to" => { "target" => 0 } } }], ["creature"]),
      spell("Daze Lance", [{ "tap" => { "to" => { "target" => 0 } } },
                           { "add_counters" => { "counter" => "stun", "amount" => 1, "to" => { "target" => 0 } } }],
            ["creature"]),
      spell("Growth Surge", [{ "add_counters" => { "counter" => "+1/+1", "amount" => 2, "to" => { "target" => 0 } } }],
            ["creature"]),
      spell("Call Recruits", [{ "create_token" => { "token" => { "name" => "Recruit", "types" => ["creature"],
                                                                 "power" => 1, "toughness" => 1 } } }]),
      creature("Plated Hatchling", 1, 1, [{ "enters_with_counters" => { "counters" => { "+1/+1" => 2 } } }]),
      creature("Hive Warden", 2, 2,
               [{ "enters_with_counters" => { "counters" => { "+1/+1" => 1 },
                                              "affects" => { "each" => "creature", "controller" => "you",
                                                             "other" => true } } }]),
      creature("Ripple Keeper", 2, 3, [{ "double_counters" => { "affects" => { "each" => "creature", "controller" => "you" } } }])
    )
  end

  def engine(game) = game.instance_variable_get(:@engine)

  def board(alice: [], bob: [], hand: [], step: :precombat_main, active: "alice", &extra)
    build_game(catalog) do
      turn 3, active: active, step: step
      player("alice") do
        alice.each { |card, opts| battlefield card, **opts.to_h }
        hand.each { hand it }
        battlefield "Mountain"
        library "Forest", count: 5
      end
      player("bob") do
        bob.each { |card, opts| battlefield card, **opts.to_h }
        library "Forest", count: 5
      end
      instance_eval(&extra) if extra
    end
  end

  def cast(game, target = nil)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: target) if target
    game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
    game.submit(type: "pay_mana", mana: "R")
    2.times { game.submit(type: "pass") }
  end

  describe "stun counters (CR 122.1d)" do
    it "a stunned permanent stays tapped in its controller's untap step and loses one stun counter instead (CR 502.3)" do
      game = board(alice: [["Grizzly Bears", { tapped: true, counters: { "stun" => 2 } }],
                           ["Hill Giant", { tapped: true }]], step: :end, active: "bob")
      bears = obj_id(game, "Grizzly Bears")
      skip_to(game, :upkeep, turn: 4)
      expect(game.state.object(bears)).to have_attributes(tapped: true, counters: { "stun" => 1 })
      expect(game.state.object(obj_id(game, "Hill Giant")).tapped).to be(false)
    end

    it "an untapped permanent with a stun counter keeps it: only tapped permanents can be untapped (CR 701.26b)" do
      game = board(alice: [["Grizzly Bears", { counters: { "stun" => 1 } }]], step: :end, active: "bob")
      skip_to(game, :upkeep, turn: 4)
      expect(game.state.object(obj_id(game, "Grizzly Bears")).counters).to eq("stun" => 1)
    end

    it "replaces an untap effect too, and a tap-and-stun spell keeps the creature down" do
      game = board(bob: ["Grizzly Bears"], hand: ["Daze Lance"])
      bears = obj_id(game, "Grizzly Bears")
      cast(game, bears)
      expect(game.state.object(bears)).to have_attributes(tapped: true, counters: { "stun" => 1 })
      engine(game).untap!(game.state.object(bears))
      expect(game.state.object(bears)).to have_attributes(tapped: true, counters: { "stun" => 0 })
      engine(game).untap!(game.state.object(bears))
      expect(game.state.object(bears).tapped).to be(false)
    end
  end

  describe "shield counters (CR 122.1c)" do
    it "a destroy effect removes a shield counter instead (CR 614.1a)" do
      game = board(bob: [["Grizzly Bears", { counters: { "shield" => 1 } }]], hand: ["Doom Ray"])
      bears = obj_id(game, "Grizzly Bears")
      cast(game, bears)
      expect(game.state.battlefield).to include(bears)
      expect(game.state.object(bears).counters).to eq("shield" => 0)
    end

    it "damage is prevented and a shield counter removed (CR 615.1a); the next damage is dealt" do
      game = board(bob: [["Grizzly Bears", { counters: { "shield" => 1 } }]], hand: ["Lightning Bolt"])
      bears = obj_id(game, "Grizzly Bears")
      cast(game, bears)
      expect(game.state.object(bears)).to have_attributes(damage: 0, counters: { "shield" => 0 })
      engine(game).deal_damage!(obj_id(game, "Mountain"), bears, 1)
      expect(game.state.object(bears).damage).to eq(1)
    end

    it "simultaneous combat damage from two blockers is prevented by one shield counter (CR 510.2)" do
      game = board(alice: [["Craw Wurm", { counters: { "shield" => 2 } }]], bob: ["Grizzly Bears", "Grizzly Bears"],
                   step: :beginning_of_combat)
      wurm = obj_id(game, "Craw Wurm")
      pass_both(game)
      game.submit(type: "attack", object: wurm, target: "player:bob")
      game.submit(type: "done") if option_types(game).include?("done")
      pass_both(game)
      game.state.battlefield.select { game.state.object(it).card == "grizzly_bears" }.each do |blocker|
        game.submit(type: "block", object: blocker, attacker: wurm)
      end
      game.submit(type: "done") if option_types(game).include?("done")
      pass_both(game)
      game.submit(game.legal_options.last) until game.pending_decision.kind == "priority"
      expect(game.step).to eq(:combat_damage)
      expect(game.state.object(wurm)).to have_attributes(damage: 0, counters: { "shield" => 1 })
    end

    it "doesn't stop destruction by lethal damage: that isn't an effect (CR 701.8b)" do
      game = board(bob: [["Grizzly Bears", { counters: { "shield" => 1 }, damage: 2 }]])
      engine(game).check_state_based_actions!
      expect(game.state.players[1].graveyard.map { game.state.object(it).card }).to eq(["grizzly_bears"])
    end
  end

  it "finality counters exile a permanent that would go to the graveyard (CR 122.1h)" do
    game = board(bob: [["Grizzly Bears", { counters: { "finality" => 1 } }]], hand: ["Doom Ray"])
    cast(game, obj_id(game, "Grizzly Bears"))
    expect(game.state.exile.map { game.state.object(it).card }).to eq(["grizzly_bears"])
  end

  it "+1/+1 and -1/-1 counters annihilate as a state-based action (CR 704.5q)" do
    game = board(alice: [["Grizzly Bears", { counters: { "+1/+1" => 3, "-1/-1" => 1 } }]])
    engine(game).check_state_based_actions!
    bears = game.state.object(obj_id(game, "Grizzly Bears"))
    expect(bears.counters).to eq("+1/+1" => 2, "-1/-1" => 0)
    expect(engine(game).power_toughness(bears)).to eq([4, 4])
  end

  it "keyword counters grant their keyword (CR 122.1b) and any +X/+Y counter modifies P/T (CR 122.1a)" do
    game = board(alice: [["Grizzly Bears", { counters: { "flying" => 1, "+2/+0" => 1, "oil" => 3 } }]])
    bears = obj_id(game, "Grizzly Bears")
    expect(engine(game).chars(bears).keyword?(:flying)).to be(true)
    expect(engine(game).power_toughness(game.state.object(bears))).to eq([4, 2])
    expect(view_of(game, bears)["counters"]).to include("oil" => 3)
  end

  it "named counters round-trip through export and import, and invalid names are rejected" do
    game = board(alice: [["Grizzly Bears", { counters: { "oil" => 2, "lore" => 1 } }]])
    copy = Enjine::Game.import(game.export, catalog: game.catalog)
    expect(copy.state.object(obj_id(copy, "Grizzly Bears")).counters).to eq("oil" => 2, "lore" => 1)
    data = JSON.parse(game.export)
    data["state"]["objects"].find { it["card"] == "grizzly_bears" }["counters"] = { "Bad Name" => 1 }
    expect { Enjine::Game.import(JSON.generate(data), catalog: game.catalog) }.to raise_error(Enjine::InvalidSnapshot, /counters/)
  end

  describe "entering with counters (CR 614.1c, 122.6)" do
    it "a permanent enters with its own counters" do
      game = board(hand: ["Plated Hatchling"])
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
      game.submit(type: "pay_mana", mana: "R")
      pass_both(game)
      hatchling = game.state.object(obj_id(game, "Plated Hatchling"))
      expect(hatchling.counters).to eq("+1/+1" => 2)
      expect(engine(game).power_toughness(hatchling)).to eq([3, 3])
    end

    it "a permanent gives extra counters to your other entering creatures, tokens included; not the opponent's" do
      game = board(alice: ["Hive Warden"], hand: ["Call Recruits"])
      cast(game)
      recruit = game.state.battlefield.find { game.state.object(it).card.start_with?("recruit") }
      expect(game.state.object(recruit).counters).to eq("+1/+1" => 1)
      eng = engine(game)
      bob_bears = eng.create_object("grizzly_bears", 1, :hand)
      game.state.players[1].hand << bob_bears.id
      expect(eng.move!(bob_bears.id, :battlefield, reason: "test").counters).to eq({})
      own = eng.create_object("plated_hatchling", 0, :hand)
      game.state.players[0].hand << own.id
      expect(eng.move!(own.id, :battlefield, reason: "test").counters).to eq("+1/+1" => 3)
    end

    it "the source must be on the battlefield already: it doesn't modify itself entering" do
      game = board
      eng = engine(game)
      warden = eng.create_object("hive_warden", 0, :hand)
      game.state.players[0].hand << warden.id
      expect(eng.move!(warden.id, :battlefield, reason: "test").counters).to eq({})
    end

    it "doubling: counters you put on your creatures, including entering ones, are doubled (CR 614.1a)" do
      game = board(alice: ["Ripple Keeper", "Hive Warden", "Grizzly Bears"], bob: ["Hill Giant"],
                   hand: ["Growth Surge"])
      bears = obj_id(game, "Grizzly Bears")
      cast(game, bears)
      expect(game.state.object(bears).counters).to eq("+1/+1" => 4)
      eng = engine(game)
      eng.add_counters!(game.state.object(obj_id(game, "Hill Giant")), "+1/+1", 1, by_player: 0)
      expect(game.state.object(obj_id(game, "Hill Giant")).counters).to eq("+1/+1" => 1) # not your creature
      eng.add_counters!(game.state.object(bears), "+1/+1", 1, by_player: 1)
      expect(game.state.object(bears).counters).to eq("+1/+1" => 5) # an opponent put it
      token = eng.create_token!(Enjine::CardDefinition.token("name" => "Recruit", "types" => ["creature"],
                                                             "power" => 1, "toughness" => 1), 0)
      expect(token.counters).to eq("+1/+1" => 2)
    end
  end

  it "validates counter names and entering-counter data" do
    strong = { "creature" => { "power" => { "at_least" => 2 } } }
    bad = creature("Bad Hatchling", 1, 1, [{ "enters_with_counters" => { "counters" => { "Big!" => 0 },
                                                                         "affects" => { "each" => strong, "controller" => "me" } } },
                                           { "enters_with_counters" => { "counters" => [] } },
                                           { "enters_with_counters" => { "counters" => { "oil" => 1 }, "affects" => "creature" } },
                                           { "double_counters" => { "affects" => "creature", "counter" => "Nope!" } },
                                           { "double_counters" => { "affects" => { "each" => { "creature" => { "tapped" => true } },
                                                                                   "controller" => "nobody" } } }])
    expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition) { |e|
      expect(e.errors).to include(
        a_string_matching(/counters\.big!: must be a counter name/), a_string_matching(/counters\.big!: must be an integer >= 1/),
        a_string_matching(/affects\.each: power can't be used/), a_string_matching(/affects\.controller: must be one of/),
        a_string_matching(/abilities\[1\]\.enters_with_counters\.counters: must be a non-empty object/),
        a_string_matching(/abilities\[2\]\.enters_with_counters\.affects: must be/),
        a_string_matching(/abilities\[3\]\.double_counters\.affects: must be/),
        a_string_matching(/abilities\[3\]\.double_counters\.counter: must be a counter name/),
        a_string_matching(/abilities\[4\]\.double_counters\.affects\.each: tapped can't be used/),
        a_string_matching(/abilities\[4\]\.double_counters\.affects\.controller: must be one of/)
      )
    }
  end

  it "describes the abilities" do
    defs = ["Plated Hatchling", "Hive Warden", "Ripple Keeper"].map { catalog.fetch(Enjine::CardDefinition.slug(it)).abilities.first.to_s }
    expect(defs).to eq(["enters with 2 +1/+1 counters", "creatures you control enter with an additional 1 +1/+1 counter",
                        "you put twice as many counters on each creature you control"])
  end
end
