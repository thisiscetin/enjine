# frozen_string_literal: true

RSpec.describe "Being the chosen type in addition to other types (CR 205.1b, 305.6, 607.2d, 614.12)" do
  def board(hand:, mine: [], mana: {})
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: mana) do
        hand(*hand)
        mine.each { battlefield it }
        library "Forest", count: 10
      end
      player("bob") { library "Forest", count: 10 }
    end
  end

  def chars(game, id) = game.instance_variable_get(:@engine).chars(id)

  it "a land that is the chosen basic land type has its mana ability" do
    game = board(hand: ["Wayfarer's Crossing"])
    game.submit(type: "play_land", object: obj_id(game, "Wayfarer's Crossing", zone: :hand, player: "alice"))
    expect(game.pending_decision.kind).to eq("enter_choice")
    expect(game.legal_options.map { it[:basic_land_type] }).to eq(%w[plains island swamp mountain forest])
    game.submit(type: "basic_land_type", basic_land_type: "island")
    crossing = obj_id(game, "Wayfarer's Crossing")
    expect(chars(game, crossing).subtypes).to eq([:island])
    game.submit(type: "activate_mana", object: crossing, ability: "intrinsic:island")
    expect(game.state.players[0].mana_pool[:U]).to eq(1)
  end

  it "a creature is the chosen creature type in addition, and pumps the others of it" do
    game = board(hand: ["Kindred Construct"], mine: ["Grizzly Bears"], mana: { C: 3 })
    game.submit(type: "cast", object: obj_id(game, "Kindred Construct", zone: :hand, player: "alice"))
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
    game.submit(type: "pass") until game.pending_decision.kind == "enter_choice"
    game.submit(type: "creature_type", creature_type: "bear")
    construct = obj_id(game, "Kindred Construct")
    expect(chars(game, construct).subtypes).to contain_exactly(:construct, :bear)
    expect(chars(game, obj_id(game, "Grizzly Bears")).power).to eq(3)
    expect(chars(game, construct).power).to eq(2) # "other"
  end
end
