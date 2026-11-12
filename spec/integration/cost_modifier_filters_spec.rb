# frozen_string_literal: true

# "Dragon spells you cast cost {1} less" / "Red spells you cast cost {1} less" (CR 601.2f): cost_modifier
# `spells` narrowed by subtype and color.
RSpec.describe "Cost modifiers for spells of a subtype or color (CR 601.2f)" do
  let(:roost) do
    { "name" => "Spec Wyrm Roost", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "cost_modifier" => { "spells" => { "subtypes" => ["dragon"] }, "reduce" => 1 } }] }
  end
  let(:ember) do
    { "name" => "Spec Ember Lens", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "cost_modifier" => { "spells" => { "colors" => ["R"], "not" => ["creature"] }, "reduce" => 1 } }] }
  end
  let(:whelp) do
    { "name" => "Spec Cinder Whelp", "mana_cost" => "{1}{R}", "types" => ["creature"], "subtypes" => ["dragon"],
      "power" => 2, "toughness" => 2 }
  end
  let(:pup) do
    { "name" => "Spec Cinder Pup", "mana_cost" => "{1}{R}", "types" => ["creature"], "subtypes" => ["dog"],
      "power" => 2, "toughness" => 2 }
  end
  let(:spark) { { "name" => "Spec Spark Toss", "mana_cost" => "{1}{R}", "types" => ["instant"], "abilities" => [] } }
  let(:frost) { { "name" => "Spec Frost Toss", "mana_cost" => "{1}{U}", "types" => ["instant"], "abilities" => [] } }
  let(:catalog) { catalog_with(roost, ember, whelp, pup, spark, frost) }

  def castable(permanent, mana)
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: mana) do
        battlefield permanent
        hand "Spec Cinder Whelp", "Spec Cinder Pup", "Spec Spark Toss", "Spec Frost Toss"
        library "Forest", count: 3
      end
      player("bob") { library "Forest", count: 3 }
    end
    game.legal_options.select { it[:type] == "cast" }.map { game.state.object(it[:object]).card }
  end

  it "reduces only spells of the named subtype" do
    expect(castable("Spec Wyrm Roost", { R: 1 })).to eq(["spec_cinder_whelp"])
  end

  it "reduces only spells of the named color, with the other filters still applying" do
    expect(castable("Spec Ember Lens", { R: 1 })).to contain_exactly("spec_spark_toss")
  end

  it "describes and validates the filters" do
    words = Enjine::CardDefinition.from_h(ember).abilities.first.to_s
    expect(words).to eq("noncreature R spells you cast cost {1} less")
    expect(Enjine::CardDefinition.from_h(roost).abilities.first.to_s).to eq("Dragon spells you cast cost {1} less")
    bad = roost.merge("abilities" => [{ "cost_modifier" => { "spells" => { "colors" => ["pink"] }, "reduce" => 1 } }])
    expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition, /spells.colors: unknown color/)
  end
end
