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

    it "reports a static pump the engine forgot" do
      allow_any_instance_of(Enjine::Engine).to receive(:static_sources).and_return([]) # rubocop:disable RSpec/AnyInstance
      expect(checked(game).map(&:rule)).to eq(["613.4c"])
    end
  end
end
