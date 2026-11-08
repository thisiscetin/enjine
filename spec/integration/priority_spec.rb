# frozen_string_literal: true

RSpec.describe "Priority and turn structure (CR 117, 500)" do
  let(:game) do
    build_game do
      turn 3, active: "alice", step: :upkeep
      player("alice") { library "Forest", count: 10 }
      player("bob") { library "Forest", count: 10 }
    end
  end

  it "gives the active player priority first, then the opponent after a pass (CR 117.3a, 117.3d)" do
    expect(game.pending_decision.player).to eq("alice")
    expect(game.pending_decision.kind).to eq("priority")
    expect(game.legal_options).to eq([{ type: "pass" }])
    game.submit(type: "pass")
    expect(game.pending_decision.player).to eq("bob")
    expect(game.step).to eq(:upkeep)
  end

  it "ends the step when both players pass in succession with an empty stack (CR 117.4, 500.2)" do
    pass_both(game)
    expect(game.step).to eq(:draw)
    expect(game.pending_decision.player).to eq("alice")
  end

  it "walks every step of a turn in order, skipping blockers and damage without attackers (CR 508.8)" do
    steps = []
    game.subscribe { |e| steps << e.step if e.is_a?(Enjine::Events::StepBegan) }
    pass_both(game, 8)
    expect(steps).to eq(%w[draw precombat_main beginning_of_combat declare_attackers end_of_combat postcombat_main end
                           cleanup untap upkeep])
    expect(game.turn).to eq(4)
    expect(game.view_for(:observer)["active"]).to eq("bob")
  end

  it "has no priority in the untap and cleanup steps (CR 502.4, 514.3)" do
    kinds = []
    game.subscribe { |e| kinds << [e.step, game.pending_decision&.kind] if e.is_a?(Enjine::Events::StepBegan) }
    pass_both(game, 8)
    expect(game.history.flat_map(&:events).grep(Enjine::Events::PriorityPassed).size).to eq(16)
    expect(kinds.map(&:first)).to include("untap", "cleanup")
  end

  it "resets the pass count when a player takes an action (CR 117.4)" do
    g = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Forest"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    g.submit(type: "pass")
    g.submit(type: "pass")
    expect(g.step).to eq(:beginning_of_combat)

    g2 = build_game do
      turn 3, active: "alice", step: :end
      player("alice") { battlefield "Forest" }
      player("bob") do
        battlefield "Forest"
        library "Forest", count: 5
      end
    end
    g2.submit(type: "pass")
    g2.submit(type: "activate_mana", object: g2.state.battlefield.last, ability: mana_ref(g2, g2.state.battlefield.last))
    expect(g2.pending_decision.player).to eq("bob")
    g2.submit(type: "pass")
    expect(g2.pending_decision.player).to eq("alice")
    expect(g2.step).to eq(:end)
  end
end
