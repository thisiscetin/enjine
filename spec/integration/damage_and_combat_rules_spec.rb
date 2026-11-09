# frozen_string_literal: true

RSpec.describe "Damage triggers, combat requirements, extra phases and replacements (CR 120, 500.8, 509, 510, 614)" do
  def creature(name, power, toughness, *abilities, keywords: [])
    { "name" => name, "mana_cost" => "{1}", "types" => ["creature"], "subtypes" => ["bear"], "power" => power,
      "toughness" => toughness, "keywords" => keywords, "abilities" => abilities }
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, who) = game.state.players[game.names.index(who)].life
  def id(game, name) = obj_id(game, name)

  def triggered(trigger, *effects) = { "triggered" => { "when" => trigger, "effects" => effects } }
  def gain(amount = 1) = { "gain_life" => { "amount" => amount, "to" => "you" } }

  let(:enrager) do
    creature("Enraged Hulk", 2, 6, triggered({ "dealt_damage" => {} },
                                             { "add_counters" => { "counter" => "+1/+1", "amount" => { "triggering" => "amount" },
                                                                   "to" => "self" } }))
  end
  let(:gloater) do
    creature("Smug Imp", 1, 1, triggered({ "dealt_damage" => { "player" => "opponent", "noncombat" => true } }, gain))
  end
  let(:sage) do
    creature("Burn Sage", 1, 1, triggered({ "deals_damage" => { "subject" => { "each" => "permanent", "controller" => "you" },
                                                                "to" => "opponent", "noncombat" => true } },
                                          { "draw" => { "amount" => { "triggering" => "amount" }, "to" => "you" } }))
  end
  let(:skyguard) do
    creature("Skyguard", 1, 3, triggered({ "blocks" => { "blocking" => { "creature" => { "keywords" => ["flying"] } } } },
                                         { "pump" => { "power" => 5, "toughness" => 0, "to" => "self" } }), keywords: ["reach"])
  end
  let(:lure) { creature("Lure Brute", 4, 2, keywords: ["must_be_blocked"]) }
  let(:wall) { creature("Tall Wall", 0, 5, keywords: ["assigns_damage_by_toughness"]) }
  let(:warleader) do
    creature("Warleader", 2, 2, triggered({ "attacks" => {} },
                                          { "additional_phases" => { "phases" => ["combat"], "if" => { "first_combat_phase" => true } } }))
  end
  let(:executioner) do
    creature("Grave Warden", 1, 1, { "exile_if_dies" => { "affects" => { "each" => "creature", "controller" => "opponent" } } })
  end
  let(:doubler) do
    creature("Token Twin", 1, 1, "double_tokens",
             triggered({ "enters" => {} }, { "create_token" => { "token" => "Treasure", "to" => "you" } }))
  end
  let(:plunge) do
    { "name" => "Plunge", "mana_cost" => "{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => ["creature"],
                                     "effects" => [{ "deal_damage" => { "amount" => 6, "to" => { "target" => 0 } } },
                                                   { "gain_life" => { "amount" => { "this_way" => 0 }, "to" => "you" } }] } }] }
  end
  let(:catalog) { catalog_with(enrager, gloater, sage, skyguard, lure, wall, warleader, executioner, doubler, plunge) }

  def board(alice: [], bob: [], hand: [], step: :precombat_main)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice") do
        battlefield(*alice) unless alice.empty?
        hand(*hand) unless hand.empty?
        battlefield "Mountain"
        library "Forest", count: 5
      end
      player("bob") do
        battlefield(*bob) unless bob.empty?
        library "Forest", count: 5
      end
    end
  end

  def resolve_triggers(game)
    while game.state.stack.any? || game.state.pending_triggers.any?
      game.submit(game.pending_decision.kind == "priority" ? { type: "pass" } : game.legal_options.first)
    end
  end

  describe "damage triggers (CR 120.3, 603.2)" do
    it "\"is dealt damage\" sees the damage dealt to it, and \"that much\" (CR 120.3)" do
      game = board(alice: ["Enraged Hulk"])
      engine(game).deal_damage!(nil, id(game, "Enraged Hulk"), 2)
      resolve_triggers(game)
      expect(game.state.object(id(game, "Enraged Hulk")).counters).to eq("+1/+1" => 2)
    end

    it "an opponent dealt noncombat damage, and noncombat damage dealt to an opponent (CR 120.2b)" do
      game = board(alice: ["Smug Imp", "Burn Sage"])
      imp = id(game, "Smug Imp")
      engine(game).deal_damage!(imp, "player:bob", 2, combat: true)
      expect(game.state.pending_triggers).to be_empty
      engine(game).deal_damage!(imp, "player:bob", 2)
      engine(game).deal_damage!(imp, "player:alice", 1) # not an opponent
      expect(game.state.pending_triggers.size).to eq(2)
      resolve_triggers(game)
      expect(life(game, "alice")).to eq(20) # 19 + 1
      expect(ids_in(game, "alice", :hand).size).to eq(2)
      expect(engine(game).turn_log(1)["noncombat_damage"]).to eq(2)
    end

    it "\"blocks a creature with flying\" (CR 509.3b, 509.3f)" do
      game = board(alice: ["Cloud Kite"], bob: ["Skyguard"], step: :beginning_of_combat)
      pass_both(game)
      game.submit(type: "attack", object: id(game, "Cloud Kite"), target: "player:bob")
      pass_both(game)
      game.submit(type: "block", object: id(game, "Skyguard"), attacker: id(game, "Cloud Kite"))
      expect(game.state.pending_triggers.size + game.state.stack.size).to eq(1)
    end
  end

  describe "combat (CR 509.1c, 510.1a)" do
    it "an attacker that must be blocked if able: done is withheld until a creature blocks it (CR 509.1c)" do
      game = board(alice: ["Lure Brute", "Grizzly Bears"], bob: ["Hill Giant"], step: :beginning_of_combat)
      pass_both(game)
      brute = id(game, "Lure Brute")
      bears = id(game, "Grizzly Bears")
      giant = id(game, "Hill Giant")
      game.submit(type: "attack", object: brute, target: "player:bob")
      game.submit(type: "attack", object: bears, target: "player:bob")
      pass_both(game)
      expect(game.legal_options).not_to include(type: "done")
      game.submit(type: "block", object: giant, attacker: bears)
      expect(game.legal_options).to eq([{ type: "unblock", object: giant }])
      game.submit(type: "unblock", object: giant)
      game.submit(type: "block", object: giant, attacker: brute)
      expect(game.state.blockers).to eq(giant => brute)
    end

    it "assigns combat damage equal to toughness when it's greater than power (CR 510.1a)" do
      game = board(alice: ["Tall Wall"], step: :beginning_of_combat)
      pass_both(game)
      game.submit(type: "attack", object: id(game, "Tall Wall"), target: "player:bob")
      skip_to(game, :end_of_combat)
      expect(life(game, "bob")).to eq(15)
    end
  end

  describe "additional combat phases (CR 500.8)" do
    it "adds a combat phase after this one, only from the first combat phase" do
      game = board(alice: ["Warleader"])
      warleader = id(game, "Warleader")
      pass_both(game, 2) # into the first combat phase
      game.submit(type: "attack", object: warleader, target: "player:bob")
      resolve_triggers(game)
      expect(game.state.extra_phases["pending"]).to eq([{ "after" => "combat", "phases" => ["combat"] }])
      skip_to(game, :end_of_combat)
      pass_both(game)
      expect(game.step).to eq(:beginning_of_combat) # the added combat phase, before the main phase
      game = Enjine::Game.import(game.export, catalog: catalog)
      engine(game).untap!(game.state.object(warleader))
      pass_both(game)
      game.submit(type: "attack", object: warleader, target: "player:bob")
      resolve_triggers(game)
      expect(game.state.extra_phases["pending"]).to be_empty # not the first combat phase
      skip_to(game, :postcombat_main)
      expect(life(game, "bob")).to eq(16)
    end

    it "adds phases after a main phase, most recently created first, then the turn goes on" do
      game = board
      engine(game).add_phases!(%w[combat main])
      pass_both(game)
      expect(game.step).to eq(:beginning_of_combat)
      skip_to(game, :postcombat_main)
      pass_both(game)
      expect(game.step).to eq(:beginning_of_combat) # the turn's own combat phase
      skip_to(game, :postcombat_main)
      pass_both(game)
      expect(game.step).to eq(:end)
    end
  end

  describe "excess damage (CR 120.4a, 120.10)" do
    it "is what {\"this_way\": n} of a deal_damage effect reads" do
      game = board(bob: ["Grizzly Bears"], hand: ["Plunge"])
      game.submit(type: "cast", object: obj_id(game, "Plunge", zone: :hand, player: "alice"))
      game.submit(type: "target", target: id(game, "Grizzly Bears"))
      while game.pending_decision&.kind == "pay_cost"
        game.submit(game.legal_options.find { %w[pay_mana activate_mana].include?(it[:type]) })
      end
      pass_both(game)
      expect(life(game, "alice")).to eq(24) # 6 to a 2/2: 4 excess
    end

    it "counts marked damage and deathtouch (CR 120.4a)" do
      game = board(bob: ["Hill Giant"])
      giant = id(game, "Hill Giant")
      game.state.object(giant).damage = 1
      expect(engine(game).lethal_damage(nil, giant)).to eq(2)
      expect(engine(game).lethal_damage(nil, "player:bob")).to be_nil
      expect(engine(game).excess_damage(2, 5)).to eq(3)
    end
  end

  describe "replacements (CR 614.1a)" do
    it "exiles an opponent's creature that would die" do
      game = board(alice: ["Grave Warden"], bob: ["Grizzly Bears"])
      engine(game).deal_damage!(nil, id(game, "Grizzly Bears"), 5)
      pass_both(game)
      expect(game.state.exile.size).to eq(1)
      expect(ids_in(game, "bob", :graveyard)).to be_empty
    end

    it "creates twice that many tokens, four times with two (CR 614.5)" do
      game = board(alice: ["Token Twin"])
      treasure = game.catalog.find { it.name == "Treasure" }
      engine(game).create_token!(treasure, 0)
      expect(game.state.battlefield.count { game.state.object(it).card == treasure.id }).to eq(2)
      engine(game).create_token!(treasure, 1) # bob's tokens aren't doubled
      expect(game.state.battlefield.count { game.state.object(it).card == treasure.id }).to eq(3)
      game = board(alice: ["Token Twin", "Token Twin"])
      engine(game).create_token!(treasure, 0)
      expect(game.state.battlefield.count { game.state.object(it).card == treasure.id }).to eq(4)
    end
  end
end
