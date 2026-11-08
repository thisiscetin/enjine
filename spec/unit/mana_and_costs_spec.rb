# frozen_string_literal: true

RSpec.describe "Validation of X costs, mana effects and cost changes (CR 107.3, 106.4, 601.2f, 702.44)" do
  def errors_for(data)
    Enjine::CardDefinition.from_h({ "name" => "Test Card", "types" => ["instant"], "mana_cost" => "{1}" }.merge(data))
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def spell(*effects) = { "abilities" => [{ "spell" => { "effects" => effects } }] }

  it "parses {X} symbols and renders them first (CR 107.3)" do
    expect(Enjine::Mana::Cost.parse("{X}").to_s).to eq("{X}")
    expect(Enjine::Mana::Cost.parse("{R}{X}").to_s).to eq("{X}{R}")
    expect(Enjine::Mana::Cost.parse("{X}{2}{R}").mana_value).to eq(3)
    expect(Enjine::CardDefinition.from_h("name" => "Wide Bolt", "types" => ["instant"], "mana_cost" => "{X}{R}")
                                 .to_h["mana_cost"]).to eq("{X}{R}")
  end

  it "validates add_mana" do
    expect(errors_for(spell({ "add_mana" => { "produce" => "{R}" } }))).to eq([])
    expect(errors_for(spell({ "add_mana" => {} })))
      .to include("abilities[0].spell.effects[0].add_mana: needs exactly one of produce, color")
    expect(errors_for(spell({ "add_mana" => { "produce" => "{R}", "color" => "any" } })))
      .to include("abilities[0].spell.effects[0].add_mana: needs exactly one of produce, color")
    expect(errors_for(spell({ "add_mana" => { "color" => "plaid" } })))
      .to include("abilities[0].spell.effects[0].add_mana.color: must be one of any_one, any")
    expect(errors_for(spell({ "add_mana" => { "produce" => "{G}", "amount" => { "counters" => { "of" => "you" } } } })))
      .to eq([]) # produce, repeated amount times
    expect(errors_for(spell({ "add_mana" => { "produce" => "{Q}" } })))
      .to include("abilities[0].spell.effects[0].add_mana.produce: unsupported produced mana {Q}")
  end

  it "rejects an activated ability without targets that adds mana: it's a mana ability (CR 605.1a)" do
    errors = errors_for("types" => ["artifact"], "abilities" => [{ "activated" => {
                          "cost" => ["tap"], "effects" => [{ "add_mana" => { "produce" => "{G}" } }]
                        } }])
    expect(errors.first).to start_with("abilities[0].activated: an activated ability without targets that adds mana is a mana ability")
  end

  it "validates cost_reduction" do
    expect(errors_for("types" => ["artifact"],
                      "abilities" => [{ "activated" => { "cost" => ["tap"], "effects" => [{ "draw" => { "amount" => 1 } }],
                                                         "cost_reduction" => 2 } }]))
      .to include("abilities[0].activated.cost_reduction: must be {\"amount\": n, \"if\": condition}")
    expect(errors_for("abilities" => [{ "cost_reduction" => {} }])).to include("abilities[0].cost_reduction.amount: required")
    expect(errors_for("abilities" => [{ "cost_reduction" => { "amount" => 1, "if" => { "bogus" => 1 } } }]).first)
      .to start_with("abilities[0].cost_reduction.if: unknown condition")
    expect(errors_for("abilities" => [{ "cost_reduction" => { "amount" => -1 } }]).first)
      .to start_with("abilities[0].cost_reduction.amount: must be an integer >= 0, \"x\"")
    errors = errors_for("types" => ["artifact"],
                        "abilities" => [{ "activated" => { "cost" => ["tap"], "effects" => [{ "draw" => { "amount" => 1 } }],
                                                           "cost_reduction" => { "amount" => "lots" } } }])
    expect(errors.first).to start_with("abilities[0].activated.cost_reduction.amount:")
  end

  it "validates cost_modifier" do
    base = { "types" => ["creature"], "power" => 1, "toughness" => 1 }
    expect(errors_for(base.merge("abilities" => [{ "cost_modifier" => { "reduce" => 1, "increase" => 1 } }])))
      .to include("abilities[0].cost_modifier: needs exactly one of reduce, increase")
    expect(errors_for(base.merge("abilities" => [{ "cost_modifier" => { "reduce" => 1, "caster" => "everyone" } }])))
      .to include("abilities[0].cost_modifier.caster: must be one of you, opponent, any")
    expect(errors_for(base.merge("abilities" => [{ "cost_modifier" => { "reduce" => 1, "spells" => "creature" } }])))
      .to include("abilities[0].cost_modifier.spells: must be an object")
    expect(errors_for(base.merge("abilities" => [{ "cost_modifier" => { "reduce" => 1, "spells" => { "any_of" => ["goblin"] } } }])).first)
      .to start_with("abilities[0].cost_modifier.spells.any_of: must be card types")
  end

  it "describes cost changes and mana effects in words" do
    defn = Enjine::CardPool::Core.catalog
    expect(defn.fetch("tidecaller_adept").abilities.first.to_s).to eq("noncreature spells you cast cost {1} less")
    expect(defn.fetch("toll_warden").abilities.first.to_s).to eq("noncreature spells your opponents cast cost {1} more")
    expect(defn.fetch("rally_signal").abilities.first.to_s).to eq("This spell costs {1} less if a creature is attacking you.")
    expect(defn.fetch("pinning_strike").abilities.first.to_s).to eq("This spell costs {2} less if it targets a creature.")
    expect(defn.fetch("ember_surge").abilities.first.to_s).to eq("add {R}{R}{R}")
    expect(defn.fetch("prism_calf").abilities.first.effects.first.to_s).to eq("add 2 mana of any one color")
    expect(defn.fetch("flare_torrent").abilities.first.effects.first.to_s).to eq("deal damage X → target #1")
  end

  it "sunburst is valid on noncreatures (charge counters, CR 702.44a) and creatures" do
    expect(errors_for("types" => ["artifact"], "keywords" => ["sunburst"])).to eq([])
    expect(errors_for("types" => %w[artifact creature], "keywords" => ["sunburst"], "power" => 0, "toughness" => 0)).to eq([])
  end

  it "snapshot validation checks x and mana_spent" do
    game = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") { battlefield "Forest" }
      player("bob")
    end
    data = JSON.parse(game.export)["state"]
    data["objects"].first.merge!("x" => -1, "mana_spent" => ["Q"])
    expect(Enjine::Snapshot.validate(data, game.catalog)).to include(
      "objects[0].x: must be a non-negative integer", "objects[0].mana_spent: must be a list of mana types"
    )
  end
end
