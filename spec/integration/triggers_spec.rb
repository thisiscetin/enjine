# frozen_string_literal: true

RSpec.describe "Triggered abilities (CR 603)" do
  def creature(name, cost, stats, triggered)
    { "name" => name, "mana_cost" => cost, "types" => ["creature"], "power" => stats[0], "toughness" => stats[1],
      "abilities" => (triggered.is_a?(Array) ? triggered : [triggered]).map { { "triggered" => it } } }
  end

  let(:greeter) do
    creature("Gate Greeter", "{W}", [1, 1],
             { "when" => { "enters" => { "subject" => { "each" => "creature", "controller" => "you", "other" => true } } },
               "effects" => [{ "gain_life" => { "amount" => 1 } }] })
  end
  let(:adept) do
    creature("Spark Adept", "{R}", [1, 1],
             { "when" => { "cast" => { "spell" => "noncreature" } },
               "effects" => [{ "pump" => { "power" => 1, "toughness" => 0, "to" => "self" } }] })
  end
  let(:catalog) { catalog_with(greeter, adept) } # the other cards are in the core pool

  def life(game, name) = game.view_for(:observer)["players"].find { it["name"] == name }["life"]

  def cast(game, card, *lands, player: "alice")
    game.submit(type: "cast", object: ids_in(game, player, :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) })
    lands.each do |land|
      game.submit(type: "activate_mana", object: land, ability: mana_ref(game, land))
      game.submit(game.legal_options.find { it[:type] == "pay_mana" })
    end
  end

  def board(&)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      instance_eval(&)
    end
  end

  it "enters: the trigger goes on the stack before anyone gets priority, then resolves (CR 603.3, 603.6a)" do
    game = board do
      player("alice") do
        hand "Tower Scholar"
        battlefield "Island", "Island"
        library "Forest", count: 3
      end
      player("bob") { library "Forest", count: 3 }
    end
    cast(game, "Tower Scholar", *game.state.battlefield)
    entry = nil
    2.times { entry = game.submit(type: "pass") } # the creature spell resolves
    expect(entry.events.map(&:type)).to include("ability_triggered", "trigger_put_on_stack")
    expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Tower Scholar ability"])
    expect(game.pending_decision).to have_attributes(kind: "priority", player: "alice")
    hand_before = ids_in(game, "alice", :hand).size
    pass_both(game)
    expect(ids_in(game, "alice", :hand).size).to eq(hand_before + 1)
  end

  it "dies: looks back in time and still resolves after the creature is gone (CR 603.10a)" do
    game = board do
      player("alice") do
        hand "Lightning Bolt"
        battlefield "Mountain"
      end
      player("bob") { battlefield "Ember Martyr" }
    end
    martyr_id = obj_id(game, "Ember Martyr")
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: martyr_id)
    game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
    game.submit(type: "pay_mana", mana: "R")
    pass_both(game) # Bolt resolves, Martyr dies, its controller (bob) gets the trigger
    expect(game.state.battlefield).not_to include(martyr_id)
    expect(game.view_for(:observer)["stack"].first).to include("name" => "Ember Martyr ability", "controller" => "bob")
    pass_both(game)
    expect(life(game, "alice")).to eq(18)
  end

  it "attacks: triggers when declared as an attacker (CR 508.3a)" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :beginning_of_combat
      player("alice") { battlefield "Banner Raider" }
      player("bob") { library "Forest", count: 3 }
    end
    pass_both(game)
    game.submit(type: "attack", object: obj_id(game, "Banner Raider"), target: "player:bob")
    expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Banner Raider ability"])
    pass_both(game)
    expect(life(game, "alice")).to eq(21)
  end

  it "beginning of your upkeep: only on its controller's turn (CR 503.1a)" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :end
      player("alice") do
        battlefield "Dawn Keeper"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    skip_to(game, :draw, turn: 4) # bob's upkeep: no trigger
    expect(life(game, "alice")).to eq(20)
    skip_to(game, :upkeep, turn: 5)
    expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Dawn Keeper ability"])
    pass_both(game)
    expect(life(game, "alice")).to eq(21)
  end

  it "targets are chosen when the trigger goes on the stack, with no cancel (CR 603.3d)" do
    game = board do
      player("alice") do
        hand "Ridge Sniper"
        battlefield "Mountain", count: 3
      end
      player("bob") { battlefield "Ember Martyr" }
    end
    cast(game, "Ridge Sniper", *game.state.battlefield.first(3))
    pass_both(game)
    sniper = obj_id(game, "Ridge Sniper")
    martyr_id = obj_id(game, "Ember Martyr")
    expect(game.pending_decision).to have_attributes(kind: "choose_target", player: "alice")
    expect(game.legal_options).to eq([{ type: "target", target: sniper }, { type: "target", target: martyr_id }])
    game.submit(type: "target", target: martyr_id)
    pass_both(game)
    expect(game.state.battlefield).not_to include(martyr_id)
  end

  it "a trigger with no legal target is removed from the stack (CR 603.3d)" do
    game = board do
      player("alice")
      player("bob")
    end
    # Put a Ridge Sniper trigger in the queue with no creatures on the battlefield.
    game.state.pending_triggers << { "id" => "t900", "controller" => 0, "source" => "ridge_sniper#900", "card" => "ridge_sniper",
                                     "ability" => "printed:0", "event" => {} }
    game.state.next_id = 1000
    game.submit(type: "pass")
    expect(game.history.last.events.map(&:type)).to include("trigger_removed")
    expect(game.state.stack).to be_empty
  end

  it "APNAP: the active player's triggers go on the stack first, so the other player's resolve first (CR 603.3b)" do
    vigil = creature("Night Vigil", "{B}", [1, 1], { "when" => { "step_begins" => { "step" => "upkeep", "whose" => "each" } },
                                                     "effects" => [{ "gain_life" => { "amount" => 1 } }] })
    game = build_game(catalog_with(vigil)) do
      turn 3, active: "alice", step: :end
      player("alice") do
        battlefield "Night Vigil"
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Night Vigil"
        library "Forest", count: 5
      end
    end
    skip_to(game, :upkeep, turn: 4) # bob's upkeep: both trigger
    expect(game.view_for(:observer)["active"]).to eq("bob")
    expect(game.view_for(:observer)["stack"].map { it["controller"] }).to eq(%w[alice bob]) # top first
    pass_both(game)
    expect(life(game, "alice")).to eq(21)
    expect(life(game, "bob")).to eq(20)
  end

  it "a player with several triggers orders them, one decision each" do
    game = board do
      player("alice") do
        hand "Gate Greeter", "Tower Scholar"
        battlefield "Gate Greeter", "Island", "Island"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    cast(game, "Tower Scholar", *game.state.battlefield.last(2))
    pass_both(game) # Scholar enters: its own enters trigger + Greeter's "another creature" trigger
    expect(game.pending_decision).to have_attributes(kind: "order_triggers", player: "alice", details: { "count" => 2 })
    expect(game.legal_options.size).to eq(2)
    game.submit(game.legal_options.last)
    expect(game.state.stack.size).to eq(2)
    expect(game.pending_decision.kind).to eq("priority")
  end

  it "landfall-style: a land you control entering puts a +1/+1 counter on the source" do
    game = board do
      player("alice") do
        hand "Forest"
        battlefield "Moss Grower"
      end
      player("bob")
    end
    game.submit(type: "play_land", object: ids_in(game, "alice", :hand).first)
    pass_both(game)
    expect(view_of(game, obj_id(game, "Moss Grower"))).to include("power" => 2, "toughness" => 3, "counters" => { "+1/+1" => 1 })
  end

  it "cast trigger: only noncreature spells you cast" do
    game = board do
      player("alice") do
        hand "Lightning Bolt", "Raging Goblin"
        battlefield "Spark Adept", "Mountain", "Mountain"
      end
      player("bob")
    end
    adept_id = obj_id(game, "Spark Adept")
    mountains = game.state.battlefield.last(2)
    cast(game, "Raging Goblin", mountains[0])
    expect(game.state.stack.size).to eq(1)
    pass_both(game)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: "player:bob")
    game.submit(type: "activate_mana", object: mountains[1], ability: "intrinsic:mountain")
    game.submit(type: "pay_mana", mana: "R")
    expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Spark Adept ability", "Lightning Bolt"])
    pass_both(game)
    expect(view_of(game, adept_id)["power"]).to eq(2)
  end

  it "survives export/import while a trigger waits for its target" do
    game = board do
      player("alice") do
        hand "Ridge Sniper"
        battlefield "Mountain", count: 3
      end
      player("bob") { battlefield "Ember Martyr" }
    end
    cast(game, "Ridge Sniper", *game.state.battlefield.first(3))
    pass_both(game)
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.pending_decision).to eq(game.pending_decision)
    expect(copy.state.frames.map { it["type"] }).to eq(%w[put_triggers cast])
  end
end
