# frozen_string_literal: true

RSpec.describe "Player rules, game end and extra turns (CR 104, 402.2, 500.7, 615, 702.11c)" do
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

  def life(game, who) = game.state.players[game.names.index(who)].life

  describe "hexproof and damage prevention for a player (CR 702.11c, 615.1)" do
    def warded
      build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { W: 2 }) do
          hand "Last Stand Ward"
          battlefield "Grizzly Bears"
          library "Forest", count: 3
        end
        player("bob", mana_pool: { R: 2 }) do
          hand "Lightning Bolt"
          battlefield "Prodigal Pyromancer"
          library "Forest", count: 3
        end
      end
    end

    it "opponents can't target the player; damage to them is prevented; the spell exiles itself" do
      game = warded
      cast(game, "Last Stand Ward")
      resolve(game)
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["last_stand_ward"])
      expect(ids_in(game, "alice", :graveyard)).to be_empty
      game.submit(type: "pass") # bob gets priority
      game.submit(type: "cast", object: obj_id(game, "Lightning Bolt", zone: :hand, player: "bob"))
      expect(game.legal_options.map { it[:target] }).not_to include("player:alice")
      expect(game.legal_options.map { it[:target] }).to include("player:bob")
    end

    it "its own controller can still target them, and noncombat damage from any source is prevented" do
      game = warded
      cast(game, "Last Stand Ward")
      resolve(game)
      expect(game.state.effects.map { it["rule"] }.compact).to eq(%w[hexproof prevent_all_damage])
      bolt = { "name" => "Self Bolt", "mana_cost" => "{R}", "types" => ["instant"],
               "abilities" => [{ "spell" => { "effects" => [{ "deal_damage" => { "amount" => 3, "to" => "you" } }] } }] }
      copy = Enjine::Game.import(game.export, catalog: catalog_with(bolt))
      expect(copy.state.to_h).to eq(game.state.to_h)
      before = life(game, "alice")
      expect(Enjine::Engine.new(game.catalog, game.state) { nil }.targetable?("player:alice", 0)).to be(true)
      expect(Enjine::Engine.new(game.catalog, game.state) { nil }.targetable?("player:alice", 1)).to be(false)
      expect(Enjine::Engine.new(game.catalog, game.state) { nil }.deal_damage!(nil, "player:alice", 3)).to eq(0)
      expect(life(game, "alice")).to eq(before)
    end

    it "the effects end at cleanup" do
      game = warded
      cast(game, "Last Stand Ward")
      resolve(game)
      skip_to(game, :upkeep, turn: 4)
      expect(game.state.effects).to be_empty
    end
  end

  describe "no maximum hand size (CR 402.2, 514.1)" do
    it "lasts until its controller's next turn: no discard in this cleanup" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { U: 4 }) do
          hand "Boundless Study"
          hand "Forest", count: 7
          library "Forest", count: 10
        end
        player("bob") { library "Forest", count: 10 }
      end
      cast(game, "Boundless Study")
      resolve(game)
      expect(ids_in(game, "alice", :hand).size).to eq(10)
      skip_to(game, :upkeep, turn: 4)
      expect(ids_in(game, "alice", :hand).size).to eq(10)
      expect(game.state.effects.map { it["duration"] }).to eq(["until_your_next_turn"])
      skip_to(game, :upkeep, turn: 5)
      expect(game.state.effects).to be_empty
    end

    def big_hand(card)
      build_game do
        turn 3, active: "alice", step: :end
        player("alice") do
          battlefield card if card
          hand "Forest", count: 9
          library "Forest", count: 10
        end
        player("bob") { library "Forest", count: 10 }
      end
    end

    def monitored(game)
      monitor = Enjine::RulesMonitor.new(game)
      100.times do
        break if game.turn == 4 && game.step == :upkeep

        types = option_types(game)
        monitor.check!(game.submit(types.include?("pass") ? { type: "pass" } : game.legal_options.first))
      end
      monitor
    end

    it "a permanent's static ability; the rules monitor agrees, and catches a missing discard otherwise" do
      keeper = { "name" => "Hoard Keeper", "mana_cost" => "{1}", "types" => ["artifact"],
                 "abilities" => [{ "player_rule" => { "rule" => "no_max_hand_size" } }] }
      game = build_game(catalog_with(keeper)) do
        turn 3, active: "alice", step: :end
        player("alice") do
          battlefield "Hoard Keeper"
          hand "Forest", count: 9
          library "Forest", count: 10
        end
        player("bob") { library "Forest", count: 10 }
      end
      expect(monitored(game).findings).to be_empty
      expect(ids_in(game, "alice", :hand).size).to eq(9)
      expect(monitored(big_hand(nil)).findings).to be_empty # discards to seven

      allow_any_instance_of(Enjine::Engine).to receive(:max_hand_size).and_return(nil) # rubocop:disable RSpec/AnyInstance
      expect(monitored(big_hand(nil)).findings.map(&:rule)).to include("514.1")
    end
  end

  describe "a player can't attack (CR 508.1c)" do
    it "skips the declaration for that player this turn" do
      game = build_game do
        turn 3, active: "bob", step: :upkeep
        player("alice", mana_pool: { W: 2 }) do
          hand "Truce Banner"
          library "Forest", count: 3
        end
        player("bob") do
          battlefield "Grizzly Bears"
          library "Forest", count: 3
        end
      end
      game.submit(type: "pass") # bob passes, alice acts in bob's upkeep
      cast(game, "Truce Banner")
      resolve(game)
      skip_to(game, :declare_attackers)
      expect(game.state.attackers).to be_empty
      expect(game.state.step).to eq(:declare_attackers)
    end
  end

  describe "not losing for 0 or less life (CR 704.5a)" do
    it "a player at 0 life stays in the game while the permanent is on the battlefield" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", life: 1) do
          battlefield "Undying Regent"
          library "Forest", count: 5
        end
        player("bob", mana_pool: { R: 1 }) { hand "Lightning Bolt" }
      end
      game.submit(type: "pass")
      cast(game, "Lightning Bolt", "player:alice", player: "bob")
      resolve(game)
      expect(life(game, "alice")).to eq(-2)
      expect(game.over?).to be(false)
    end

    it "without it, the player loses" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", life: 1) { library "Forest", count: 5 }
        player("bob", mana_pool: { R: 1 }) { hand "Lightning Bolt" }
      end
      game.submit(type: "pass")
      cast(game, "Lightning Bolt", "player:alice", player: "bob")
      resolve(game)
      expect(game.result).to eq("winner" => "bob", "reason" => "life")
    end
  end

  describe "players can't sacrifice matching permanents (CR 701.21a, 614.17b)" do
    it "a Treasure's mana ability can't be activated, so it can't pay for spells" do
      game = build_game do
        turn 3, active: "alice", step: :end
        player("alice") do
          battlefield "Hoarding Broker"
          hand "Lightning Bolt"
          library "Forest", count: 5
        end
        player("bob") { library "Forest", count: 5 }
      end
      skip_to(game, :upkeep, turn: 4)
      resolve(game)
      treasure = game.state.battlefield.find { game.catalog.fetch(game.state.object(it).card).name == "Treasure" }
      expect(treasure).not_to be_nil
      engine = Enjine::Engine.new(game.catalog, game.state) { nil }
      expect(engine.can_sacrifice?(game.state.object(treasure), 0)).to be(false)
      expect(engine.can_sacrifice?(game.state.object(obj_id(game, "Hoarding Broker")), 0)).to be(true)
      expect(engine.can_sacrifice?(game.state.object(treasure), 1)).to be(false) # not bob's to sacrifice
    end

    it "only its controller is affected" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice") { battlefield "Hoarding Broker" }
        player("bob") { battlefield "Brasswork Cudgel" }
      end
      engine = Enjine::Engine.new(game.catalog, game.state) { nil }
      expect(engine.can_sacrifice?(game.state.object(obj_id(game, "Brasswork Cudgel")), 1)).to be(true)
    end
  end

  describe "winning and losing by an effect (CR 104.2b, 104.3e)" do
    def wager(alice_life:, bob_life:)
      build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", life: alice_life, mana_pool: { B: 5 }) do
          hand "Final Wager"
          library "Forest", count: 3
        end
        player("bob", life: bob_life) { library "Forest", count: 3 }
      end
    end

    it "the player wins immediately; the rest of the spell doesn't happen" do
      game = wager(alice_life: 20, bob_life: 5)
      cast(game, "Final Wager")
      resolve(game)
      expect(game.result).to eq("winner" => "alice", "reason" => "opponent_won")
      expect(ids_in(game, "alice", :hand)).to be_empty # the draw after it never happened
      expect(Enjine::Snapshot.validate(game.state.to_h, game.catalog)).to be_empty
    end

    it "the player loses" do
      game = wager(alice_life: 3, bob_life: 20)
      cast(game, "Final Wager")
      resolve(game)
      expect(game.result).to eq("winner" => "bob", "reason" => "effect")
    end

    it "neither condition: the spell continues" do
      game = wager(alice_life: 20, bob_life: 20)
      cast(game, "Final Wager")
      resolve(game)
      expect(game.over?).to be(false)
      expect(ids_in(game, "alice", :hand).size).to eq(1)
    end
  end

  describe "extra turns (CR 500.7)" do
    def sloop_game
      build_game do
        turn 3, active: "alice", step: :declare_attackers
        pending :declare_attackers, player: "alice"
        player("alice") do
          battlefield "Temporal Sloop"
          library "Forest", count: 10
        end
        player("bob") { library "Forest", count: 10 }
      end
    end

    def to_attack(game, turn)
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers" && game.turn == turn
    end

    it "the player takes the next turn; only once per game with the 'haven't begun one' condition" do
      game = sloop_game
      game.submit(type: "attack", object: obj_id(game, "Temporal Sloop"), target: "player:bob")
      skip_to(game, :end_of_combat)
      expect(game.state.extra_turns["queue"]).to eq([0])
      copy = Enjine::Game.import(game.export, catalog: game.catalog)
      expect(copy.state.extra_turns).to eq(game.state.extra_turns)
      skip_to(game, :upkeep, turn: 4)
      expect(game.state.active).to eq(0)
      expect(game.state.extra_turns).to eq("queue" => [], "begun" => [0])
      to_attack(game, 4)
      game.submit(type: "attack", object: obj_id(game, "Temporal Sloop"), target: "player:bob")
      skip_to(game, :end, turn: 4)
      expect(life(game, "bob")).to eq(14)
      expect(game.state.extra_turns["queue"]).to be_empty
      skip_to(game, :upkeep, turn: 5)
      expect(game.state.active).to eq(1)
    end

    it "snapshot validation rejects a malformed extra_turns field" do
      data = sloop_game.state.to_h.merge("extra_turns" => { "queue" => [3] })
      expect(Enjine::Snapshot.validate(data, core_catalog)).to include(a_string_matching(/extra_turns: must be/))
    end
  end
end
