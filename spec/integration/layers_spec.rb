# frozen_string_literal: true

RSpec.describe "Layers: conditional and computed statics, type changes, granted abilities (CR 604, 613)" do
  def creature(name, power, toughness, extra = {})
    { "name" => name, "mana_cost" => "{1}", "types" => ["creature"], "power" => power, "toughness" => toughness }.merge(extra)
  end

  def static(params) = { "static" => params }

  let(:cards) do
    yours = ->(each) { { "each" => each, "controller" => "you" } }
    artifact_creatures = { "creature" => { "types" => ["artifact"] } }
    treasures = { "permanent" => { "subtypes" => ["treasure"] } }
    [
      { "name" => "Cloaked Corvette", "mana_cost" => "{1}", "types" => ["artifact"],
        "abilities" => [static("affects" => "self", "if" => { "not" => { "source" => "creature" } }, "keywords" => ["hexproof"])] },
      creature("Dusk Aviator", 2, 2,
               "abilities" => [static("affects" => "self", "if" => { "your_turn" => true }, "keywords" => ["flying"])]),
      creature("Hoard Keeper", 1, 1, "abilities" => [static("affects" => "self", "pump" => {
                                                              "power" => { "count" => yours.call(treasures) },
                                                              "toughness" => { "count" => yours.call(treasures) }
                                                            })]),
      { "name" => "Gene Hex", "mana_cost" => "{1}{B}", "types" => ["enchantment"], "subtypes" => ["aura"],
        "abilities" => [{ "enchant" => "creature" },
                        static("affects" => "attached", "pump" => { "power" => -4, "toughness" => 0 },
                               "keywords" => %w[cant_block doesnt_untap], "creature_types" => ["salamander"])] },
      { "name" => "Identity Shift", "mana_cost" => "{G}", "types" => ["instant"],
        "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [
          { "set_creature_types" => { "types" => ["doctor"], "to" => { "target" => 0 } } }
        ] } }] },
      creature("Hive Relay", 1, 1, "types" => %w[artifact creature], "subtypes" => ["drone"], "abilities" => [
                 static("affects" => yours.call(artifact_creatures), "abilities" => [
                          { "triggered" => { "when" => { "deals_damage" => { "combat" => true, "to" => "player" } },
                                             "effects" => [{ "draw" => { "amount" => 1 } }] } }
                        ])
               ]),
      creature("Root Speaker", 2, 2, "abilities" => [
                 static("affects" => yours.call("creature"), "abilities" => [{ "mana" => { "cost" => ["tap"], "produce" => "{G}{G}" } }])
               ]),
      creature("Drone Collective", { "count" => yours.call(artifact_creatures) }, 2, "types" => %w[artifact creature]),
      creature("Unbound Drone", 0, 4, "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{1}" }], "effects" => [
                 { "set_base_power_toughness" => { "power" => 7, "toughness" => 9, "duration" => "indefinite", "to" => "self" } }
               ] } }]),
      creature("Spanner Sentry", 3, 3, "keywords" => ["defender"], "abilities" => [
                 static("affects" => "self", "if" => { "amount" => { "spells_cast_this_turn" => {
                          "by" => "you", "matching" => { "spell" => { "not" => ["creature"] } }
                        } }, "at_least" => 1 }, "keywords" => ["attacks_despite_defender"])
               ]),
      { "name" => "Split Decision", "mana_cost" => "{B}", "types" => ["instant"],
        "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [
          { "destroy" => { "to" => { "target" => 0 } } },
          { "create_token" => { "token" => { "name" => "Officer", "colors" => ["R"], "types" => ["creature"],
                                             "subtypes" => ["officer"], "power" => 1, "toughness" => 1 },
                                "amount" => 2, "to" => { "controller_of" => { "target" => 0 } } } }
        ] } }] },
      { "name" => "Toll Collector", "mana_cost" => "{B}", "types" => ["sorcery"],
        "abilities" => [{ "spell" => { "effects" => [
          { "lose_life" => { "amount" => { "life_lost_this_turn" => "each_opponent" }, "to" => "each_opponent" } },
          { "gain_life" => { "amount" => { "this_way" => 0 } } }
        ] } }] },
      creature("Final Volley", 3, 3, "abilities" => [{ "activated" => { "cost" => ["sacrifice"], "targets" => ["player"], "effects" => [
                 { "deal_damage" => { "amount" => { "power" => "self" }, "to" => { "target" => 0 } } },
                 { "gain_life" => { "amount" => { "counters" => { "of" => "self", "kind" => "+1/+1" } } } }
               ] } }]),
      creature("Rally Herald", 2, 2, "abilities" => [{ "triggered" => {
                 "when" => { "player_attacks" => {} },
                 "while" => { "amount" => { "power" => yours.call("creature") }, "at_least" => 8 },
                 "effects" => [{ "gain_life" => { "amount" => 2 } }]
               } }])
    ]
  end
  let(:catalog) { catalog_with(*cards) }

  def board(step: :precombat_main, alice: [], bob: [], hand: [], counters: {})
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice") do
        alice.each { battlefield it, counters: counters.fetch(it, {}) }
        hand(*hand) unless hand.empty?
        library "Forest", count: 5
      end
      player("bob") do
        bob.each { battlefield it }
        library "Forest", count: 5
      end
    end
  end

  def engine_of(game) = game.instance_variable_get(:@engine)
  def pt(game, card) = engine_of(game).power_toughness(engine_of(game).object(obj_id(game, card)))

  def pay(game, *lands)
    lands.each do |land|
      game.submit(type: "activate_mana", object: land, ability: mana_ref(game, land))
      game.submit(game.legal_options.find { it[:type] == "pay_mana" })
    end
  end

  def cast(game, card, target: nil, lands: [])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) })
    game.submit(type: "target", target: target) if target
    pay(game, *lands)
  end

  def monitor_findings(game)
    monitor = Enjine::RulesMonitor.new(game)
    monitor.check!(Enjine::HistoryEntry.new(seq: 0, turn: 3, step: "x", player: nil, kind: nil, option: nil, events: []))
  end

  it "applies a static only while its condition holds (CR 604.2): 'as long as it isn't a creature', 'during your turn'" do
    game = board(alice: ["Cloaked Corvette", "Dusk Aviator"])
    engine = engine_of(game)
    expect(engine.chars(obj_id(game, "Cloaked Corvette")).keyword?(:hexproof)).to be(true)
    expect(engine.chars(obj_id(game, "Dusk Aviator")).keyword?(:flying)).to be(true)
    game.state.active = 1
    engine.touch!
    expect(engine.chars(obj_id(game, "Dusk Aviator")).keyword?(:flying)).to be(false)
  end

  it "counts for 'gets +1/+1 for each' as things change (CR 611.3a), and the rules monitor agrees" do
    game = board(alice: ["Hoard Keeper"])
    engine = engine_of(game)
    expect(pt(game, "Hoard Keeper")).to eq([1, 1])
    treasure = Enjine::CardDefinition.token(Enjine::Tokens.fetch("Treasure"))
    game.catalog.add(treasure)
    2.times { engine.create_token!(treasure, 0) }
    expect(pt(game, "Hoard Keeper")).to eq([3, 3])
    expect(monitor_findings(game)).to be_empty
  end

  it "an Aura that sets creature types, pumps, and stops blocking and untapping (CR 205.1a, 613.1d, 502.3)" do
    game = board(alice: ["Gene Hex"], bob: ["Hive Relay"])
    engine = engine_of(game)
    relay = obj_id(game, "Hive Relay")
    engine.object(obj_id(game, "Gene Hex")).attached_to = relay
    engine.object(relay).tapped = true
    engine.touch!
    current = engine.chars(relay)
    expect(current.subtypes).to eq([:salamander])
    expect([current.power, current.toughness]).to eq([-3, 1])
    expect(current.keyword?(:cant_block)).to be(true)
    expect(monitor_findings(game)).to be_empty
    engine.untap_all!(1)
    expect(engine.object(relay).tapped).to be(true)
  end

  it "setting creature types until end of turn replaces creature types only (CR 205.1a)" do
    game = board(alice: ["Forest", "Hive Relay"], hand: ["Identity Shift"])
    relay = obj_id(game, "Hive Relay")
    cast(game, "Identity Shift", target: relay, lands: [obj_id(game, "Forest")])
    pass_both(game)
    expect(engine_of(game).chars(relay)).to have_attributes(subtypes: [:doctor], types: %i[artifact creature])
    skip_to(game, :upkeep, turn: 4)
    expect(engine_of(game).chars(relay).subtypes).to eq([:drone])
  end

  it "grants a triggered ability: it triggers for the creature and resolves from the granting card's data (CR 613.1f)" do
    game = board(step: :beginning_of_combat, alice: ["Hive Relay"])
    relay = obj_id(game, "Hive Relay")
    ref = engine_of(game).chars(relay).triggered_abilities.map(&:ref)
    expect(ref).to eq(["granted:hive_relay:printed:0:0"])
    hand = ids_in(game, "alice", :hand).size
    pass_both(game)
    game.submit(type: "attack", object: relay, target: "player:bob")
    pass_both(game, 2) # blockers, then combat damage
    stack = game.state.stack.map { game.state.object(it) }
    expect(stack.map { [it.card, it.source, it.ability] }).to eq([["hive_relay", relay, "printed:0:0"]])
    pass_both(game)
    expect(ids_in(game, "alice", :hand).size).to eq(hand + 1)
  end

  it "grants a mana ability to each creature you control (CR 613.1f, 605.1a)" do
    game = board(alice: ["Root Speaker", "Grizzly Bears"])
    bears = obj_id(game, "Grizzly Bears")
    option = { type: "activate_mana", object: bears, ability: "granted:root_speaker:printed:0:0" }
    expect(game.legal_options).to include(option)
    game.submit(option)
    expect(game.state.players[0].mana_pool[:G]).to eq(2)
    engine_of(game).object(bears).controlled_since = 3 # arrived this turn: no {T} abilities (CR 302.6)
    engine_of(game).object(bears).tapped = false
    expect(game.legal_options.map { it[:object] }).not_to include(bears)
  end

  it "defines power with a characteristic-defining ability in every zone (CR 604.3, 613.4a)" do
    game = board(alice: ["Drone Collective", "Hive Relay"], hand: ["Drone Collective"])
    engine = engine_of(game)
    expect(pt(game, "Drone Collective")).to eq([2, 2])
    in_hand = engine.object(ids_in(game, "alice", :hand).first)
    expect(engine.power(in_hand)).to eq(2)
    expect(monitor_findings(game)).to be_empty
    expect(Enjine::CardDefinition.from_h(cards[7]).to_h["power"]).to eq(cards[7]["power"])
    bad = cards[7].merge("power" => { "power" => "self" })
    expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition, /power: a characteristic-defining amount/)
  end

  it "sets base power and toughness for as long as it stays (CR 613.4b, 611.2b); counters still apply (613.4c)" do
    game = board(alice: ["Unbound Drone", "Forest"], counters: { "Unbound Drone" => { "+1/+1" => 1 } })
    game.submit(type: "activate", object: obj_id(game, "Unbound Drone"), ability: "printed:0")
    pay(game, obj_id(game, "Forest"))
    pass_both(game)
    expect(pt(game, "Unbound Drone")).to eq([8, 10])
    expect(monitor_findings(game)).to be_empty
    skip_to(game, :upkeep, turn: 4)
    expect(pt(game, "Unbound Drone")).to eq([8, 10])
  end

  it "lets a defender attack while a history condition holds (CR 702.3b, 604.2)" do
    game = board(step: :precombat_main, alice: ["Spanner Sentry", "Mountain"], bob: ["Savannah Lions"], hand: ["Lightning Bolt"])
    engine = engine_of(game)
    sentry = obj_id(game, "Spanner Sentry")
    expect(engine.eligible_attackers).to eq([])
    cast(game, "Lightning Bolt", target: obj_id(game, "Savannah Lions"), lands: [obj_id(game, "Mountain")])
    pass_both(game)
    expect(engine.eligible_attackers).to eq([sentry])
  end

  it "'its controller' of a destroyed target is its controller as it last existed (CR 608.2h); tokens have colors" do
    game = board(alice: ["Swamp"], bob: ["Savannah Lions"], hand: ["Split Decision"])
    cast(game, "Split Decision", target: obj_id(game, "Savannah Lions"), lands: [obj_id(game, "Swamp")])
    pass_both(game)
    tokens = game.state.battlefield.map { game.state.object(it) }.select { it.card.start_with?("officer_token") }
    expect(tokens.map(&:controller)).to eq([1, 1])
    engine = engine_of(game)
    expect(engine.chars(tokens.first).colors).to eq([:R])
    red = Enjine::Mechanics.build_entry(:filter, { "creature" => { "colors" => ["R"] } }, [], "f")
    expect(red.candidates(engine, 0)).to eq(tokens.map(&:id))
  end

  it "gains as much life as an earlier effect took (CR 608.2c)" do
    game = board(alice: ["Swamp"], hand: ["Toll Collector"])
    engine = engine_of(game)
    engine.change_life!(1, -3)
    cast(game, "Toll Collector", lands: [obj_id(game, "Swamp")])
    pass_both(game)
    expect(game.state.players.map(&:life)).to eq([23, 14])
  end

  it "uses the source as it last existed after it was sacrificed to pay the cost (CR 608.2h)" do
    game = board(alice: ["Final Volley"], counters: { "Final Volley" => { "+1/+1" => 2 } })
    game.submit(type: "activate", object: obj_id(game, "Final Volley"), ability: "printed:0")
    game.submit(type: "target", target: "player:bob")
    pass_both(game)
    expect(game.state.players.map(&:life)).to eq([22, 15])
  end

  it "'whenever you attack while ...' checks its condition only as it triggers (CR 603.2)" do
    game = board(step: :beginning_of_combat, alice: ["Rally Herald", "Grizzly Bears"])
    pass_both(game)
    game.submit(type: "attack", object: obj_id(game, "Grizzly Bears"), target: "player:bob")
    game.submit(type: "done")
    expect(game.state.pending_triggers + game.state.stack).to be_empty
    game = board(step: :beginning_of_combat, alice: ["Rally Herald", "Hoard Keeper"], counters: { "Rally Herald" => { "+1/+1" => 6 } })
    pass_both(game)
    game.submit(type: "attack", object: obj_id(game, "Hoard Keeper"), target: "player:bob")
    game.submit(type: "done")
    expect(game.state.stack.size).to eq(1)
    engine_of(game).object(obj_id(game, "Rally Herald")).counters.clear # no longer 8 power: it still resolves
    engine_of(game).touch!
    pass_both(game)
    expect(game.state.players[0].life).to eq(22)
  end

  it "validates statics, granted abilities and the new effects with paths" do
    errors = lambda do |abilities|
      Enjine::CardDefinition.from_h(creature("Bad", 1, 1, "abilities" => abilities))
      []
    rescue Enjine::InvalidCardDefinition => e
      e.errors
    end
    expect(errors.call([static("affects" => "self", "if" => { "source" => { "creature" => { "power" => { "at_least" => 2 } } } },
                               "keywords" => ["flying"])])).to include(a_string_matching(/static.if: can't depend on power/))
    expect(errors.call([static("affects" => "self", "pump" => { "power" => { "power" => "self" } })]))
      .to include(a_string_matching(/pump.power: can't read power/))
    expect(errors.call([static("affects" => "self", "abilities" => [{ "spell" => { "effects" => [] } }])]))
      .to include(a_string_matching(/abilities\[0\]: only triggered and mana abilities/))
    expect(errors.call([static("affects" => "self", "creature_types" => [])])).to include(a_string_matching(/creature_types: must be/))
    expect(errors.call([{ "activated" => { "cost" => ["tap"], "effects" => [
                         { "set_base_power_toughness" => { "power" => 1, "toughness" => 1, "duration" => "forever", "to" => "self" } },
                         { "set_creature_types" => { "types" => "doctor", "to" => "self" } }
                       ] } }])).to include(a_string_matching(/duration: must be one of/),
                                           a_string_matching(/types: must be a non-empty list/))
    expect { Enjine::CardDefinition.from_h(creature("Hued", 1, 1, "colors" => ["purple"])) }
      .to raise_error(Enjine::InvalidCardDefinition, /colors: must be a list/)
  end

  it "describes the new statics and effects" do
    defs = cards.to_h { [it["name"], Enjine::CardDefinition.from_h(it)] }
    expect(defs["Gene Hex"].abilities[1].to_s)
      .to eq("the attached permanent gets -4/+0 and cant_block, doesnt_untap and creature type salamander")
    expect(defs["Dusk Aviator"].abilities[0].to_s).to eq("it gets flying as long as it's your turn")
    expect(defs["Hoard Keeper"].abilities[0].to_s).to start_with("it gets +(the count of each permanent")
    expect(defs["Root Speaker"].abilities[0].to_s).to start_with("creatures you control get \"")
    expect(defs["Unbound Drone"].abilities[0].effects[0].to_s).to eq("base power and toughness become 7/9 → itself")
    expect(defs["Identity Shift"].abilities[0].effects[0].to_s).to eq("becomes doctor until end of turn → target #1")
    expect(defs["Rally Herald"].abilities[0].to_s).to start_with("Whenever you attack while ")
  end
end
