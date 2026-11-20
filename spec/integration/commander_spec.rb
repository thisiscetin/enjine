# frozen_string_literal: true

RSpec.describe "Duel Commander (CR 903)" do
  let(:warden) do
    { "name" => "Test Warden", "mana_cost" => "{2}{G}", "types" => ["creature"], "supertypes" => ["legendary"],
      "subtypes" => ["elf"], "power" => 3, "toughness" => 3 }
  end
  let(:anthem_warden) do
    { "name" => "Anthem Warden", "mana_cost" => "{1}{G}", "types" => ["creature"], "supertypes" => ["legendary"],
      "power" => 1, "toughness" => 1,
      "abilities" => [{ "static" => { "affects" => { "each" => { "creature" => {} }, "controller" => "you", "other" => true },
                                      "pump" => { "power" => 1, "toughness" => 1 } } }] }
  end
  let(:death_warden) do
    { "name" => "Death Warden", "mana_cost" => "{1}{B}", "types" => ["creature"], "supertypes" => ["legendary"],
      "power" => 2, "toughness" => 2,
      "abilities" => [{ "triggered" => { "when" => { "dies" => { "subject" => "self" } },
                                         "effects" => [{ "gain_life" => { "amount" => 2 } }] } }] }
  end
  let(:unsummon) do
    { "name" => "Test Unsummon", "mana_cost" => "{U}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [{ "return_to_hand" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:test_exile) do
    { "name" => "Test Exile", "mana_cost" => "{W}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [{ "exile" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:catalog) { catalog_with(warden, anthem_warden, death_warden, unsummon, test_exile) }

  def engine(game) = game.instance_variable_get(:@engine)
  def commander_id(game, name = "test_warden") = game.state.command.find { game.state.object(it).card == name }
  def zone_of(game, id) = game.state.objects[id]&.zone

  # alice has her commander in the command zone and mana; bob has a Grizzly Bears.
  def board(commander: warden["name"], mana: { G: 3 }, casts: 0, **zones)
    build_game(catalog) do
      duel_commander
      turn 3, active: "alice", step: :precombat_main
      player("alice", life: 40, mana_pool: mana, commander_casts: casts) do
        commander commander, **zones.slice(:zone)
        library "Forest", count: 10
      end
      player("bob", life: 40) do
        commander "Anthem Warden"
        battlefield "Grizzly Bears"
        library "Forest", count: 10
      end
    end
  end

  def pay(game)
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
  end

  def cast_commander(game)
    game.submit(type: "cast", object: commander_id(game), via: "command")
    pay(game)
    game.submit(type: "pass") until game.state.stack.empty?
  end

  describe "game setup (CR 903.6, 903.7)" do
    def deck_for(commander, lands: "Forest", filler: 99)
      { "cards" => CardFixtures.cards + [warden], "main" => [{ "card" => lands, "count" => filler }], "commander" => commander }
    end

    let(:players) { %w[alice bob].map { Enjine::Player.new(name: it, deck: deck_for("Test Warden")) } }
    let(:game) { Enjine::Setup.new(*players, format: :duel_commander).new_game(seed: 5) }

    it "puts each commander in the command zone, starts at 40 life and keeps it out of the library" do
      through_pregame(game)
      expect(game.state.command.map { game.state.object(it).card }).to eq(%w[test_warden test_warden])
      expect(game.state.players.map(&:life)).to eq([40, 40])
      expect(game.state.players.map { it.hand.size + it.library.size }).to eq([99, 99])
      expect(game.state.players.map { it.hand.size }).to include(7)
    end

    it "shows the command zone, the commander and its tax to everyone" do
      through_pregame(game)
      view = game.view_for("alice")
      expect(view["command"].map { it["name"] }).to eq(["Test Warden", "Test Warden"])
      expect(view["players"].map { it.values_at("commander", "commander_tax", "commander_damage") })
        .to eq([["Test Warden", 0, {}]] * 2)
    end

    it "restarts as the same Commander game" do
      through_pregame(game)
      game.restart(seed: 9)
      expect(game.state.players.map(&:life)).to eq([40, 40])
      expect(game.state.command.size).to eq(2)
    end

    it "is an ordinary game without a format" do
      plain = Enjine::Setup.new(*%w[a b].map { Enjine::Player.new(name: it, deck: basics_deck) }).new_game(seed: 1)
      expect([plain.state.command, plain.state.players.map(&:life)]).to eq([[], [20, 20]])
      expect(plain.view_for("a")["players"].first.keys).not_to include("commander")
    end

    it "round-trips through a snapshot" do
      through_pregame(game)
      copy = Enjine::Game.import(game.export, catalog: game.catalog)
      expect(copy.state.to_h).to eq(game.state.to_h)
      expect(copy.state.format).to eq(Enjine::Format::DUEL_COMMANDER)
    end
  end

  describe "the commander is a card, not a flag (CR 903.3)" do
    it "is the owner's own card, whatever zone it is in" do
      game = board(zone: :graveyard)
      id = game.state.players[0].graveyard.first
      expect(engine(game).commander?(game.state.object(id))).to be(true)
    end

    it "is not a card the opponent owns with the same name" do
      game = build_game(catalog) do
        duel_commander
        player("alice", life: 40) do
          commander "Test Warden"
          library "Forest", count: 5
        end
        player("bob", life: 40) do
          commander "Anthem Warden"
          battlefield "Test Warden"
          library "Forest", count: 5
        end
      end
      expect(engine(game).commander?(game.state.object(game.state.battlefield.first))).to be(false)
      expect(engine(game).commander?(game.state.object(game.state.command.first))).to be(true)
    end

    it "is not a token copy of it" do
      game = board
      token = engine(game).create_token_copy!(["test_warden", {}], 0)
      expect(engine(game).commander?(token)).to be(false)
    end

    it "does nothing from the command zone (CR 113.6)" do
      game = build_game(catalog) do
        duel_commander
        player("alice", life: 40) do
          commander "Anthem Warden"
          battlefield "Grizzly Bears"
          library "Forest", count: 5
        end
        player("bob", life: 40) do
          commander "Test Warden"
          library "Forest", count: 5
        end
      end
      bears = game.state.battlefield.first
      expect(engine(game).power(game.state.object(bears))).to eq(2)
    end
  end

  describe "casting from the command zone (CR 903.8)" do
    it "offers the commander as a cast option at sorcery speed" do
      game = board
      expect(game.legal_options).to include({ type: "cast", object: commander_id(game), via: "command" })
    end

    it "costs {2} more for each earlier cast from the command zone" do
      game = board(mana: { G: 1, C: 2 })
      cast_commander(game) # {2}{G}
      id = game.state.battlefield.find { game.state.object(it).card == "test_warden" }
      expect(engine(game).commander_casts(0)).to eq(1)
      engine(game).move!(id, :command, reason: "test")
      game.state.players[0].mana_pool = Enjine::Mana.empty_pool.merge(G: 1, C: 4)
      game.state.players[0].mana_pool[:C] = 4
      cast_commander(game)
      expect(game.state.players[0].mana_pool.values.sum).to eq(0) # {4}{G}
      expect(engine(game).commander_tax(0)).to eq(4)
    end

    it "is not offered without enough mana for the tax" do
      expect(board(mana: { G: 4 }, casts: 1).legal_options.map { it[:via] }).not_to include("command") # {4}{G}
      expect(board(mana: { G: 5 }, casts: 1).legal_options.map { it[:via] }).to include("command")
    end

    it "doesn't count a cast that was cancelled" do
      game = board
      id = commander_id(game)
      game.submit(type: "cast", object: id, via: "command")
      game.submit(type: "cancel")
      expect([engine(game).commander_casts(0), game.state.command.include?(id), game.pending_decision.kind])
        .to eq([0, true, "priority"])
    end
  end

  # bob, the active player, casts `spell` at alice's commander on the battlefield.
  def hit_commander(spell, mana, commander: warden["name"])
    game = build_game(catalog) do
      duel_commander
      turn 3, active: "bob", step: :precombat_main
      player("alice", life: 40) do
        commander commander, zone: :battlefield
        library "Forest", count: 10
      end
      player("bob", life: 40, mana_pool: mana) do
        commander "Anthem Warden"
        hand spell
        library "Forest", count: 10
      end
    end
    game.submit(type: "cast", object: obj_id(game, spell, zone: :hand, player: "bob"))
    game.submit(type: "target", target: game.state.battlefield.first)
    pay(game)
    game.submit(type: "pass") until game.pending_decision.kind != "priority" || game.state.stack.empty?
    game
  end

  describe "returning to the command zone (CR 903.9)" do
    it "asks the owner when the commander dies (903.9a) and puts it there on a yes" do
      game = hit_commander("Lightning Bolt", { R: 1 })
      expect([game.pending_decision.kind, game.pending_decision.player]).to eq(%w[commander_zone alice])
      game.submit(game.legal_options.find { it[:type] == "command" })
      expect(game.state.command.map { game.state.object(it).card }).to include("test_warden")
      expect(game.state.players[0].graveyard).to be_empty
      expect(game.pending_decision.kind).to eq("priority")
    end

    it "leaves it in the graveyard on a no, and doesn't ask again" do
      game = hit_commander("Lightning Bolt", { R: 1 })
      game.submit(game.legal_options.find { it[:type] == "stay" })
      expect(game.state.players[0].graveyard.size).to eq(1)
      expect(game.pending_decision.kind).to eq("priority")
      game.submit(type: "pass")
      expect(game.pending_decision.kind).not_to eq("commander_zone")
    end

    it "asks when the commander is exiled (903.9a)" do
      game = hit_commander("Test Exile", { W: 1 })
      expect(game.pending_decision.kind).to eq("commander_zone")
      game.submit(game.legal_options.find { it[:type] == "command" })
      expect(game.state.exile).to be_empty
    end

    it "asks when the commander would go to its owner's hand (903.9b)" do
      game = hit_commander("Test Unsummon", { U: 1 })
      expect(game.pending_decision.kind).to eq("commander_zone")
      game.submit(game.legal_options.find { it[:type] == "command" })
      expect(game.state.players[0].hand).to be_empty
      expect(game.state.command.map { game.state.object(it).card }).to include("test_warden")
    end

    it "lets a commander return to hand without tax when its owner declines (903.9b)" do
      game = hit_commander("Test Unsummon", { U: 1 })
      game.submit(game.legal_options.find { it[:type] == "stay" })
      expect(game.state.players[0].hand.size).to eq(1)
    end

    it "still triggers the commander's own dies ability (CR 603.10a)" do
      game = hit_commander("Lightning Bolt", { R: 1 }, commander: "Death Warden")
      game.submit(game.legal_options.find { it[:type] == "command" })
      game.submit(type: "pass") until game.state.stack.empty?
      expect(game.state.players[0].life).to eq(42)
      expect(game.state.command.map { game.state.object(it).card }).to include("death_warden")
    end

    it "doesn't count a return to the command zone as a cast" do
      game = hit_commander("Lightning Bolt", { R: 1 })
      game.submit(game.legal_options.find { it[:type] == "command" })
      expect(engine(game).commander_casts(0)).to eq(0)
    end
  end

  describe "21 combat damage from one commander (CR 903.10a)" do
    def duel(life: 40)
      build_game(catalog) do
        duel_commander
        turn 3, active: "alice", step: :precombat_main
        player("alice", life: life) do
          commander "Test Warden", zone: :battlefield
          library "Forest", count: 10
        end
        player("bob", life: life) do
          commander "Anthem Warden"
          library "Forest", count: 10
        end
      end
    end

    def hit(game, damage, combat: true, to: "player:bob", from: game.state.battlefield.first)
      engine(game).deal_damage!(from, to, damage, combat: combat)
      engine(game).check_state_based_actions!
    end

    it "loses the game at 21" do
      game = duel
      hit(game, 20)
      expect(game.over?).to be(false)
      expect(game.state.players[1].commander_damage).to eq("test_warden" => 20)
      hit(game, 1)
      expect([game.result["winner"], game.result["reason"]]).to eq(%w[alice commander_damage])
    end

    it "adds up over several combats and zone changes" do
      game = duel
      hit(game, 10)
      id = game.state.battlefield.first
      engine(game).move!(id, :command, reason: "test")
      engine(game).move!(game.state.command.find { game.state.object(it).card == "test_warden" }, :battlefield, reason: "test")
      hit(game, 11)
      expect(game.over?).to be(true)
    end

    it "ignores damage that isn't combat damage" do
      game = duel
      hit(game, 25, combat: false)
      expect([game.over?, game.state.players[1].commander_damage]).to eq([false, nil])
    end

    it "ignores combat damage from other creatures" do
      game = build_game(catalog) do
        duel_commander
        player("alice", life: 40) do
          commander "Test Warden"
          battlefield "Grizzly Bears"
          library "Forest", count: 10
        end
        player("bob", life: 40) do
          commander "Anthem Warden"
          library "Forest", count: 10
        end
      end
      hit(game, 30)
      expect(game.over?).to be(false)
    end

    it "counts a commander its owner doesn't control, dealt to its owner" do
      game = duel
      engine(game).object(game.state.battlefield.first).controller = 1
      hit(game, 21, to: "player:alice")
      expect([game.result["winner"], game.result["reason"]]).to eq(%w[bob commander_damage])
    end

    it "keeps each commander's damage apart" do
      game = duel
      hit(game, 20)
      expect(game.state.players[1].commander_damage.keys).to eq(["test_warden"])
      expect(game.view_for("bob")["players"][1]["commander_damage"]).to eq("Test Warden" => 20)
    end
  end

  describe "the text interface" do
    def text(game) = Enjine::CLI::Text.new(game)

    it "words the 903.9 choice and what comes of it" do
      game = hit_commander("Lightning Bolt", { R: 1 })
      view = text(game)
      expect(view.decision(game.pending_decision)).to include("ALICE must act: commander zone", "(your commander)")
      expect(game.legal_options.map { view.option(it) }).to eq(["Put Test Warden into the command zone", "Leave Test Warden where it is"])
      entry = game.submit(game.legal_options.first)
      expect(view.events(entry.events.map(&:to_h))).to include("alice puts Test Warden into the command zone")
    end

    it "shows the commander, its tax and the cast from the command zone" do
      game = board(mana: { G: 5 }, casts: 1)
      cast = game.legal_options.find { it[:via] == "command" }
      expect(text(game).option(cast)).to eq("Cast Test Warden {2}{G} from the command zone (+{2})")
      expect(text(board).option(board.legal_options.find { it[:via] == "command" })).to eq("Cast Test Warden {2}{G} from the command zone")
      expect(text(game).board(game.view_for("alice"))).to include("Commander: Test Warden [", "in the command zone · tax {2}")
    end

    it "shows commander damage taken" do
      game = board
      game.state.players[0].commander_damage = { "anthem_warden" => 9 }
      expect(text(game).board(game.view_for("alice"))).to include("commander damage taken: 9 from Anthem Warden")
    end
  end

  describe "snapshots" do
    it "round-trip a game with casts, damage and a pending 903.9 choice" do
      game = hit_commander("Lightning Bolt", { R: 1 })
      game.state.players[0].commander_casts = 2
      game.state.players[0].commander_damage = { "anthem_warden" => 7 }
      copy = Enjine::Game.import(game.export, catalog: game.catalog)
      expect(copy.state.to_h).to eq(game.state.to_h)
      expect(copy.pending_decision.kind).to eq("commander_zone")
    end

    it "reject a stranger in the command zone" do
      data = board.state.to_h
      data["commanders"] = %w[grizzly_bears anthem_warden] # alice's commander is a different card
      expect(Enjine::Snapshot.validate(data, catalog).join).to include("only emblems and its owner's commander")
    end

    it "reject commander data in a constructed game, and a Commander game without commanders" do
      data = board.state.to_h
      expect(Enjine::Snapshot.validate(data.merge("format" => "constructed"), catalog).join).to include("only a Commander game has them")
      expect(Enjine::Snapshot.validate(data.merge("commanders" => [nil, nil]), catalog).join).to include("has one each")
      expect(Enjine::Snapshot.validate(data.merge("format" => "brawl"), catalog).join).to include("unknown")
    end
  end
end
