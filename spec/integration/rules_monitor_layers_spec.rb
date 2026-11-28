# frozen_string_literal: true

# The RulesMonitor reads a permanent's types, keywords and abilities from the engine's layers 1-6 (CR 613.1a-f)
# and recomputes the rest (layer 7 power/toughness, land plays, hand size, loyalty costs) itself. Each pair
# below: what the engine does right isn't reported, and the violation the check exists for still is.
RSpec.describe "RulesMonitor against the layers (CR 613)" do
  def engine(game) = game.instance_variable_get(:@engine)
  def entry(events = []) = Enjine::HistoryEntry.new(seq: 0, turn: 3, step: "x", player: nil, kind: nil, option: nil, events: events)

  def findings(game, events = [], monitor: Enjine::RulesMonitor.new(game))
    engine(game).touch!
    monitor.check!(entry(events)).map(&:rule)
  end

  def creature(name, power: 2, toughness: 2, **extra)
    { "name" => name, "mana_cost" => "{1}", "types" => ["creature"], "subtypes" => ["soldier"], "power" => power,
      "toughness" => toughness }.merge(extra.transform_keys(&:to_s))
  end

  def board(*cards, mine:, theirs: [], step: :precombat_main, hand: [])
    build_game(catalog_with(*cards)) do
      turn 3, active: "alice", step: step
      player("alice") do
        mine.each { |name, opts| battlefield name, **opts.to_h }
        hand(*hand) unless hand.empty?
        library "Forest", count: 5
      end
      player("bob") do
        theirs.each { battlefield it }
        library "Forest", count: 5
      end
    end
  end

  def effect(kind, id, timestamp: 9_000, **details)
    { "kind" => kind, "timestamp" => timestamp, "controller" => 0, "affected" => [id], "duration" => "permanent" }
      .merge(details.transform_keys(&:to_s))
  end

  describe "a creature that becomes a Bear in addition to its other types (CR 613.4c, 205.1b)" do
    let(:lord) do
      creature("Spec Bear Lord", abilities: [{ "static" => { "affects" => { "each" => { "creature" => { "subtypes" => ["bear"] } },
                                                                            "controller" => "you", "other" => true },
                                                             "pump" => { "power" => 2, "toughness" => 2 } } }])
    end
    let(:game) { board(lord, creature("Spec Footman"), mine: [["Spec Bear Lord"], ["Spec Footman"]]) }
    let(:footman) { obj_id(game, "Spec Footman") }

    before do
      game.state.effects << effect("add_subtypes", footman, subtypes: ["bear"])
      engine(game).touch!
    end

    it "expects the lord's bonus the engine gives it" do
      expect(engine(game).power_toughness(engine(game).object(footman))).to eq([4, 4])
      expect(findings(game)).to eq([])
    end

    it "still reports the bonus when the engine forgets it" do
      allow(engine(game)).to receive(:static_sources).and_return([])
      expect(findings(game)).to eq(["613.4c"])
    end
  end

  describe "a static that pumps attacking creatures (CR 613.4c, 506.4)" do
    let(:banner) do
      { "name" => "Spec War Banner", "mana_cost" => "{2}", "types" => ["artifact"],
        "abilities" => [{ "static" => { "affects" => { "each" => { "creature" => { "attacking" => true } }, "controller" => "you" },
                                        "pump" => { "power" => 1, "toughness" => 0 } } }] }
    end
    let(:game) { board(banner, creature("Spec Raider"), mine: [["Spec War Banner"], ["Spec Raider"]], step: :declare_blockers) }
    let(:raider) { obj_id(game, "Spec Raider") }

    before do
      game.state.attackers[raider] = "player:bob"
      engine(game).touch!
    end

    it "expects the bonus only while the creature attacks" do
      expect(engine(game).power_toughness(engine(game).object(raider))).to eq([3, 2])
      expect(findings(game)).to eq([])
    end

    it "still reports the bonus when the engine forgets it" do
      allow(engine(game)).to receive(:static_sources).and_return([])
      expect(findings(game)).to eq(["613.4c"])
    end
  end

  describe "a pumped creature that becomes only a land (CR 613.4c, 205.1a, 208.3)" do
    let(:game) { board(creature("Spec Puddle"), mine: [["Spec Puddle"]]) }
    let(:puddle) { obj_id(game, "Spec Puddle") }

    it "expects no power or toughness while it isn't a creature" do
      game.state.effects << effect("pump", puddle, timestamp: 50, power: 1, toughness: 1, duration: "end_of_turn")
      game.state.effects << effect("set_types", puddle, timestamp: 51, types: ["land"])
      expect(findings(game)).to eq([])
    end

    it "still reports a creature with the wrong power and toughness" do
      game.state.effects << effect("pump", puddle, timestamp: 50, power: 1, toughness: 1, duration: "end_of_turn")
      allow(engine(game)).to receive(:apply_layers).and_return({})
      expect(findings(game)).to eq(["613.4c"])
    end

    it "expects none from a static that makes it only a land while it is a creature with a marker counter" do
      static = { "affects" => "self", "set_types" => ["land"], "if" => { "source" => { "creature" => { "counters" => "stone" } } } }
      troll = creature("Spec Stone Troll", power: 5, toughness: 5, abilities: [{ "static" => static }])
      game = board(troll, mine: [["Spec Stone Troll", { counters: { "stone" => 1 } }]])
      expect(engine(game).chars(obj_id(game, "Spec Stone Troll")).creature?).to be(false)
      expect(findings(game)).to eq([])
    end
  end

  describe "keyword counters (CR 704.5g, 122.1b, 702.12b)" do
    let(:game) { board(creature("Spec Guardian"), mine: [["Spec Guardian", { damage: 3, counters: counters }]]) }

    context "with an indestructible counter" do
      let(:counters) { { "indestructible" => 1 } }

      it "lets the creature keep lethal damage" do
        expect(findings(game)).to eq([])
      end
    end

    context "without one" do
      let(:counters) { {} }

      it "reports a creature surviving lethal damage" do
        expect(findings(game)).to eq(["704.5g"])
      end
    end
  end

  describe "a -X loyalty ability (CR 606.4, 107.3)" do
    let(:sage) do
      { "name" => "Spec Ebb Sage", "mana_cost" => "{3}{R}", "types" => ["planeswalker"], "subtypes" => ["sage"], "loyalty" => 5,
        "abilities" => [{ "loyalty" => { "cost" => "-X",
                                         "effects" => [{ "lose_life" => { "amount" => "x", "to" => "each_opponent" } }] } }] }
    end
    let(:game) { board(sage, mine: [["Spec Ebb Sage", { counters: { "loyalty" => 5 } }]]) }
    let(:walker) { obj_id(game, "Spec Ebb Sage") }

    it "accepts removing X loyalty counters" do
      monitor = Enjine::RulesMonitor.new(game)
      monitor.check!(game.submit(type: "activate", object: walker, ability: "printed:0"))
      monitor.check!(game.submit(type: "x", value: 3))
      monitor.check!(game.submit(type: "pass")) until game.state.stack.empty? && game.pending_decision.kind == "priority"
      expect(game.state.object(walker).counters["loyalty"]).to eq(2)
      expect(monitor.findings).to eq([])
    end

    it "reports a loyalty change that isn't -X" do
      events = [Enjine::Events::XAnnounced.new(player: "alice", object: "o99", value: 3),
                Enjine::Events::CountersChanged.new(object: walker, counter: "loyalty", from: 5, to: 4, by: nil),
                Enjine::Events::AbilityActivated.new(player: "alice", object: "o99", card: "spec_ebb_sage", source: walker,
                                                     ability: "printed:0", targets: [])]
      expect(findings(game, events)).to eq(["606.4"])
    end
  end

  describe "a copy with haste as an exception (CR 302.6, 707.9b)" do
    let(:game) { board(creature("Spec Mirror Twin"), mine: [["Spec Mirror Twin", { controlled_since: 3 }]], step: :declare_attackers) }
    let(:twin) { obj_id(game, "Spec Mirror Twin") }
    let(:attack) { [Enjine::Events::AttackerDeclared.new(object: twin, target: "player:bob")] }

    it "lets it attack the turn it came under its controller's control" do
      game.state.object(twin).memory["copy_except"] = { "keywords" => ["haste"] }
      expect(findings(game, attack)).to eq([])
    end

    it "still reports a summoning-sick attacker without haste" do
      expect(findings(game, attack)).to eq(["302.6"])
    end
  end

  describe "power/toughness counters other than +1/+1 and -1/-1 (CR 613.4c, 122.1a)" do
    let(:game) { board(creature("Spec Shell"), mine: [["Spec Shell", { counters: { "-0/-1" => 1, "+1/+0" => 2, "+0/+1" => 3 } }]]) }

    it "counts every power/toughness counter" do
      expect(view_of(game, obj_id(game, "Spec Shell"))).to include("power" => 4, "toughness" => 4)
      expect(findings(game)).to eq([])
    end

    it "still reports counters the engine ignored" do
      allow(engine(game)).to receive(:apply_layers).and_return({})
      expect(findings(game)).to eq(["613.4c"])
    end
  end

  describe "additional land plays from a class level and a station symbol (CR 305.2, 717.2a, 722.2a)" do
    let(:druid) do
      { "name" => "Spec Grove Class", "mana_cost" => "{G}", "types" => ["enchantment"], "subtypes" => ["class"],
        "abilities" => [{ "class_level" => { "level" => 2, "cost" => "{G}", "abilities" => ["additional_land_plays"] } }] }
    end
    let(:ship) do
      { "name" => "Spec Seed Ship", "mana_cost" => "{1}{G}", "types" => ["artifact"], "subtypes" => ["spacecraft"],
        "abilities" => [{ "station_symbol" => { "at" => 3, "abilities" => ["additional_land_plays"] } }] }
    end
    let(:game) { board(druid, ship, mine: [["Spec Grove Class"], ["Spec Seed Ship", { counters: { "charge" => 3 } }]]) }

    def plays(game, count)
      Array.new(count) do |i|
        land = engine(game).create_object("forest", 0, :battlefield).id
        game.state.battlefield << land
        Enjine::Events::ZoneChanged.new(card: "forest", old_id: "h#{i}", new_id: land, owner: "alice", from: "hand",
                                        to: "battlefield", reason: "play_land", lookers: nil)
      end
    end

    it "allows one land plus one for each unlocked ability" do
      game.state.object(obj_id(game, "Spec Grove Class")).memory["class_level"] = 2
      expect(findings(game, plays(game, 3))).to eq([])
    end

    it "still reports a land play too many" do
      expect(findings(game, plays(game, 3))).to eq(["305.2"])
    end
  end

  describe "an emblem that gives no maximum hand size (CR 514.1, 402.2, 114.4)" do
    let(:silver) do
      rule = { "player_rule" => { "rule" => "no_max_hand_size" } }
      { "name" => "Spec Silver Sigil", "mana_cost" => "{0}", "types" => ["sorcery"],
        "abilities" => [{ "spell" => { "effects" => [{ "create_emblem" => { "abilities" => [rule] } }] } }] }
    end
    let(:game) { board(silver, mine: [], hand: ["Spec Silver Sigil"] + Array.new(9, "Forest")) }

    def end_turn(game)
      monitor = Enjine::RulesMonitor.new(game)
      findings(game, monitor: monitor)
      findings(game, [Enjine::Events::TurnBegan.new(turn: 4, active: "bob")], monitor: monitor)
    end

    it "lets its owner end the turn with more than seven cards" do
      game.submit(type: "cast", object: obj_id(game, "Spec Silver Sigil", zone: :hand, player: "alice"))
      game.submit(type: "pass") until game.state.stack.empty?
      expect(game.state.emblem_ids.size).to eq(1)
      expect(end_turn(game)).to eq([])
    end

    it "still reports a hand over seven without one" do
      expect(end_turn(game)).to eq(["514.1"])
    end
  end

  describe "a creature that loses all abilities after an Aura gave it flying (CR 702.9b, 613.7, 613.1f)" do
    let(:gift) do
      { "name" => "Spec Feather Gift", "mana_cost" => "{U}", "types" => ["enchantment"], "subtypes" => ["aura"],
        "abilities" => [{ "enchant" => "creature" }, { "static" => { "affects" => "attached", "keywords" => ["flying"] } }] }
    end
    let(:game) { board(gift, creature("Spec Glider"), mine: [["Spec Glider"], ["Spec Feather Gift"]], theirs: ["Grizzly Bears"]) }
    let(:glider) { obj_id(game, "Spec Glider") }
    let(:block) { [Enjine::Events::BlockerDeclared.new(object: obj_id(game, "Grizzly Bears"), attacker: glider)] }

    before { game.state.object(obj_id(game, "Spec Feather Gift")).attached_to = glider }

    it "lets a creature without flying block it once the later removal took the flying away" do
      game.state.effects << effect("lose_abilities", glider, timestamp: 9_000)
      expect(findings(game, block)).to eq([])
    end

    it "still reports the block when the Aura's flying came after the removal" do
      game.state.effects << effect("lose_abilities", glider, timestamp: 0)
      expect(findings(game, block)).to eq(["702.9b"])
    end
  end
end
