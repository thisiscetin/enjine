# frozen_string_literal: true

RSpec.describe "Skipping turns (CR 614.10)" do
  def board
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: { U: 6 }) do
        hand "Stolen Hours"
        library "Forest", count: 10
      end
      player("bob") { library "Forest", count: 10 }
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)

  def cast_stolen_hours(game)
    game.submit(type: "cast", object: obj_id(game, "Stolen Hours", zone: :hand, player: "alice"))
    game.submit(type: "target", target: "player:bob")
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
    game.submit(type: "pass") until game.state.stack.empty?
  end

  it "the opponent's next turn doesn't happen: the caster takes the next one (CR 614.10)" do
    game = board
    cast_stolen_hours(game)
    expect(game.state.extra_turns["skip"]).to eq([1])
    expect(Enjine::Game.import(game.export, catalog: game.catalog).state.to_h).to eq(game.state.to_h)
    skip_to(game, :upkeep, turn: 4)
    expect(game.state.active).to eq(0)
    expect(game.state.extra_turns).not_to have_key("skip")
    skip_to(game, :upkeep, turn: 5)
    expect(game.state.active).to eq(1)
  end

  it "skips add up, and an extra turn is skipped like any other (CR 614.10a)" do
    game = board
    engine(game).skip_turns!(1, 2)
    engine(game).skip_turns!(0, 1)
    engine(game).add_extra_turn!(0)
    expect(engine(game).take_next_turn!).to eq(0) # alice's extra turn, then bob's turn are skipped
    expect(game.state.extra_turns).to eq("queue" => [], "begun" => [], "skip" => [1])
    engine(game).skip_turns!(1, 0)
    expect(game.state.extra_turns["skip"]).to eq([1])
  end
end
