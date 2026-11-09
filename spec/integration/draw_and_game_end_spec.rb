# frozen_string_literal: true

RSpec.describe "Drawing and ending the game (CR 103.8a, 504, 704.5, 104)" do
  it "makes the active player draw in the draw step" do
    game = build_game do
      turn 2, active: "bob", step: :upkeep
      player("alice") { library "Forest", count: 3 }
      player("bob") { library "Island", count: 3 }
    end
    pass_both(game)
    expect(game.step).to eq(:draw)
    expect(ids_in(game, "bob", :hand).size).to eq(1)
    expect(ids_in(game, "bob", :library).size).to eq(2)
  end

  it "skips the starting player's whole first draw step (CR 103.8a)" do
    game = through_pregame(basics_setup.new_game(seed: 3))
    starting = game.view_for(:observer)["active"]
    expect(game.step).to eq(:upkeep)
    pass_both(game)
    expect(game.step).to eq(:precombat_main)
    expect(game.view_for(:observer)["players"].find { it["name"] == starting }["hand_count"]).to eq(7)
  end

  it "makes a player who drew from an empty library lose (CR 704.5b)" do
    game = build_game do
      turn 2, active: "bob", step: :upkeep
      player("alice") { library "Forest" }
      player("bob")
    end
    entry = nil
    2.times { entry = game.submit(type: "pass") }
    expect(game).to be_over
    expect(game.result).to eq("winner" => "alice", "reason" => "empty_library")
    expect(entry.events.map(&:type).last(2)).to eq(%w[player_lost game_ended])
    expect(game.pending_decision).to be_nil
    expect { game.submit(type: "pass") }.to raise_error(Enjine::IllegalDecision, /over/)
  end

  it "makes a player at 0 or less life lose (CR 704.5a)" do
    game = build_game do
      turn 2, active: "alice", step: :upkeep
      player("alice")
      player("bob", life: 0)
    end
    expect(game.result).to be_nil
    game.submit(type: "pass")
    expect(game.result).to eq("winner" => "alice", "reason" => "life")
  end

  it "makes a player with ten poison counters lose (CR 704.5c)" do
    game = build_game do
      turn 2, active: "alice", step: :upkeep
      player("alice", poison: 10)
      player("bob")
    end
    game.submit(type: "pass")
    expect(game.result).to eq("winner" => "bob", "reason" => "poison")
  end

  it "is a draw when all players lose simultaneously (CR 104.4a)" do
    game = build_game do
      turn 2, active: "alice", step: :upkeep
      player("alice", drew_from_empty: true)
      player("bob", life: -3)
    end
    game.submit(type: "pass")
    expect(game.result).to eq("winner" => nil, "reason" => "empty_library,life")
  end

  it "lets a player concede at any time (CR 104.3a)" do
    game = basics_setup.new_game(seed: 1)
    entry = game.concede("alice")
    expect(entry.kind).to eq("concede")
    expect(game.result).to eq("winner" => "bob", "reason" => "concede")
    expect { game.concede("bob") }.to raise_error(Enjine::IllegalDecision)
    expect { basics_setup.new_game(seed: 1).concede("zed") }.to raise_error(ArgumentError, /unknown player/)
  end
end
