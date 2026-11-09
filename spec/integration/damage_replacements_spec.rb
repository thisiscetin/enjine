# frozen_string_literal: true

RSpec.describe "Damage replacement, redirection and prevention (CR 614.1a, 614.9, 615, 616.1)" do
  def creature(name, power, toughness, *abilities, types: ["creature"])
    { "name" => name, "mana_cost" => "{1}", "types" => types, "subtypes" => ["bear"], "power" => power,
      "toughness" => toughness, "abilities" => abilities }
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, who) = game.state.players[game.names.index(who)].life
  def id(game, name) = obj_id(game, name)

  let(:doubler) do
    creature("Doubling Drake", 1, 1, { "damage_replacement" => { "by" => { "controller" => "you" },
                                                                 "to" => { "controller" => "opponent" }, "multiply" => 2 } })
  end
  let(:sparker) do
    creature("Spark Adept", 1, 1, { "damage_replacement" => { "by" => { "controller" => "you" }, "to" => { "controller" => "opponent" },
                                                              "combat" => "noncombat", "plus" => 1 } })
  end
  let(:guardian) do
    creature("Shell Guardian", 2, 20, { "damage_replacement" => { "to" => { "controller" => "you", "other" => true },
                                                                  "redirect" => "self" } })
  end
  let(:fog_wall) do
    creature("Mist Wall", 0, 2, { "prevent_damage" => { "to" => "self", "combat" => "combat" } },
             { "prevent_damage" => { "by" => "self", "combat" => "combat" } })
  end
  let(:barricade) do
    creature("Ward Barricade", 0, 4, { "prevent_damage" => { "to" => { "each" => "creature", "controller" => "you", "other" => true },
                                                             "combat" => "noncombat" } })
  end
  let(:spoiler) { creature("Grudge Spoiler", 1, 1, { "damage_unpreventable" => {} }) }
  let(:shock) do
    { "name" => "Test Shock", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                     "effects" => [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }] } }] }
  end
  let(:shield) do
    { "name" => "Bend Aside", "mana_cost" => "{W}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                     "effects" => [{ "prevent_damage" => { "to" => { "target" => 0 }, "next" => 3 } }] } }] }
  end
  let(:muzzle) do
    { "name" => "Muzzle", "mana_cost" => "{W}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["creature"],
                                     "effects" => [{ "prevent_damage" => { "by" => { "target" => 0 }, "combat" => "combat" } }] } }] }
  end
  let(:catalog) { catalog_with(doubler, sparker, guardian, fog_wall, barricade, spoiler, shock, shield, muzzle) }

  def board(alice: [], bob: [], hand: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield(*alice) unless alice.empty?
        hand(*hand) unless hand.empty?
        battlefield "Mountain", count: 2
        battlefield "Plains"
        library "Forest", count: 5
      end
      player("bob") do
        battlefield(*bob) unless bob.empty?
        library "Forest", count: 5
      end
    end
  end

  def cast(game, card, target)
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: "alice"))
    game.submit(type: "target", target: target)
    while game.pending_decision&.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "activate_mana" } || game.legal_options.first)
    end
    pass_both(game)
  end

  describe "damage modification (CR 614.1a)" do
    it "doubles damage a source you control deals to an opponent or their permanents, not to yours" do
      game = board(alice: ["Doubling Drake", "Grizzly Bears"], bob: ["Hill Giant"], hand: ["Test Shock"])
      cast(game, "Test Shock", "player:bob")
      expect(life(game, "bob")).to eq(16)

      giant = game.state.battlefield.find { game.state.object(it).card == "hill_giant" }
      expect(engine(game).deal_damage!(id(game, "Grizzly Bears"), giant, 1)).to eq(2)
      expect(engine(game).deal_damage!(giant, id(game, "Grizzly Bears"), 1)).to eq(1) # bob's source: unchanged
    end

    it "adds to noncombat damage only, and doubles before adding (the order the affected player picks, CR 616.1)" do
      game = board(alice: ["Spark Adept", "Doubling Drake"])
      adept = id(game, "Spark Adept")
      expect(engine(game).deal_damage!(adept, "player:bob", 2)).to eq(5) # 2 * 2 + 1
      expect(engine(game).deal_damage!(adept, "player:bob", 2, combat: true)).to eq(4)
      expect(life(game, "bob")).to eq(11)
    end

    it "applies to the redirected recipient: still a permanent of the same opponent (CR 616.1f)" do
      game = board(alice: ["Shell Guardian"], bob: ["Doubling Drake"])
      drake = id(game, "Doubling Drake")
      guardian = id(game, "Shell Guardian")
      expect(engine(game).deal_damage!(drake, "player:alice", 3)).to eq(6) # doubled: alice is bob's opponent
      expect(life(game, "alice")).to eq(20)
      expect(game.state.object(guardian).damage).to eq(6)
    end
  end

  describe "redirection (CR 614.9)" do
    it "deals damage that would be dealt to you and your other permanents to this creature instead" do
      game = board(alice: ["Shell Guardian", "Grizzly Bears"], hand: [])
      guardian = id(game, "Shell Guardian")
      expect(engine(game).deal_damage!(nil, "player:alice", 2)).to eq(2)
      engine(game).deal_damage!(nil, id(game, "Grizzly Bears"), 3)
      expect(life(game, "alice")).to eq(20)
      expect(game.state.object(guardian).damage).to eq(5)
      expect(game.state.object(id(game, "Grizzly Bears")).damage).to eq(0)
      expect(engine(game).deal_damage!(nil, "player:bob", 1)).to eq(1) # bob isn't protected
      expect(life(game, "bob")).to eq(19)
    end

    it "does nothing once the new recipient is gone (CR 614.9)" do
      game = board(alice: ["Shell Guardian"])
      guardian = id(game, "Shell Guardian")
      engine(game).move!(guardian, :graveyard, reason: "destroy")
      engine(game).deal_damage!(nil, "player:alice", 2)
      expect(life(game, "alice")).to eq(18)
    end
  end

  describe "prevention (CR 615)" do
    it "prevents combat damage dealt to and by a creature, but not noncombat damage" do
      game = board(alice: ["Mist Wall", "Grizzly Bears"])
      wall = id(game, "Mist Wall")
      bears = id(game, "Grizzly Bears")
      expect(engine(game).deal_damage!(bears, wall, 2, combat: true)).to eq(0)
      expect(engine(game).deal_damage!(wall, bears, 2, combat: true)).to eq(0)
      expect(engine(game).deal_damage!(bears, wall, 1)).to eq(1)
    end

    it "prevents noncombat damage to other creatures you control (Crystal Barricade-style)" do
      game = board(alice: ["Ward Barricade", "Grizzly Bears"])
      bears = id(game, "Grizzly Bears")
      expect(engine(game).deal_damage!(nil, bears, 2)).to eq(0)
      expect(engine(game).deal_damage!(nil, bears, 1, combat: true)).to eq(1)
      expect(engine(game).deal_damage!(nil, id(game, "Ward Barricade"), 1)).to eq(1) # not "other"
      expect(engine(game).deal_damage!(nil, "player:alice", 1)).to eq(1) # players aren't creatures
    end

    it "shields the next 3 damage, used up across damage events (CR 615.7)" do
      game = board(hand: ["Bend Aside"])
      cast(game, "Bend Aside", "player:alice")
      expect(game.state.effects.last).to include("kind" => "prevent_damage", "remaining" => 3, "to" => ["player:alice"])
      expect(engine(game).deal_damage!(nil, "player:alice", 2)).to eq(0)
      expect(engine(game).deal_damage!(nil, "player:alice", 2)).to eq(1)
      expect(game.state.effects.none? { it["kind"] == "prevent_damage" }).to be(true)
      expect(engine(game).deal_damage!(nil, "player:alice", 2)).to eq(2)
      expect(life(game, "alice")).to eq(17)
    end

    it "prevents combat damage a target creature would deal this turn, and it round-trips (CR 615.1)" do
      game = board(bob: ["Hill Giant"], hand: ["Muzzle"])
      giant = id(game, "Hill Giant")
      cast(game, "Muzzle", giant)
      game = Enjine::Game.import(game.export, catalog: catalog)
      expect(engine(game).deal_damage!(giant, "player:alice", 3, combat: true)).to eq(0)
      expect(engine(game).deal_damage!(giant, "player:alice", 3)).to eq(3)
    end

    it "can't prevent damage while damage can't be prevented; shields aren't used up (CR 615.12)" do
      game = board(alice: ["Mist Wall", "Grizzly Bears"], bob: ["Grudge Spoiler"], hand: ["Bend Aside"])
      cast(game, "Bend Aside", "player:alice")
      expect(engine(game).deal_damage!(id(game, "Grizzly Bears"), id(game, "Mist Wall"), 1, combat: true)).to eq(1)
      expect(engine(game).deal_damage!(nil, "player:alice", 2)).to eq(2)
      expect(game.state.effects.last).to include("remaining" => 3)
    end

    it "a shield counter doesn't prevent damage that can't be prevented, but is still removed (CR 122.1c, 615.12)" do
      game = build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") { battlefield "Grizzly Bears", counters: { "shield" => 1 } }
        player("bob") { battlefield "Grudge Spoiler" }
      end
      bears = game.state.object(id(game, "Grizzly Bears"))
      expect(engine(game).deal_damage!(id(game, "Grudge Spoiler"), bears.id, 1)).to eq(1)
      expect([bears.damage, bears.counters.fetch("shield", 0)]).to eq([1, 0])
    end
  end
end
