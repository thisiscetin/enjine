# frozen_string_literal: true

# The RulesMonitor only proves something if it catches real bugs, so these specs plant
# bugs in the engine and check the monitor reports them.
RSpec.describe Enjine::RulesMonitor do
  def play(decisions: 4000, seed: 4)
    setup = Enjine::Setup.new(Enjine::Player.new(name: "p1", deck: CardFixtures.deck("gruul_beats")),
                              Enjine::Player.new(name: "p2", deck: CardFixtures.deck("azorius_walkers")))
    game = setup.new_game(seed: seed)
    monitor = described_class.new(game)
    agent = Enjine::Agents::Random.new(seed: seed)
    decisions.times do
      break if game.over?

      monitor.check!(game.submit(agent.choose(game.pending_decision)))
    end
    monitor
  end

  def rules(monitor) = monitor.findings.map(&:rule).uniq

  it "reports nothing for a correct engine, and counts mechanics" do
    monitor = play
    expect(monitor.findings).to eq([])
    expect(monitor.stats["spell_cast"]).to be_positive
    expect(monitor.stats["damage_dealt"]).to be_positive
  end

  it "accepts a sorcery whose cast trigger is still waiting for its target (CR 307.1, 603.3d)" do
    watcher = { "name" => "Mill Watcher", "mana_cost" => "{U}", "types" => ["creature"], "power" => 0, "toughness" => 2,
                "abilities" => [{ "triggered" => { "when" => { "cast" => { "spell" => "instant_or_sorcery" } }, "targets" => ["player"],
                                                   "effects" => [{ "mill" => { "amount" => 1, "to" => { "target" => 0 } } }] } }] }
    study = { "name" => "Quiet Study", "mana_cost" => "{U}", "types" => ["sorcery"],
              "abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
    game = build_game(catalog_with(watcher, study)) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: { U: 1 }) do
        hand "Quiet Study"
        battlefield "Mill Watcher"
        library "Island", count: 5
      end
      player("bob") { library "Island", count: 5 }
    end
    monitor = described_class.new(game)
    monitor.check!(game.submit(type: "cast", object: ids_in(game, "alice", :hand).first))
    monitor.check!(game.submit(type: "pay_mana", mana: "U"))
    expect(game.pending_decision.kind).to eq("choose_target")
    expect(monitor.findings).to eq([])
  end

  it "catches wrong power/toughness (CR 613.4c)" do
    allow_any_instance_of(Enjine::Engine).to receive(:apply_layers).and_return({}) # rubocop:disable RSpec/AnyInstance
    expect(rules(play)).to include("613.4c")
  end

  it "catches mana that doesn't empty between steps (CR 500.5)" do
    allow_any_instance_of(Enjine::Engine).to receive(:empty_mana_pools!) # rubocop:disable RSpec/AnyInstance
    expect(rules(play)).to include("500.5")
  end

  it "catches creatures surviving lethal damage (CR 704.5g)" do
    allow_any_instance_of(Enjine::Engine).to receive(:check_permanent_state_based_actions!).and_return(false) # rubocop:disable RSpec/AnyInstance
    expect(rules(play)).to include("704.5g")
  end

  it "catches damage that doesn't cost life (CR 120.3a)" do
    allow_any_instance_of(Enjine::Engine).to receive(:change_life!) # rubocop:disable RSpec/AnyInstance
    expect(rules(play)).to include("120.3a")
  end

  it "catches damage and effects that survive cleanup (CR 514.2)" do
    allow_any_instance_of(Enjine::Engine).to receive(:cleanup_turn!) # rubocop:disable RSpec/AnyInstance
    expect(rules(play)).to include("514.2")
  end

  it "catches summoning-sick attackers (CR 302.6)" do
    allow_any_instance_of(Enjine::Engine).to receive(:summoning_sick_for_tap?).and_return(false) # rubocop:disable RSpec/AnyInstance
    expect(rules(play)).to include("302.6")
  end

  it "catches extra land plays (CR 305.2)" do
    allow_any_instance_of(Enjine::Engine).to receive(:land_plays_allowed).and_return(3) # rubocop:disable RSpec/AnyInstance
    expect(rules(play)).to include("305.2")
  end

  context "with static abilities on the board (CR 604.2, 613.4c, 702.12b, 702.3b)" do
    let(:cards) do
      [{ "name" => "Banner of Ranks", "mana_cost" => "{2}", "types" => ["artifact"],
         "abilities" => [{ "static" => { "affects" => { "each" => "creature", "controller" => "you" },
                                         "pump" => { "power" => 1, "toughness" => 1 },
                                         "keywords" => %w[indestructible attacks_despite_defender haste] } }] },
       { "name" => "Wall of Ranks", "mana_cost" => "{1}", "types" => ["creature"], "keywords" => ["defender"], "power" => 1,
         "toughness" => 1 }]
    end
    let(:game) do
      build_game(catalog_with(*cards)) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") { battlefield "Banner of Ranks", "Wall of Ranks" }
        player("bob") { library "Forest", count: 3 }
      end
    end

    def checked(game)
      monitor = described_class.new(game)
      monitor.check!(Enjine::HistoryEntry.new(seq: 0, turn: 3, step: "x", player: nil, kind: nil, option: nil, events: []))
    end

    it "expects static pumps and lets indestructible creatures keep lethal damage" do
      game.state.object(obj_id(game, "Wall of Ranks")).damage = 3
      expect(checked(game)).to eq([])
      monitor = described_class.new(game)
      event = Enjine::Events::AttackerDeclared.new(object: obj_id(game, "Wall of Ranks"), target: "player:bob")
      expect(monitor.check!(Enjine::HistoryEntry.new(seq: 1, turn: 3, step: "x", player: nil, kind: nil, option: nil,
                                                     events: [event]))).to eq([])
    end

    it "counts haste granted by a static ability for summoning-sick attackers (CR 302.6)" do
      wall = game.state.object(obj_id(game, "Wall of Ranks"))
      wall.controlled_since = 3
      event = Enjine::Events::AttackerDeclared.new(object: wall.id, target: "player:bob")
      expect(checked_events(game, [event])).to eq([])
    end

    def checked_events(game, events)
      described_class.new(game).check!(Enjine::HistoryEntry.new(seq: 1, turn: 3, step: "x", player: nil, kind: nil, option: nil,
                                                                events: events))
    end

    it "lets a permanent that keeps its damage keep it into the next turn (CR 514.2)" do
      keeper = { "name" => "Damage Keeper", "mana_cost" => "{1}", "types" => ["creature"], "keywords" => ["keeps_damage"],
                 "power" => 1, "toughness" => 5 }
      game = build_game(catalog_with(*cards, keeper)) do
        turn 3, active: "alice", step: :upkeep
        player("alice") { battlefield "Damage Keeper", "Wall of Ranks" }
        player("bob") { library "Forest", count: 3 }
      end
      game.state.object(obj_id(game, "Damage Keeper")).damage = 2
      began = [Enjine::Events::TurnBegan.new(turn: 3, active: "alice")]
      expect(checked_events(game, began)).to eq([])
      game.state.object(obj_id(game, "Wall of Ranks")).damage = 1
      expect(checked_events(game, began).map(&:rule)).to include("514.2")
    end

    it "leaves lethal damage on a creature whose creature types were replaced to the engine (CR 704.5g, 613.1d)" do
      wall = obj_id(game, "Wall of Ranks")
      game.state.object(wall).damage = 3
      game.state.effects << { "kind" => "assimilate", "timestamp" => 99, "controller" => 0, "affected" => [wall],
                              "duration" => "permanent" }
      allow_any_instance_of(described_class).to receive(:keyword?).and_return(false) # rubocop:disable RSpec/AnyInstance
      expect(checked(game).map(&:rule)).not_to include("704.5g")
    end

    it "reports a static pump the engine forgot" do
      allow_any_instance_of(Enjine::Engine).to receive(:static_sources).and_return([]) # rubocop:disable RSpec/AnyInstance
      expect(checked(game).map(&:rule)).to eq(["613.4c"])
    end
  end

  context "with conditional Equipment, max speed, station symbols and changelings (CR 604.2, 702.178a, 722.2a, 702.73a)" do
    let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.real_cards) }

    def findings_after(game) = described_class.new(game).check!(game.history.last)

    it "expects an Equipment's bonus only while its condition holds, and max speed statics only at speed 4" do
      game = build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { C: 2 }, speed: 4) do
          battlefield "Quick-Draw Katana", "Walking Sarcophagus"
          library "Forest", count: 3
        end
        player("bob") { library "Forest", count: 3 }
      end
      sarcophagus = obj_id(game, "Walking Sarcophagus")
      game.submit(type: "activate", object: obj_id(game, "Quick-Draw Katana"), ability: "printed:1")
      game.submit(type: "target", target: sarcophagus)
      2.times { game.submit(type: "pay_mana", mana: "C") }
      pass_both(game)
      expect(view_of(game, sarcophagus)).to include("power" => 5, "toughness" => 3)
      expect(findings_after(game)).to eq([])
      skip_to(game, :upkeep, turn: 4)
      expect(view_of(game, sarcophagus)).to include("power" => 3, "toughness" => 3)
      expect(findings_after(game)).to eq([])
    end

    it "expects the statics of a station symbol once the permanent has enough charge counters" do
      game = build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          battlefield "Lumen-Class Frigate", counters: { "charge" => 2 }
          battlefield "Walking Sarcophagus"
          library "Forest", count: 3
        end
        player("bob") { library "Forest", count: 3 }
      end
      game.submit(type: "pass")
      expect(view_of(game, obj_id(game, "Walking Sarcophagus"))).to include("power" => 3, "toughness" => 2)
      expect(findings_after(game)).to eq([])
    end

    it "expects a lord's bonus on a changeling, which has every creature type" do
      game = build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          battlefield "Dwynen, Gilt-Leaf Daen", "Chitinous Graspling"
          library "Forest", count: 3
        end
        player("bob") { library "Forest", count: 3 }
      end
      game.submit(type: "pass")
      expect(view_of(game, obj_id(game, "Chitinous Graspling"))).to include("power" => 4, "toughness" => 5)
      expect(findings_after(game)).to eq([])
    end
  end
end
