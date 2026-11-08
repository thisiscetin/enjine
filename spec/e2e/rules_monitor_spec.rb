# frozen_string_literal: true

# The RulesMonitor only proves something if it catches real bugs, so these specs plant
# bugs in the engine and check the monitor reports them.
RSpec.describe Enjine::RulesMonitor do
  def play(decisions: 4000, seed: 3)
    setup = Enjine::Setup.new(Enjine::Player.new(name: "p1", deck: Enjine::CardPool::Core.deck("gruul_beats")),
                              Enjine::Player.new(name: "p2", deck: Enjine::CardPool::Core.deck("azorius_walkers")))
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

  it "catches mana that doesn't empty between steps (CR 500.4)" do
    allow_any_instance_of(Enjine::Engine).to receive(:empty_mana_pools!) # rubocop:disable RSpec/AnyInstance
    expect(rules(play)).to include("500.4")
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
    stub_const("Enjine::Actions::PlayLand::LANDS_PER_TURN", 3)
    expect(rules(play)).to include("305.2")
  end
end
