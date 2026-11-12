# frozen_string_literal: true

# "{1}: Add one mana of any one color. Activate only once each turn." (CR 602.5b on a mana ability, CR 605).
RSpec.describe "Mana abilities activated only once each turn (CR 602.5b)" do
  let(:filter) do
    { "name" => "Spec Prism Filter", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "mana" => { "cost" => [{ "mana" => "{1}" }], "color" => "any_one", "colors" => %w[W B G],
                                    "limit" => "once_each_turn" } }] }
  end
  let(:catalog) { catalog_with(filter) }

  let(:game) do
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: { R: 2 }) do
        battlefield "Spec Prism Filter"
        library "Forest", count: 3
      end
      player("bob") { library "Forest", count: 3 }
    end
  end

  def mana_options(game) = game.legal_options.select { it[:type] == "activate_mana" }

  it "is offered once, then not again this turn" do
    options = mana_options(game)
    expect(options.map { it[:mana] }).to contain_exactly("{W}", "{B}", "{G}")
    game.submit(options.find { it[:mana] == "{G}" })
    expect(game.state.players[0].mana_pool).to include(G: 1, R: 1)
    expect(mana_options(game)).to be_empty # {R} left in the pool, but the limit is used up
  end

  it "resets next turn" do
    filter_id = obj_id(game, "Spec Prism Filter")
    game.state.object(filter_id).memory["activations"] = { "printed:0" => { "turn" => 2, "count" => 1 } }
    expect(mana_options(game)).not_to be_empty
  end

  it "validates and describes the limit" do
    ability = Enjine::CardDefinition.from_h(filter).abilities.first
    expect(ability.to_s).to end_with("Activate only once each turn.")
    bad = filter.merge("abilities" => [{ "mana" => { "cost" => ["tap"], "produce" => "{C}", "limit" => "once" } }])
    expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition, /limit: must be one of once_each_turn/)
  end
end
