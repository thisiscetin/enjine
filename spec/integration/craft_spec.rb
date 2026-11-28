# frozen_string_literal: true

# Craft with [materials] [cost] (CR 702.167a-c): exile this and the materials, return it transformed.
RSpec.describe "Craft" do
  let(:bricks) do
    { "name" => "Spec Bricks // Spec Kiln", "layout" => "transform",
      "faces" => [{ "name" => "Spec Bricks", "mana_cost" => "{1}{W}", "types" => ["artifact"],
                    "abilities" => [{ "craft" => { "cost" => "{W}", "materials" => { "card" => { "types" => ["artifact"] } } } }] },
                  { "name" => "Spec Kiln", "types" => ["artifact"], "colors" => ["W"] }] }
  end
  let(:pair) do
    { "name" => "Spec Pair Craft // Spec Pair Back", "layout" => "transform",
      "faces" => [{ "name" => "Spec Pair Craft", "mana_cost" => "{W}", "types" => ["artifact"],
                    "abilities" => [{ "craft" => { "cost" => [{ "mana" => "{W}" }],
                                                   "materials" => { "card" => { "types" => ["creature"] }, "count" => 2,
                                                                    "or_more" => true } } }] },
                  { "name" => "Spec Pair Back", "types" => %w[artifact creature], "colors" => ["W"], "power" => 4,
                    "toughness" => 4 }] }
  end
  let(:relic) { { "name" => "Spec Craft Relic", "mana_cost" => "{1}", "types" => ["artifact"] } }
  let(:bear) { { "name" => "Spec Craft Bear", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 2, "toughness" => 2 } }
  let(:catalog) { catalog_with(bricks, pair, relic, bear) }

  def board(battlefield:, graveyard: [], step: :precombat_main)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice") do
        battlefield "Plains", count: 2
        battlefield.each { battlefield it }
        graveyard(*graveyard) unless graveyard.empty?
        library "Forest", count: 10
      end
      player("bob") { library "Forest", count: 10 }
    end
  end

  def pay!(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def resolve!(game)
    50.times do
      break if game.pending_decision.kind == "priority" && game.state.stack.empty? && game.state.pending_triggers.empty?

      game.submit(game.legal_options.find { it[:type] == "pass" } || game.legal_options.first)
    end
  end

  def activate_craft(game, card)
    id = obj_id(game, card)
    game.legal_options.find { it[:type] == "activate" && it[:object] == id }
  end

  def exiled(game) = game.state.exile.map { game.state.object(it).card }
  def engine(game) = game.instance_variable_get(:@engine)

  it "exiles this and an artifact card from the graveyard, then returns transformed (CR 702.167a)" do
    game = board(battlefield: ["Spec Bricks // Spec Kiln"], graveyard: ["Spec Craft Relic"])
    game.submit(activate_craft(game, "spec_bricks"))
    expect(game.pending_decision.kind).to eq("choose_cost")
    game.submit(game.legal_options.find { it[:type] == "cost" })
    pay!(game)
    expect(exiled(game)).to contain_exactly("spec_bricks", "spec_craft_relic")
    resolve!(game)
    back = game.state.battlefield.find { engine(game).chars(it).name == "Spec Kiln" }
    expect(engine(game).chars(back).name).to eq("Spec Kiln")
    expect(exiled(game)).to eq(["spec_craft_relic"])
  end

  it "materials may be permanents you control, never the crafting one; or more: done after enough (CR 702.167a, 702.167b)" do
    game = board(battlefield: ["Spec Pair Craft // Spec Pair Back", "Spec Craft Bear"], graveyard: ["Spec Craft Bear", "Spec Craft Bear"])
    game.submit(activate_craft(game, "spec_pair_craft"))
    options = game.legal_options.select { it[:type] == "cost" }
    expect(options.size).to eq(3)
    expect(options.map { it[:object] }).not_to include(obj_id(game, "spec_pair_craft"))
    game.submit(options.find { it[:object] == obj_id(game, "spec_craft_bear") })
    expect(option_types(game)).not_to include("done")
    game.submit(game.legal_options.find { it[:type] == "cost" })
    expect(option_types(game)).to include("done")
    game.submit(type: "done")
    pay!(game)
    resolve!(game)
    back = game.state.battlefield.find { engine(game).chars(it).name == "Spec Pair Back" }
    expect(engine(game).chars(back).power).to eq(4)
    expect(game.state.battlefield.map { game.state.object(it).card }).not_to include("spec_craft_bear")
  end

  it "isn't offered without materials or outside sorcery timing (CR 702.167a, 118.3)" do
    expect(activate_craft(board(battlefield: ["Spec Bricks // Spec Kiln"]), "spec_bricks")).to be_nil
    game = board(battlefield: ["Spec Bricks // Spec Kiln"], graveyard: ["Spec Craft Relic"], step: :upkeep)
    expect(activate_craft(game, "spec_bricks")).to be_nil
  end

  it "validates and describes itself (CR 702.167a)" do
    bad = relic.merge("name" => "Spec Bad Craft", "abilities" => [{ "craft" => { "cost" => 3, "materials" => { "count" => 0 } } }])
    expect { catalog_with(bad) }.to raise_error(Enjine::InvalidCardDefinition, /craft.cost.*|craft.materials/m)
    ability = Enjine::CardDefinition.from_h(pair).faces.first.ability_instances.first.ability
    expect(ability.to_s).to include("Craft", "2 or more creature cards")
  end
end
