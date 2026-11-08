# frozen_string_literal: true

RSpec.describe "'As this enters, pay life or it enters tapped' (CR 614.12, 119.4)" do
  let(:shockland) do
    { "name" => "Tidal Ridge", "types" => ["land"], "subtypes" => %w[island mountain],
      "abilities" => [{ "enters_tapped_unless_pay_life" => { "life" => 2 } }] }
  end
  let(:shock_golem) do
    { "name" => "Wary Golem", "mana_cost" => "{1}", "types" => %w[artifact creature], "power" => 1, "toughness" => 1,
      "abilities" => [{ "enters_tapped_unless_pay_life" => { "life" => 3 } }] }
  end
  let(:catalog) { catalog_with(shockland, shock_golem) }

  def game_with(life: 20, hand: ["Tidal Ridge"], board: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", life: life) do
        hand.each { hand it }
        board.each { battlefield it }
      end
      player("bob")
    end
  end

  def play(game) = game.submit(type: "play_land", object: ids_in(game, "alice", :hand).first)

  it "paying life lets it enter untapped" do
    game = game_with
    play(game)
    expect(game.pending_decision).to have_attributes(kind: "enter_choice", player: "alice")
    expect(game.legal_options).to eq([{ type: "pay_life", life: 2 }, { type: "enter_tapped" }])
    game.submit(type: "pay_life", life: 2)
    ridge = obj_id(game, "Tidal Ridge")
    expect(game.state.object(ridge).tapped).to be(false)
    expect(game.state.players[0].life).to eq(18)
    expect(game.legal_options).to include(a_hash_including(type: "activate_mana", object: ridge))
  end

  it "declining makes it enter tapped, at no life cost" do
    game = game_with
    play(game)
    game.submit(type: "enter_tapped")
    expect(game.state.object(obj_id(game, "Tidal Ridge")).tapped).to be(true)
    expect(game.state.players[0].life).to eq(20)
  end

  it "can't pay more life than you have (CR 119.4)" do
    game = game_with(life: 1)
    play(game)
    expect(game.legal_options).to eq([{ type: "enter_tapped" }])
  end

  it "also applies to a permanent spell as it resolves" do
    game = game_with(hand: ["Wary Golem"], board: ["Mountain"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
    game.submit(type: "pay_mana", mana: "R")
    pass_both(game)
    expect(game.pending_decision).to have_attributes(kind: "enter_choice", details: a_hash_including("object"))
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.pending_decision).to eq(game.pending_decision)
    game.submit(type: "pay_life", life: 3)
    expect(game.state.object(obj_id(game, "Wary Golem")).tapped).to be(false)
    expect(game.state.players[0].life).to eq(17)
  end
end
