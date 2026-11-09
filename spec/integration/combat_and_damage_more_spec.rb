# frozen_string_literal: true

# Block restrictions, attack triggers and restrictions, damage kept through cleanup, last known
# information of a damage source and excess damage in a fight (CR 120.4a, 508.1c, 509.1b, 514.2, 603.2,
# 701.14, 702.2e, 702.80b).
RSpec.describe "Combat and damage: restrictions, first attacks, LKI and fights" do
  def creature(name, power, toughness, *abilities, keywords: [], types: ["creature"], subtypes: ["bear"])
    { "name" => name, "mana_cost" => "{1}", "types" => types, "subtypes" => subtypes, "power" => power,
      "toughness" => toughness, "keywords" => keywords, "abilities" => abilities }
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, who) = game.state.players[game.names.index(who)].life
  def id(game, name) = obj_id(game, name)
  def triggered(trigger, *effects, targets: []) = { "triggered" => { "when" => trigger, "targets" => targets, "effects" => effects } }
  def gain(amount = 1) = { "gain_life" => { "amount" => amount, "to" => "you" } }

  let(:drone) do
    creature("Sky Drone", 1, 1, { "can_block_only" => { "filter" => { "creature" => { "keywords" => ["flying"] } } } },
             keywords: ["flying"])
  end
  let(:flier) { creature("Wind Bird", 1, 1, keywords: ["flying"]) }
  let(:stinger) do
    creature("Last Stinger", 1, 1, triggered({ "dies" => {} }, { "deal_damage" => { "amount" => 1, "to" => { "target" => 0 } } },
                                             targets: ["creature"]), keywords: %w[deathtouch wither])
  end
  let(:turtle) { creature("Old Turtle", 8, 20, keywords: ["keeps_damage"]) }
  let(:storm) do
    creature("Storm Heart", 4, 5, { "damage_replacement" => { "by" => { "each" => { "creature" => { "entered_this_turn" => true } },
                                                                        "controller" => "you" }, "multiply" => 2 } })
  end
  let(:aurelia) do
    creature("First Leader", 3, 4, triggered({ "attacks" => { "first_time_this_turn" => true } },
                                             { "untap" => { "to" => { "each" => "creature", "controller" => "you" } } },
                                             { "additional_phases" => { "phases" => ["combat"] } }), keywords: ["vigilance"])
  end
  let(:worm) do
    on = { "player_attacks" => { "attacking_power" => { "at_least" => 8 }, "first_time_this_turn" => true } }
    creature("Desert Worm", 6, 5, triggered(on,
                                            gain(5)))
  end
  let(:bumi) do
    creature("Rock Boss", 5, 4, triggered({ "attacks" => {} },
                                          { "additional_phases" => { "phases" => ["combat"],
                                                                     "attackers" => { "creature" => { "types" => ["land"] } } } }),
             keywords: ["vigilance"])
  end
  let(:land_creature) { creature("Walking Hill", 2, 2, types: %w[land creature], subtypes: []).except("mana_cost") }
  let(:rampage) do
    { "name" => "Wild Rampage", "mana_cost" => "{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => [{ "creature" => { "controller" => "you" } },
                                                   { "creature" => { "controller" => "opponent" } }],
                                     "effects" => [{ "fight" => { "to" => { "target" => 0 }, "with" => { "target" => 1 } } },
                                                   { "reflexive_trigger" => { "if" => { "amount" => { "this_way" => 0 }, "at_least" => 1 },
                                                                              "effects" => [gain({ "this_way" => 0 })] } }] } }] }
  end
  let(:big) { creature("Big Brute", 6, 6) }
  let(:small) { creature("Small Fry", 2, 2) }
  let(:catalog) { catalog_with(drone, flier, stinger, turtle, storm, aurelia, worm, bumi, land_creature, rampage, big, small) }

  def board(alice: [], bob: [], hand: [], step: :precombat_main, mana: {})
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana) do
        battlefield(*alice) unless alice.empty?
        hand(*hand) unless hand.empty?
        library "Forest", count: 5
      end
      player("bob") do
        battlefield(*bob) unless bob.empty?
        library "Forest", count: 5
      end
    end
  end

  def resolve_all(game)
    while game.state.stack.any? || game.state.pending_triggers.any?
      game.submit(game.pending_decision.kind == "priority" ? { type: "pass" } : game.legal_options.first)
    end
  end

  def attack(game, *names)
    pass_both(game) until game.pending_decision.kind == "declare_attackers"
    names.each { game.submit(type: "attack", object: id(game, it), target: "player:bob") }
    game.submit(type: "done") if game.legal_options.include?(type: "done")
  end

  describe "\"can block only creatures with flying\" (CR 509.1b)" do
    it "offers the restricted creature only as a blocker of a matching attacker" do
      game = board(alice: ["Wind Bird", "Small Fry"], bob: ["Sky Drone"], step: :beginning_of_combat)
      attack(game, "Wind Bird", "Small Fry")
      pass_both(game) until game.pending_decision.kind == "declare_blockers"
      blocks = game.legal_options.select { it[:type] == "block" }
      expect(blocks).to eq([{ type: "block", object: id(game, "Sky Drone"), attacker: id(game, "Wind Bird") }])
    end
  end

  describe "last known information of a damage source (CR 702.2e, 702.80b)" do
    it "a deathtouch and wither source that left the battlefield still has them" do
      game = board(alice: ["Last Stinger"], bob: ["Big Brute"])
      big = id(game, "Big Brute")
      engine(game).move!(id(game, "Last Stinger"), :graveyard, reason: "destroy")
      resolve_all(game)
      expect(game.state.battlefield).not_to include(big) # deathtouch: destroyed
    end

    it "wither puts -1/-1 counters for the departed source's controller" do
      game = board(alice: ["Last Stinger"], bob: ["Big Brute"])
      big = id(game, "Big Brute")
      eng = engine(game)
      eng.with_last_known("gone#1", { "controller" => 0, "keywords" => ["wither"] }) { eng.deal_damage!("gone#1", big, 2) }
      expect(eng.object(big).counters["-1/-1"]).to eq(2)
      expect(eng.object(big).damage).to eq(0)
    end
  end

  describe "damage isn't removed during cleanup (CR 514.2)" do
    it "keeps marked damage on a creature with keeps_damage" do
      game = board(alice: ["Old Turtle", "Big Brute"])
      eng = engine(game)
      eng.deal_damage!(nil, id(game, "Old Turtle"), 5)
      eng.deal_damage!(nil, id(game, "Big Brute"), 2)
      eng.cleanup_turn!
      expect(eng.object(id(game, "Old Turtle")).damage).to eq(5)
      expect(eng.object(id(game, "Big Brute")).damage).to eq(0)
    end
  end

  describe "sources that entered this turn (filter entered_this_turn)" do
    it "doubles damage only from a creature that entered this turn" do
      game = board(alice: ["Storm Heart", "Small Fry", "Big Brute"])
      eng = engine(game)
      eng.object(id(game, "Small Fry")).memory["entered"] = game.state.turn
      expect(eng.deal_damage!(id(game, "Small Fry"), "player:bob", 2)).to eq(4)
      expect(eng.deal_damage!(id(game, "Big Brute"), "player:bob", 2)).to eq(2)
    end
  end

  describe "excess damage dealt in a fight (CR 120.4a, 701.14)" do
    it "is {\"this_way\": n} of the fight, and a reflexive trigger's `if` reads it" do
      game = board(alice: ["Big Brute"], bob: ["Small Fry"], hand: ["Wild Rampage"], mana: { R: 1 })
      game.submit(type: "cast", object: obj_id(game, "Wild Rampage", zone: :hand, player: "alice"))
      game.submit(type: "target", target: id(game, "Big Brute"))
      game.submit(type: "target", target: id(game, "Small Fry"))
      game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
      resolve_all(game)
      expect(life(game, "alice")).to eq(24) # 6 damage to a 2/2: 4 excess
    end

    it "doesn't trigger without excess damage" do
      game = board(alice: ["Small Fry"], bob: ["Big Brute"], hand: ["Wild Rampage"], mana: { R: 1 })
      game.submit(type: "cast", object: obj_id(game, "Wild Rampage", zone: :hand, player: "alice"))
      game.submit(type: "target", target: id(game, "Small Fry"))
      game.submit(type: "target", target: id(game, "Big Brute"))
      game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
      resolve_all(game)
      expect(life(game, "alice")).to eq(20)
      expect(game.state.stack).to be_empty
    end
  end

  describe "\"attacks for the first time each turn\" (CR 603.2)" do
    it "triggers in the first combat only" do
      game = board(alice: ["First Leader"], step: :beginning_of_combat)
      attack(game, "First Leader")
      resolve_all(game)
      expect(game.state.extra_phases["pending"].size).to eq(1)
      pass_both(game) until game.state.step == :end_of_combat
      pass_both(game) until game.pending_decision.kind == "declare_attackers"
      attack(game, "First Leader")
      expect(game.state.pending_triggers).to be_empty
      expect(engine(game).attacks_this_turn(id(game, "First Leader"))).to eq(2)
    end

    it "a withdrawn attack doesn't count" do
      game = board(alice: ["First Leader"], step: :beginning_of_combat)
      pass_both(game) until game.pending_decision.kind == "declare_attackers"
      leader = id(game, "First Leader")
      eng = engine(game)
      eng.declare_attacker!(leader, "player:bob") && nil
      eng.withdraw_attacker!(leader)
      expect(eng.attacks_this_turn(leader)).to eq(0)
      expect(eng.attacked_this_turn?(leader)).to be(false)
    end
  end

  describe "attacking with total power N or greater for the first time each turn" do
    it "triggers once the attackers' total power is high enough, the first such combat only" do
      game = board(alice: ["Desert Worm", "Small Fry", "First Leader"], step: :beginning_of_combat)
      attack(game, "Desert Worm", "Small Fry", "First Leader") # 6 + 2 + 3
      resolve_all(game)
      expect(life(game, "alice")).to eq(25)
      log = engine(game).turn_log(0)["attack_powers"]
      expect(log).to eq([11])
    end

    it "doesn't trigger below the total power" do
      game = board(alice: ["Desert Worm", "Small Fry"], step: :beginning_of_combat)
      attack(game, "Small Fry")
      resolve_all(game)
      expect(life(game, "alice")).to eq(20)
    end
  end

  describe "attack restriction for an added combat phase (CR 508.1c)" do
    it "lets only matching creatures attack during that combat phase" do
      game = board(alice: ["Rock Boss", "Walking Hill", "Small Fry"], step: :beginning_of_combat)
      attack(game, "Rock Boss")
      resolve_all(game)
      pass_both(game) until game.state.step == :end_of_combat
      pass_both(game) until game.pending_decision.kind == "declare_attackers"
      candidates = game.legal_options.select { it[:type] == "attack" }.map { it[:object] }.uniq
      expect(candidates).to eq([id(game, "Walking Hill")])
      expect(Enjine::Snapshot.load(JSON.parse(JSON.generate(game.state.to_h)), game.catalog).extra_phases["attackers"])
        .to eq({ "creature" => { "types" => ["land"] } })
      attack(game, "Walking Hill")
      skip_to(game, :end)
      expect(game.state.extra_phases["attackers"]).to be_nil
    end
  end
end
