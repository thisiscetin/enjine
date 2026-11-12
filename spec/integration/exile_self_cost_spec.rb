# frozen_string_literal: true

# "{1}{G}, Exile this enchantment: Create two 1/1 green Saproling creature tokens." (CR 406.1, 602.2b)
RSpec.describe "Exiling the permanent itself as a cost (CR 602.2b)" do
  let(:trellis) do
    { "name" => "Spec Seedling Trellis", "mana_cost" => "{G}", "types" => ["enchantment"],
      "abilities" => [{ "activated" => {
        "cost" => [{ "mana" => "{1}{G}" }, "exile_self"],
        "effects" => [{ "create_token" => { "amount" => 2, "token" => { "name" => "Spec Sprout", "types" => ["creature"],
                                                                        "colors" => ["G"], "power" => 1, "toughness" => 1 } } }]
      } }] }
  end
  let(:catalog) { catalog_with(trellis) }

  let(:game) do
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: { G: 2 }) do
        battlefield "Spec Seedling Trellis"
        library "Forest", count: 3
      end
      player("bob") { library "Forest", count: 3 }
    end
  end

  it "exiles it as the ability is activated; the ability still resolves" do
    trellis_id = obj_id(game, "Spec Seedling Trellis")
    game.submit(type: "activate", object: trellis_id, ability: "printed:0")
    until (decision = game.pending_decision).kind == "priority" && game.state.stack.empty?
      if decision.kind == "pay_cost"
        game.submit(game.legal_options.find { it[:type] == "pay_mana" })
      else
        game.submit(game.legal_options.find { it[:type] == "pass" } || game.legal_options.first)
      end
    end
    alice = game.state.players[0]
    expect(game.state.exile.map { game.state.object(it).card }).to eq(["spec_seedling_trellis"])
    expect(alice.graveyard).to be_empty
    expect(game.state.battlefield.map { game.state.object(it).card }).to all(start_with("spec_sprout_token"))
    expect(game.state.battlefield.size).to eq(2)
  end

  it "is described, and can't be paid from another zone (CR 113.6m)" do
    expect(Enjine::CardDefinition.from_h(trellis).abilities.first.to_s).to include("Exile this")
    bad = trellis.merge("abilities" => [{ "activated" => { "cost" => ["exile_self"], "zone" => "graveyard",
                                                           "effects" => [{ "draw" => { "amount" => 1 } }] } }])
    expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition, /can't tap, sacrifice or exile it/)
  end
end
