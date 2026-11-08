# frozen_string_literal: true

RSpec.describe "Combat and event triggers, combat restrictions (CR 508-510, 119.9, 121.2)" do
  def creature(name, stats, keywords: [], abilities: [])
    { "name" => name, "mana_cost" => "{1}", "types" => ["creature"], "power" => stats[0], "toughness" => stats[1],
      "keywords" => keywords, "abilities" => abilities }
  end

  # Invented test cards.
  let(:pinger) do
    creature("Spark Courier", [2, 2], abilities: [
               { "triggered" => { "when" => { "deals_damage" => { "combat" => true, "to" => "player" } },
                                  "effects" => [{ "gain_life" => { "amount" => 1 } }] } },
               { "activated" => { "cost" => ["tap"], "targets" => ["any_target"],
                                  "effects" => [{ "deal_damage" => { "amount" => 1, "to" => { "target" => 0 } } }] } }
             ])
  end
  let(:lurker) do
    creature("Menacing Lure", [3, 3], keywords: ["menace"], abilities: [
               { "triggered" => { "when" => { "becomes_blocked" => {} }, "effects" => [{ "draw" => { "amount" => 1 } }] } }
             ])
  end
  let(:surger) { creature("Tidal Surger", [4, 4], keywords: %w[lifelink trample]) }
  let(:catalog) { catalog_with(pinger, lurker, surger) }

  def life(game, name) = game.view_for(:observer)["players"].find { it["name"] == name }["life"]
  def stack_names(game) = game.view_for(:observer)["stack"].map { it["name"] }
  def events_of(game, klass) = game.history.flat_map(&:events).grep(klass)

  def combat(&)
    build_game(catalog) do
      turn 3, active: "alice", step: :beginning_of_combat
      instance_eval(&)
    end
  end

  def attack(game, *ids)
    pass_both(game) # -> declare attackers
    ids.each { game.submit(type: "attack", object: it, target: "player:bob") }
    game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
  end

  describe "deals_damage" do
    it "triggers on combat damage to a player, and the event says it was combat damage (CR 510.2)" do
      game = combat do
        player("alice") { battlefield "Spark Courier" }
        player("bob") { library "Forest", count: 3 }
      end
      attack(game, obj_id(game, "Spark Courier"))
      pass_both(game, 2) # declare attackers, declare blockers (none possible) -> combat damage
      expect(stack_names(game)).to eq(["Spark Courier ability"])
      expect(events_of(game, Enjine::Events::DamageDealt).map(&:combat)).to eq([true])
      pass_both(game)
      expect(life(game, "alice")).to eq(21)
    end

    it "doesn't trigger on noncombat damage or on combat damage to a creature" do
      game = combat do
        player("alice") { battlefield "Spark Courier" }
        player("bob") { battlefield "Grizzly Bears" }
      end
      courier = obj_id(game, "Spark Courier")
      game.submit(type: "activate", object: courier, ability: "printed:1")
      game.submit(type: "target", target: "player:bob")
      pass_both(game)
      expect(life(game, "bob")).to eq(19)
      expect(life(game, "alice")).to eq(20)
      expect(events_of(game, Enjine::Events::DamageDealt).last.combat).to be(false)
      expect(game.state.pending_triggers).to be_empty
    end

    it "counts each combat damage step: double strike triggers twice (CR 510.4)" do
      striker = creature("Twin Fang", [1, 1], keywords: ["double_strike"], abilities: [
                           { "triggered" => { "when" => { "deals_damage" => { "combat" => true, "to" => "player" } },
                                              "effects" => [{ "gain_life" => { "amount" => 1 } }] } }
                         ])
      game = build_game(catalog_with(striker)) do
        turn 3, active: "alice", step: :beginning_of_combat
        player("alice") { battlefield "Twin Fang" }
        player("bob")
      end
      attack(game, obj_id(game, "Twin Fang"))
      pass_both(game, 2)
      expect(game.step).to eq(:combat_damage)
      pass_both(game, 2) # resolve the first trigger, then end the first-strike damage step
      pass_both(game)    # resolve the second
      expect(life(game, "alice")).to eq(22)
      expect(life(game, "bob")).to eq(18)
    end
  end

  it "player_attacks: once per combat however many creatures attack, never without attackers (CR 508.3d)" do
    game = combat do
      player("alice") { battlefield "Warhorn Herald", "Grizzly Bears" }
      player("bob")
    end
    herald = obj_id(game, "Warhorn Herald")
    bears = obj_id(game, "Grizzly Bears")
    attack(game, herald, bears)
    expect(events_of(game, Enjine::Events::AttacksDeclared).map(&:attackers)).to eq([[herald, bears]])
    expect(stack_names(game)).to eq(["Warhorn Herald ability"])
    pass_both(game)
    expect([herald, bears].map { view_of(game, it)["power"] }).to eq([3, 3])

    quiet = combat do
      player("alice") { battlefield "Warhorn Herald" }
      player("bob")
    end
    attack(quiet)
    expect(events_of(quiet, Enjine::Events::AttacksDeclared)).to be_empty
    expect(quiet.state.pending_triggers + quiet.state.stack).to be_empty
  end

  describe "becomes_blocked (CR 509.3c)" do
    let(:game) do
      combat do
        player("alice") do
          battlefield "Menacing Lure"
          library "Forest", count: 5
        end
        player("bob") { battlefield "Grizzly Bears", "Grizzly Bears" }
      end
    end
    let(:lure) { obj_id(game, "Menacing Lure") }

    it "triggers once even when two creatures block" do
      attack(game, lure)
      pass_both(game)
      game.state.battlefield.select { game.state.object(it).card == "grizzly_bears" }.each do |bears|
        game.submit(type: "block", object: bears, attacker: lure)
      end
      expect(events_of(game, Enjine::Events::BecameBlocked).map { [it.object, it.blockers.size] }).to eq([[lure, 2]])
      expect(stack_names(game)).to eq(["Menacing Lure ability"])
    end

    it "doesn't trigger for a block that was taken back before the declaration ended" do
      attack(game, lure)
      pass_both(game)
      bears = game.state.battlefield.find { game.state.object(it).card == "grizzly_bears" }
      game.submit(type: "block", object: bears, attacker: lure)
      expect(option_types(game)).not_to include("done") # menace: one blocker isn't legal
      game.submit(type: "unblock", object: bears)
      game.submit(type: "done")
      expect(events_of(game, Enjine::Events::BecameBlocked)).to be_empty
      expect(game.state.pending_triggers + game.state.stack).to be_empty
    end
  end

  describe "gains_life and loses_life (CR 119.9, 120.3f)" do
    it "lifelink damage split by trample is one life gain event for its source" do
      game = combat do
        player("alice") { battlefield "Tidal Surger", "Dawnhymn Acolyte" }
        player("bob") { battlefield "Raging Goblin" }
      end
      surger = obj_id(game, "Tidal Surger")
      attack(game, surger)
      pass_both(game)
      game.submit(type: "block", object: obj_id(game, "Raging Goblin"), attacker: surger)
      pass_both(game) # -> combat damage: assign it point by point
      game.submit(type: "assign", object: obj_id(game, "Raging Goblin"))
      3.times { game.submit(type: "assign", object: "player:bob") }
      gains = events_of(game, Enjine::Events::LifeChanged).select { it.player == "alice" }
      expect(gains.map(&:gain)).to eq([4])
      expect(stack_names(game)).to eq(["Dawnhymn Acolyte ability"])
    end

    it "an opponent losing life triggers loses_life; your own loss doesn't" do
      game = combat do
        player("alice") { battlefield "Bloodfeast Imp", "Spark Courier" }
        player("bob")
      end
      game.submit(type: "activate", object: obj_id(game, "Spark Courier"), ability: "printed:1")
      game.submit(type: "target", target: "player:alice")
      pass_both(game)
      expect(game.state.stack).to be_empty
      expect(events_of(game, Enjine::Events::LifeChanged).last.loss).to eq(1)
    end
  end

  it "draws: triggers once for each card drawn (CR 121.2)" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Archive Gremlin", "Island", "Island", "Island"
        hand "Divination"
        library "Forest", count: 5
      end
      player("bob")
    end
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.state.battlefield.select { game.state.object(it).card == "island" }.each do |land|
      game.submit(type: "activate_mana", object: land, ability: mana_ref(game, land))
      game.submit(game.legal_options.find { it[:type] == "pay_mana" })
    end
    pass_both(game) # Divination resolves: two draws
    game.submit(game.legal_options.first) if game.pending_decision.kind == "order_triggers"
    expect(stack_names(game)).to eq(["Archive Gremlin ability"] * 2)
    pass_both(game, 2)
    expect(life(game, "bob")).to eq(18)
  end

  it "dies: another creature you control, judged as it last existed (CR 603.10a)" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Lightning Bolt", "Lightning Bolt"
        battlefield "Mountain", "Mountain"
      end
      player("bob") { battlefield "Carrion Warden", "Grizzly Bears" }
    end
    bolt = lambda do |target|
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(type: "target", target: target)
      land = game.state.battlefield.find { game.state.object(it).card == "mountain" && !game.state.object(it).tapped }
      game.submit(type: "activate_mana", object: land, ability: "intrinsic:mountain")
      game.submit(type: "pay_mana", mana: "R")
      pass_both(game)
    end
    bolt.call(obj_id(game, "Grizzly Bears"))
    expect(stack_names(game)).to eq(["Carrion Warden ability"])
    pass_both(game)
    expect(life(game, "bob")).to eq(22)
    bolt.call(obj_id(game, "Carrion Warden")) # "another": its own death doesn't count
    expect(game.state.stack).to be_empty
  end

  it "any_of: one ability with two trigger events (enters, attacks)" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Ridgeline Skirmisher"
        battlefield "Mountain", "Mountain"
      end
      player("bob")
    end
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.state.battlefield.dup.each do |land|
      game.submit(type: "activate_mana", object: land, ability: "intrinsic:mountain")
      game.submit(game.legal_options.find { it[:type] == "pay_mana" })
    end
    pass_both(game)
    expect(stack_names(game)).to eq(["Ridgeline Skirmisher ability"])
    pass_both(game)
    expect(life(game, "bob")).to eq(19)
  end

  describe "restrictions and requirements (CR 508.1c-d, 509.1b)" do
    it "a creature that can't block is never offered as a blocker" do
      game = combat do
        player("alice") { battlefield "Grizzly Bears" }
        player("bob") { battlefield "Rampaging Brute", "Grizzly Bears" }
      end
      attack(game, game.state.battlefield.first)
      pass_both(game)
      blockers = game.legal_options.filter_map { it[:object] }
      expect(blockers).to eq([game.state.battlefield.last])
    end

    it "a creature that can't be blocked skips the declare blockers decision" do
      game = combat do
        player("alice") { battlefield "Fogveil Stalker" }
        player("bob") { battlefield "Grizzly Bears" }
      end
      attack(game, obj_id(game, "Fogveil Stalker"))
      pass_both(game)
      expect(game.pending_decision.kind).to eq("priority")
      expect(game.step).to eq(:declare_blockers)
    end

    it "attacks each combat if able: done is withheld until it attacks, unless it can't" do
      game = combat do
        player("alice") { battlefield "Rampaging Brute", "Grizzly Bears" }
        player("bob")
      end
      pass_both(game)
      expect(option_types(game)).not_to include("done")
      game.submit(type: "attack", object: obj_id(game, "Grizzly Bears"), target: "player:bob")
      expect(option_types(game)).not_to include("done")
      game.submit(type: "attack", object: obj_id(game, "Rampaging Brute"), target: "player:bob")
      expect(game.state.attackers.keys.size).to eq(2)

      tapped = combat do
        player("alice") do
          battlefield "Rampaging Brute", tapped: true
          battlefield "Grizzly Bears"
        end
        player("bob")
      end
      pass_both(tapped)
      expect(option_types(tapped)).to include("done")
    end

    it "a granted restriction lasts until end of turn (CR 514.2), and survives export/import" do
      game = build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand "Shadow Passage"
          battlefield "Grizzly Bears", "Island"
          library "Forest", count: 5
        end
        player("bob") { battlefield "Grizzly Bears" }
      end
      bears = game.state.battlefield.first
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(type: "target", target: bears)
      game.submit(type: "activate_mana", object: obj_id(game, "Island"), ability: "intrinsic:island")
      game.submit(type: "pay_mana", mana: "U")
      pass_both(game)
      expect(game.state.effects.map { it["keywords"] }).to eq([["cant_be_blocked"]])
      copy = Enjine::Game.import(game.export, catalog: game.catalog)
      skip_to(copy, :beginning_of_combat)
      attack(copy, bears)
      pass_both(copy) # bob gets no declare_blockers decision
      expect(copy.step).to eq(:declare_blockers)
      expect(copy.pending_decision.kind).to eq("priority")
      skip_to(copy, :upkeep, turn: 4)
      expect(copy.state.effects).to be_empty
    end
  end
end
