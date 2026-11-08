# frozen_string_literal: true

RSpec.describe "Control changes, combat restrictions, fight and bite (CR 613.1b, 506.5, 509.1b, 701.14)" do
  def pay_all(game)
    while game.pending_decision&.kind == "pay_cost"
      options = game.legal_options
      game.submit(options.find { it[:type] == "pay_mana" } || options.find { it[:type] == "activate_mana" })
    end
  end

  def cast(game, card, *targets, player: "alice")
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: player))
    targets.each { game.submit(type: "target", target: it) }
    pay_all(game)
  end

  def resolve(game)
    game.submit(type: "pass") until game.state.stack.empty? || game.over?
  end

  def controller(game, id) = game.state.object(id).controller

  describe "gaining control (CR 613.1b, 108.4)" do
    it "indefinitely: the permanent stays with its new controller" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { U: 5 }) do
          hand "Usurp Command"
          library "Forest", count: 3
        end
        player("bob") do
          battlefield "Hill Giant"
          library "Forest", count: 3
        end
      end
      giant = obj_id(game, "Hill Giant")
      cast(game, "Usurp Command", giant)
      resolve(game)
      expect(controller(game, giant)).to eq(0)
      skip_to(game, :upkeep, turn: 4)
      expect(controller(game, giant)).to eq(0)
    end

    it "until end of turn: untapped, with haste and an extra subtype, it can attack; control returns at cleanup" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { R: 3 }) do
          hand "Borrowed Blade"
          library "Forest", count: 3
        end
        player("bob") do
          battlefield "Hill Giant", tapped: true
          library "Forest", count: 3
        end
      end
      giant = obj_id(game, "Hill Giant")
      cast(game, "Borrowed Blade", giant)
      entry = game.submit(type: "pass")
      entry = game.submit(type: "pass") until game.state.stack.empty?
      expect(entry.events.map(&:type)).to include("control_changed", "untapped")
      expect(controller(game, giant)).to eq(0)
      chars = Enjine::Engine.new(game.catalog, game.state) { nil }.chars(giant)
      expect(chars.subtypes).to include(:warrior, :giant)
      expect(chars.keyword?(:haste)).to be(true)
      copy = Enjine::Game.import(game.export, catalog: game.catalog)
      skip_to(copy, :upkeep, turn: 4)
      expect(controller(copy, giant)).to eq(1)
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      game.submit(type: "attack", object: giant, target: "player:bob")
      skip_to(game, :upkeep, turn: 4)
      expect(controller(game, giant)).to eq(1)
      expect(game.state.players[1].life).to eq(17)
      expect(game.state.effects).to be_empty
    end

    it "a newer indefinite control change isn't undone when the temporary one ends" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { R: 3, U: 5 }) do
          hand "Borrowed Blade", "Usurp Command"
          library "Forest", count: 3
        end
        player("bob") do
          battlefield "Hill Giant"
          library "Forest", count: 3
        end
      end
      giant = obj_id(game, "Hill Giant")
      cast(game, "Borrowed Blade", giant)
      resolve(game)
      # Bob's creature is now alice's; give it back and take it again for good.
      engine = Enjine::Engine.new(game.catalog, game.state) { nil }
      engine.gain_control_until_end_of_turn!(game.state.object(giant), 0, Enjine::Mechanics::EffectContext.new(0))
      expect(game.state.effects.count { it["kind"] == "control" }).to eq(1) # already alice's: nothing new
      engine.gain_control!(game.state.object(giant), 1)
      cast(game, "Usurp Command", giant)
      resolve(game)
      skip_to(game, :upkeep, turn: 4)
      expect(controller(game, giant)).to eq(0)
    end

    it "two temporary changes ending together return it to the controller before the first" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { R: 3 }) do
          hand "Borrowed Blade"
          library "Forest", count: 3
        end
        player("bob") do
          battlefield "Hill Giant"
          library "Forest", count: 3
        end
      end
      giant = obj_id(game, "Hill Giant")
      cast(game, "Borrowed Blade", giant)
      resolve(game)
      engine = Enjine::Engine.new(game.catalog, game.state) { nil }
      engine.gain_control_until_end_of_turn!(game.state.object(giant), 1, Enjine::Mechanics::EffectContext.new(1))
      expect(controller(game, giant)).to eq(1)
      engine.revert_temporary_control!
      expect(controller(game, giant)).to eq(1)
    end

    it "another player can be the one gaining control" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { U: 2 }) do
          hand "Gift of Burden"
          battlefield "Grizzly Bears"
          library "Forest", count: 3
        end
        player("bob") { library "Forest", count: 3 }
      end
      bears = obj_id(game, "Grizzly Bears")
      cast(game, "Gift of Burden", "player:bob", bears)
      resolve(game)
      expect(controller(game, bears)).to eq(1)
      expect(ids_in(game, "alice", :hand).size).to eq(2)
    end
  end

  describe "can't attack alone (CR 506.5, 508.1c)" do
    def board(*creatures)
      build_game do
        turn 3, active: "alice", step: :declare_attackers
        pending :declare_attackers, player: "alice"
        player("alice") do
          creatures.each { battlefield it }
          library "Forest", count: 3
        end
        player("bob") { library "Forest", count: 3 }
      end
    end

    it "isn't offered when nothing else could attack" do
      game = board("Timid Mastiff")
      expect(game.legal_options).to eq([{ type: "done" }])
    end

    it "a requirement to attack doesn't apply while obeying it would break the restriction (CR 508.1d)" do
      eager = { "name" => "Eager Pup", "mana_cost" => "{1}", "types" => ["creature"], "power" => 1, "toughness" => 1,
                "keywords" => %w[cant_attack_alone attacks_each_combat],
                "abilities" => [{ "triggered" => { "when" => { "attacks" => {} }, "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
      cat = catalog_with(eager)
      alone = build_game(cat) do
        turn 3, active: "alice", step: :declare_attackers
        pending :declare_attackers, player: "alice"
        player("alice") { battlefield "Eager Pup" }
        player("bob")
      end
      expect(alone.legal_options).to eq([{ type: "done" }])

      pair = build_game(cat) do
        turn 3, active: "alice", step: :declare_attackers
        pending :declare_attackers, player: "alice"
        player("alice") { battlefield "Eager Pup", "Grizzly Bears" }
        player("bob")
      end
      pup = obj_id(pair, "Eager Pup")
      pair.submit(type: "attack", object: pup, target: "player:bob")
      expect(pair.state.pending_triggers.size).to eq(1)
      pair.submit(type: "withdraw", object: pup)
      expect(pair.state.pending_triggers).to be_empty # that attack never happened
    end

    it "is offered with another possible attacker; done waits until it doesn't attack alone, or it's withdrawn" do
      game = board("Timid Mastiff", "Grizzly Bears")
      mastiff = obj_id(game, "Timid Mastiff")
      bears = obj_id(game, "Grizzly Bears")
      game.submit(type: "attack", object: mastiff, target: "player:bob")
      expect(game.legal_options).to contain_exactly({ type: "attack", object: bears, target: "player:bob" },
                                                    { type: "withdraw", object: mastiff })
      game.submit(type: "withdraw", object: mastiff)
      expect(game.state.attackers).to be_empty
      expect(game.legal_options).to include({ type: "done" })
      game.submit(type: "attack", object: mastiff, target: "player:bob")
      game.submit(type: "attack", object: bears, target: "player:bob")
      expect(game.state.attackers.keys).to contain_exactly(mastiff, bears)
      expect(game.pending_decision.kind).to eq("priority") # the declaration finished on its own
    end
  end

  describe "can't be blocked by (CR 509.1b)" do
    def blockers_board(attacker, *blockers)
      build_game do
        turn 3, active: "alice", step: :declare_attackers
        pending :declare_attackers, player: "alice"
        player("alice") do
          battlefield attacker
          library "Forest", count: 3
        end
        player("bob") do
          blockers.each { battlefield it }
          library "Forest", count: 3
        end
      end
    end

    it "creatures with power 2 or less can't block it; bigger ones can" do
      game = blockers_board("Stalking Brute", "Grizzly Bears", "Hill Giant")
      game.submit(type: "attack", object: obj_id(game, "Stalking Brute"), target: "player:bob")
      game.submit(type: "pass") until game.pending_decision.kind == "declare_blockers"
      blockers = game.legal_options.select { it[:type] == "block" }.map { it[:object] }
      expect(blockers).to eq([obj_id(game, "Hill Giant")])
    end

    it "artifact creatures can't block it" do
      game = blockers_board("Void Drifter", "Bastion Golem", "Craw Wurm")
      game.submit(type: "attack", object: obj_id(game, "Void Drifter"), target: "player:bob")
      game.submit(type: "pass") until game.pending_decision.kind == "declare_blockers"
      blockers = game.legal_options.select { it[:type] == "block" }.map { it[:object] }
      expect(blockers).to eq([obj_id(game, "Craw Wurm")])
    end
  end

  describe "can't be the target of abilities from artifact sources opponents control (CR 115.4)" do
    it "an artifact's ability can't target it; another source's ability and spells can" do
      game = build_game do
        turn 3, active: "bob", step: :precombat_main
        player("alice") { battlefield "Void Drifter" }
        player("bob", mana_pool: { R: 3 }) do
          battlefield "Arc Lantern", "Prodigal Pyromancer"
          battlefield "Survey Drone"
          hand "Lightning Bolt"
        end
      end
      drifter = obj_id(game, "Void Drifter")
      engine = Enjine::Engine.new(game.catalog, game.state) { nil }
      expect(engine.targetable?(drifter, 1, obj_id(game, "Arc Lantern"))).to be(false)
      expect(engine.targetable?(drifter, 1, obj_id(game, "Prodigal Pyromancer"))).to be(true)
      expect(engine.targetable?(drifter, 1)).to be(true)
      expect(engine.targetable?(drifter, 0, obj_id(game, "Arc Lantern"))).to be(true) # its controller isn't an opponent
      game.submit(type: "activate", object: obj_id(game, "Arc Lantern"), ability: "printed:0")
      game.submit(type: "x", value: 1) if game.pending_decision.kind == "choose_x"
      expect(game.legal_options.map { it[:target] }).not_to include(drifter)
      game.submit(type: "cancel")
      game.submit(type: "activate", object: obj_id(game, "Prodigal Pyromancer"), ability: "printed:0")
      expect(game.legal_options.map { it[:target] }).to include(drifter)
    end
  end

  describe "fight (CR 701.14) and bite" do
    def duel(card, mine, theirs)
      build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { G: 2 }) do
          hand card
          battlefield mine
          library "Forest", count: 3
        end
        player("bob") do
          battlefield theirs
          library "Forest", count: 3
        end
      end
    end

    it "each creature deals damage equal to its power to the other" do
      game = duel("Duel at Dawn", "Hill Giant", "Grizzly Bears")
      giant = obj_id(game, "Hill Giant")
      cast(game, "Duel at Dawn", giant, obj_id(game, "Grizzly Bears"))
      resolve(game)
      expect(ids_in(game, "bob", :graveyard).map { game.state.object(it).card }).to eq(["grizzly_bears"])
      expect(game.state.object(giant).damage).to eq(2)
    end

    it "neither deals damage if one is gone (CR 701.14b), and a creature fighting itself deals twice its power" do
      game = duel("Duel at Dawn", "Hill Giant", "Grizzly Bears")
      giant = obj_id(game, "Hill Giant")
      engine = Enjine::Engine.new(game.catalog, game.state) { nil }
      engine.fight!(giant, "nothing#1")
      expect(game.state.object(giant).damage).to eq(0)
      engine.fight!(giant, giant)
      expect(game.state.object(giant).damage).to eq(6)
    end

    it "bite: only the chosen creature deals damage" do
      game = duel("Pack Strike", "Hill Giant", "Craw Wurm")
      giant = obj_id(game, "Hill Giant")
      wurm = obj_id(game, "Craw Wurm")
      cast(game, "Pack Strike", giant, wurm)
      resolve(game)
      expect(game.state.object(wurm).damage).to eq(3)
      expect(game.state.object(giant).damage).to eq(0)
    end
  end

  describe "removing damage and counters (CR 120.6, 122.8)" do
    it "removes marked damage, some counters of a kind and all counters of another" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { W: 1 }) do
          hand "Mend Flesh"
          battlefield "Craw Wurm", damage: 1, counters: { "-1/-1" => 2, "stun" => 2 }
        end
        player("bob")
      end
      wurm = obj_id(game, "Craw Wurm")
      cast(game, "Mend Flesh", wurm)
      resolve(game)
      expect(game.state.object(wurm)).to have_attributes(damage: 0, counters: { "-1/-1" => 1, "stun" => 0 })
      engine = Enjine::Engine.new(game.catalog, game.state) { nil }
      engine.remove_all_counters!(game.state.object(wurm))
      expect(game.state.object(wurm).counters.values).to all(eq(0))
    end
  end
end
