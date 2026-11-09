# frozen_string_literal: true

# Start your engines!, speed and max speed (CR 702.178, 702.179, 704.5aa) and exhaust (CR 702.177).
RSpec.describe "Speed, max speed and exhaust" do
  let(:hustler) do
    { "name" => "Pitstop Hustler", "mana_cost" => "{1}{R}", "types" => ["creature"], "subtypes" => ["goblin"],
      "power" => 2, "toughness" => 2, "keywords" => ["start_your_engines"],
      "abilities" => [{ "max_speed" => { "keywords" => ["double_strike"] } },
                      { "max_speed" => { "abilities" => [
                        { "activated" => { "cost" => [{ "mana" => "{1}" }, "exile_self_from_graveyard"],
                                           "effects" => [{ "draw" => { "amount" => 1 } }] } }
                      ] } }] }
  end
  let(:gauge) do
    { "name" => "Speed Dial", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "activated" => { "cost" => ["tap"],
                                         "effects" => [{ "gain_life" => { "amount" => { "speed" => "you" } } }] } },
                      { "static" => { "affects" => { "each" => "creature", "controller" => "you" }, "if" => { "max_speed" => true },
                                      "pump" => { "power" => 1, "toughness" => 0 } } }] }
  end
  let(:mender) do
    { "name" => "Gearbreak Tinker", "mana_cost" => "{1}{G}", "types" => ["creature"], "subtypes" => ["goblin"],
      "power" => 1, "toughness" => 1,
      "abilities" => [{ "activated" => { "exhaust" => true, "cost" => [{ "mana" => "{1}" }],
                                         "effects" => [{ "add_counters" => { "counter" => "+1/+1", "amount" => 2, "to" => "self" } }] } },
                      { "triggered" => { "when" => { "activates_ability" => { "exhaust" => true } },
                                         "effects" => [{ "gain_life" => { "amount" => 2 } }] } }] }
  end
  let(:catalog) { catalog_with(hustler, gauge, mender) }

  def engine(game) = game.instance_variable_get(:@engine)
  def player_view(game, name) = game.view_for(:observer)["players"].find { it["name"] == name }

  def board(alice: [], speed: nil, hand: [], graveyard: [], step: :precombat_main, active: "alice")
    attrs = speed ? { speed: speed } : {}
    build_game(catalog) do
      turn 3, active: active, step: step
      player("alice", **attrs) do
        alice.each { |card, opts| battlefield card, **(opts || {}) }
        hand.each { hand it }
        graveyard.each { graveyard it }
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
  end

  def bolt_bob(game)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: "player:bob") if game.legal_options.include?(type: "target", target: "player:bob")
    game.submit(type: "activate_mana", object: game.state.battlefield.find do
      game.state.object(it).card == "mountain" && !game.state.object(it).tapped
    end,
                ability: "intrinsic:mountain")
    game.submit(type: "pay_mana", mana: "R")
    pass_both(game)
  end

  describe "start your engines! (CR 702.179)" do
    it "a player who controls it and has no speed gets speed 1 (state-based action, CR 704.5aa)" do
      game = board(alice: [["Pitstop Hustler"], ["Speed Dial"]])
      expect(player_view(game, "alice")).not_to have_key("speed")
      entry = game.submit(type: "activate", object: obj_id(game, "Speed Dial"), ability: "printed:0")
      expect(player_view(game, "alice")["speed"]).to eq(1)
      expect(entry.events.map(&:type)).to include("speed_changed")
      pass_both(game)
      expect(player_view(game, "alice")["life"]).to eq(21) # the speed amount
    end

    it "increases once each turn when an opponent loses life during your turn, with a trigger (CR 702.179d)" do
      game = board(alice: [["Pitstop Hustler"], ["Mountain", { count: 2 }]], speed: 1, hand: ["Lightning Bolt", "Lightning Bolt"])
      bolt_bob(game)
      expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Pitstop Hustler ability"])
      pass_both(game)
      expect(engine(game).speed(0)).to eq(2)
      bolt_bob(game) # only once each turn
      expect(game.state.stack).to be_empty
      expect(engine(game).speed(0)).to eq(2)
    end

    it "doesn't increase on an opponent's turn or past 4, and speed 0 without any (CR 702.179d-f)" do
      theirs = board(alice: [["Mountain"]], speed: 2, hand: ["Lightning Bolt"], active: "bob", step: :upkeep)
      expect(engine(theirs).speed(1)).to eq(0)
      game = board(alice: [["Mountain"]], speed: 4, hand: ["Lightning Bolt"])
      bolt_bob(game)
      expect(game.state.stack).to be_empty
      expect(engine(game).speed(0)).to eq(4)
      engine(game).increase_speed!(0, 1)
      expect(engine(game).speed(0)).to eq(4)
    end

    it "the trigger checks the speed again as it resolves (CR 603.4)" do
      game = board(alice: [["Mountain"]], speed: 3, hand: ["Lightning Bolt"])
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(type: "target", target: "player:bob")
      game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
      game.submit(type: "pay_mana", mana: "R")
      pass_both(game)
      engine(game).set_speed!(0, 4)
      pass_both(game)
      expect(engine(game).speed(0)).to eq(4)
      expect(game.history.flat_map(&:events).map(&:type)).not_to include("speed_changed")
    end

    it "speed round-trips through export and import" do
      game = board(alice: [["Mountain"]], speed: 3)
      copy = Enjine::Game.import(game.export, catalog: catalog)
      expect(engine(copy).speed(0)).to eq(3)
      bad = JSON.parse(game.export).tap { it["state"]["players"][0]["speed"] = 7 }
      expect { Enjine::Game.import(bad, catalog: catalog) }.to raise_error(Enjine::InvalidSnapshot, /speed: must be 1, 2, 3 or 4/)
    end
  end

  describe "max speed (CR 702.178)" do
    it "grants keywords and static abilities only while your speed is 4 (CR 702.178a)" do
      slow = board(alice: [["Pitstop Hustler"], ["Speed Dial"]], speed: 3)
      hustler = obj_id(slow, "Pitstop Hustler")
      expect(engine(slow).chars(hustler).keyword?(:double_strike)).to be(false)
      expect(engine(slow).power(engine(slow).object(hustler))).to eq(2)
      fast = board(alice: [["Pitstop Hustler"], ["Speed Dial"]], speed: 4)
      hustler = obj_id(fast, "Pitstop Hustler")
      expect(engine(fast).chars(hustler).keyword?(:double_strike)).to be(true)
      expect(engine(fast).power(engine(fast).object(hustler))).to eq(3)
      alone = board(alice: [["Pitstop Hustler"], ["Forest"]], speed: 4) # nothing else changes the board
      expect(engine(alone).chars(obj_id(alone, "Pitstop Hustler")).keyword?(:double_strike)).to be(true)
    end

    it "a speed trigger needs a start your engines! card in the game" do
      game = build_game(core_catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", speed: 2) do
          battlefield "Mountain"
          hand "Lightning Bolt"
          library "Forest", count: 5
        end
        player("bob") { library "Forest", count: 5 }
      end
      allow(engine(game)).to receive(:speed_card).and_return(nil)
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(type: "target", target: "player:bob")
      game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
      game.submit(type: "pay_mana", mana: "R")
      pass_both(game)
      expect(game.state.stack).to be_empty
    end

    it "a granted graveyard ability works from the graveyard at max speed (CR 702.178b)" do
      fast = board(alice: [["Forest"]], graveyard: ["Pitstop Hustler"], speed: 4)
      card = ids_in(fast, "alice", :graveyard).first
      option = { type: "activate", object: card, ability: "printed:1:0" }
      expect(fast.legal_options).to include(option)
      fast.submit(option)
      fast.submit(type: "activate_mana", object: obj_id(fast, "Forest"), ability: "intrinsic:forest")
      fast.submit(type: "pay_mana", mana: "G")
      expect(fast.state.exile.map { fast.state.object(it).card }).to eq(["pitstop_hustler"])
      expect(ids_in(fast, "alice", :graveyard)).to be_empty
      slow = board(alice: [["Forest"]], graveyard: ["Pitstop Hustler"], speed: 3)
      expect(slow.legal_options).not_to include(type: "activate", object: ids_in(slow, "alice", :graveyard).first, ability: "printed:1:0")
    end
  end

  describe "exhaust (CR 702.177)" do
    it "can be activated only once, and \"whenever you activate an exhaust ability\" triggers (CR 702.177a)" do
      game = board(alice: [["Gearbreak Tinker"], ["Forest", { count: 2 }]])
      mender = obj_id(game, "Gearbreak Tinker")
      option = { type: "activate", object: mender, ability: "printed:0" }
      game.submit(option)
      game.submit(type: "activate_mana", object: obj_id(game, "Forest"), ability: "intrinsic:forest")
      game.submit(type: "pay_mana", mana: "G")
      expect(game.state.stack.size).to eq(2)
      pass_both(game, 2)
      expect(game.state.object(mender).counters["+1/+1"]).to eq(2)
      expect(player_view(game, "alice")["life"]).to eq(22)
      expect(game.legal_options).not_to include(option)
      skip_to(game, :precombat_main, turn: 5)
      expect(game.legal_options).not_to include(option) # not even on a later turn
    end
  end
end
