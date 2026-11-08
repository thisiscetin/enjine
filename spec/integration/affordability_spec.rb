# frozen_string_literal: true

RSpec.describe "Casting is offered only when the colors can be paid (observed in fuzzing)" do
  it "doesn't offer Lightning Bolt with only Islands, but does with a Mountain" do
    game = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Lightning Bolt", "Counterspell"
        battlefield "Island", "Island"
      end
      player("bob")
    end
    expect(game.legal_options).not_to include(a_hash_including(type: "cast", object: ids_in(game, "alice", :hand).first))

    with_red = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: { R: 1 }) do
        hand "Lightning Bolt", "Divination"
        battlefield "Island"
      end
      player("bob")
    end
    expect(with_red.legal_options).to include(type: "cast", object: ids_in(with_red, "alice", :hand).first)
    expect(with_red.legal_options).not_to include(type: "cast", object: ids_in(with_red, "alice", :hand).last) # {2}{U}: 2 mana
  end
end
