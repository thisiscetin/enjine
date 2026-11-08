# frozen_string_literal: true

RSpec.describe "Cost increases and reductions (CR 601.2f, 118.7a)" do
  def pay_all(game)
    while game.pending_decision&.kind == "pay_cost"
      options = game.legal_options
      game.submit(options.find { it[:type] == "pay_mana" } || options.find { it[:type] == "activate_mana" })
    end
  end

  def on_board(game, card) = game.state.battlefield.select { game.state.object(it).card == card }
  def cast_option(game) = { type: "cast", object: ids_in(game, "alice", :hand).first }

  it "a reduction that depends on targets is applied once targets are chosen, and only to generic mana" do
    game = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Pinning Strike"
        battlefield "Plains", count: 2
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Grizzly Bears", tapped: true
        battlefield "Raging Goblin"
        library "Forest", count: 5
      end
    end
    tapped, untapped = on_board(game, "grizzly_bears") + on_board(game, "raging_goblin")
    expect(game.legal_options).to include(cast_option(game)) # affordable if it targets a tapped creature
    game.submit(cast_option(game))
    game.submit(type: "target", target: untapped)
    expect(game.pending_decision.details["remaining"]).to eq("{3}{W}") # no reduction: a dead end
    game.submit(type: "cancel")
    game.submit(cast_option(game))
    game.submit(type: "target", target: tapped)
    expect(game.pending_decision.details["remaining"]).to eq("{1}{W}")
    pay_all(game)
    pass_both(game)
    expect(game.state.battlefield).not_to include(tapped)
  end

  it "the total cost is locked in: later changes don't affect it (CR 601.2f)" do
    game = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Scrap Colossus"
        battlefield "Arc Lantern", count: 2
        battlefield "Mountain", count: 4
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    game.submit(cast_option(game))
    expect(game.pending_decision.details["remaining"]).to eq("{4}") # {6} minus one per artifact you control
    lantern = on_board(game, "arc_lantern").first
    game.state.battlefield.delete(lantern) # the count changes mid-payment...
    mountain = on_board(game, "mountain").first
    game.submit(type: "activate_mana", object: mountain, ability: "intrinsic:mountain")
    game.submit(type: "pay_mana", mana: "R")
    expect(game.pending_decision.details["remaining"]).to eq("{3}") # ...but the total stayed locked in
  end

  it "a reduction can't go below {0} or touch colored mana; increases add generic mana" do
    game = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Ember Surge"
        battlefield "Tidecaller Adept", count: 3
        battlefield "Mountain"
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Toll Warden"
        library "Forest", count: 5
      end
    end
    game.submit(cast_option(game))
    expect(game.pending_decision.details["remaining"]).to eq("{R}") # {1}{R} + 1 - 3: generic floors at 0
  end

  it "opponents' cost increases make a spell unaffordable" do
    game = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Ember Surge"
        battlefield "Mountain", count: 2
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Toll Warden"
        library "Forest", count: 5
      end
    end
    expect(game.legal_options).not_to include(cast_option(game))
  end

  it "a reduction while a creature is attacking you (a condition on the game state)" do
    game = build_game do
      turn 3, active: "bob", step: :precombat_main
      player("alice") do
        hand "Rally Signal"
        battlefield "Plains", count: 2
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Grizzly Bears"
        library "Forest", count: 5
      end
    end
    rally = cast_option(game)
    game.submit(type: "pass")
    expect(game.legal_options).not_to include(rally) # {2}{W} with two lands
    game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
    game.submit(type: "attack", object: on_board(game, "grizzly_bears").first, target: "player:alice")
    game.submit(type: "pass") until game.pending_decision.player == "alice"
    expect(game.legal_options).to include(rally)
    game.submit(rally)
    expect(game.pending_decision.details["remaining"]).to eq("{1}{W}")
  end

  it "an activated ability's own reduction (CR 602.2b)" do
    game = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Survey Drone"
        battlefield "Island", count: 3
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    drone = on_board(game, "survey_drone").first
    game.submit(type: "activate", object: drone, ability: "printed:0")
    expect(game.pending_decision.details["remaining"]).to eq("{1}") # {4} minus one per land
    pay_all(game)
    pass_both(game)
    expect(ids_in(game, "alice", :hand).size).to eq(1)
  end
end
