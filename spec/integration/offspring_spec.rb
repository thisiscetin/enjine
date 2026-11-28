# frozen_string_literal: true

# Offspring (CR 702.175a-b): an optional additional cost and a linked enters trigger creating a 1/1 token copy.
RSpec.describe "Offspring" do
  let(:vinelasher) do
    { "name" => "Spec Offspring Lizard", "mana_cost" => "{B}", "types" => ["creature"], "subtypes" => ["lizard"],
      "power" => 3, "toughness" => 2, "abilities" => [{ "offspring" => { "cost" => "{2}" } }] }
  end
  let(:catalog) { catalog_with(vinelasher) }

  def board
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Swamp", count: 3
        hand "Spec Offspring Lizard"
        library "Forest", count: 10
      end
      player("bob") { library "Forest", count: 10 }
    end
  end

  def cast!(game, kick)
    game.submit(type: "cast", object: obj_id(game, "spec_offspring_lizard", zone: :hand, player: "alice"))
    expect(game.pending_decision.kind).to eq("choose_kicker")
    game.submit(type: kick ? "kick" : "no_kick")
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
    100.times do
      break if game.pending_decision.kind == "priority" && game.state.stack.empty? && game.state.pending_triggers.empty?

      game.submit(game.legal_options.find { it[:type] == "pass" } || game.legal_options.first)
    end
  end

  def lizards(game)
    game.state.battlefield.map { game.state.object(it) }.select { it.card == "spec_offspring_lizard" }
  end

  it "paying the offspring cost creates a 1/1 token copy as it enters (CR 702.175a)" do
    game = board
    cast!(game, true)
    engine = game.instance_variable_get(:@engine)
    token = lizards(game).find { engine.token?(it) }
    expect(lizards(game).size).to eq(2)
    expect([engine.chars(token).power, engine.chars(token).toughness]).to eq([1, 1])
    expect(engine.chars(token).subtypes).to include(:lizard)
    expect(game.state.players[0].mana_pool.values.sum).to eq(0)
  end

  it "without paying it, no token is created and the spell isn't kicked (CR 702.175a, 702.33d)" do
    game = board
    cast!(game, false)
    expect(lizards(game).size).to eq(1)
    expect(lizards(game).first.memory["kicked"]).to be_nil
  end

  it "validates its cost (CR 702.175a)" do
    bad = vinelasher.merge("name" => "Spec Bad Offspring", "abilities" => [{ "offspring" => { "cost" => [] } }])
    expect { catalog_with(bad) }.to raise_error(Enjine::InvalidCardDefinition, /offspring/)
  end
end
