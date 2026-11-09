# frozen_string_literal: true

RSpec.describe Enjine::CardDefinition do
  let(:forest) { { "name" => "Forest", "types" => ["land"], "supertypes" => ["basic"], "subtypes" => ["forest"] } }

  def errors_for(data)
    described_class.from_h(data)
    raise "expected InvalidCardDefinition"
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  it "builds a land with an intrinsic mana ability (CR 305.6)" do
    defn = described_class.from_h(forest)
    expect(defn.id).to eq("forest")
    expect(defn).to be_land
    expect(defn).to be_permanent
    expect(defn).to be_deck_limit_exempt
    expect(defn.type_line).to eq("Basic Land — Forest")
    expect(defn.mana_abilities.map(&:produce)).to eq([[:G]])
    expect(defn.mana_abilities.first.to_s).to eq("{T}: Add {G}.")
  end

  it "accepts symbol keys and round-trips through to_h" do
    defn = described_class.from_h(name: "Forest", types: [:land], supertypes: [:basic], subtypes: [:forest])
    expect(described_class.from_h(defn.to_h)).to eq(defn)
    expect(defn.to_h).to eq(forest)
    expect(defn.to_h).to be_frozen
    expect(defn.hash).to eq(described_class.from_h(forest).hash)
  end

  it "carries an optional rarity and printing, round-trips them, and ignores them for identity" do
    alfa = { "name" => "Alfa", "mana_cost" => "{1}{U}{U}", "types" => ["instant"],
             "abilities" => [{ "spell" => { "targets" => ["spell"], "effects" => [{ "counter" => { "to" => { "target" => 0 } } }] } }],
             "rarity" => "rare", "printing" => { "set" => "trk", "number" => "12" } }
    defn = described_class.from_h(alfa.merge("printing" => { set: "trk", number: 12 }))
    expect([defn.rarity, defn.printing]).to eq(["rare", { "set" => "trk", "number" => "12" }])
    expect(defn.to_h).to eq(alfa)
    expect(described_class.from_h(defn.to_h).to_h).to eq(alfa)
    reprint = described_class.from_h(alfa.merge("rarity" => "common", "printing" => { "set" => "abc", "number" => "7a" }))
    expect(reprint).to eq(defn)
    expect(reprint.hash).to eq(defn.hash)
    expect(Enjine::Catalog.from_definitions([defn, reprint]).size).to eq(1)
    expect(errors_for(alfa.merge("rarity" => 3, "printing" => { "set" => "trk" })))
      .to eq(["rarity: must be a string", "printing: must be {\"set\": code, \"number\": collector number}"])
    expect(errors_for(alfa.merge("printing" => "trk:12")).size).to eq(1)
  end

  it "keeps a card's rarity and printing beside its faces" do
    adventure = { "name" => "Alfa // Bravo", "layout" => "adventure",
                  "faces" => [{ "name" => "Alfa", "mana_cost" => "{G}", "types" => ["creature"], "power" => 1, "toughness" => 1 },
                              { "name" => "Bravo", "mana_cost" => "{G}", "types" => ["sorcery"], "subtypes" => ["adventure"],
                                "abilities" => [{ "spell" => { "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }],
                  "rarity" => "uncommon", "printing" => { "set" => "trk", "number" => "3" } }
    defn = described_class.from_h(adventure)
    expect(defn.to_h).to eq(adventure)
    expect(described_class.from_h(defn.to_h)).to eq(defn)
    expect(errors_for(adventure.merge("faces" => [adventure["faces"][0].merge("rarity" => "rare"), adventure["faces"][1]])).first)
      .to start_with("faces[0].rarity: unknown field")
  end

  it "returns an existing definition unchanged" do
    defn = described_class.from_h(forest)
    expect(described_class.from_h(defn)).to be(defn)
  end

  it "builds explicit mana abilities from data" do
    defn = described_class.from_h("name" => "Wastes", "types" => ["land"], "supertypes" => ["basic"],
                                  "abilities" => [{ "mana" => { "cost" => ["tap"], "produce" => "{C}" } }])
    expect(defn.mana_abilities.map(&:produce)).to eq([[:C]])
    expect(defn.to_h["abilities"]).to eq([{ "mana" => { "cost" => ["tap"], "produce" => "{C}" } }])
  end

  it "derives canonical ids from names" do
    expect(described_class.slug("Jace, the Mind Sculptor")).to eq("jace_the_mind_sculptor")
    expect(described_class.slug("Urza's Tower")).to eq("urzas_tower")
    expect(described_class.slug("Lim-Dûl's Vault")).to eq("lim_duls_vault")
  end

  it "rejects non-objects" do
    expect { described_class.from_h("Forest") }.to raise_error(Enjine::InvalidCardDefinition, /must be an object/)
  end

  it "reports every problem at once with its path" do
    errors = errors_for("name" => "", "types" => %w[land wizardry], "flavor" => "x", "power" => "2",
                        "abilities" => [{ "mana" => { "cost" => [], "produce" => "{Q}" } }, "flying", { "a" => 1, "b" => 2 }],
                        "rules_text" => 3, "supertypes" => ["snowy"], "subtypes" => ["Bad Type!"])
    expect(errors).to include(
      a_string_matching(/\Aflavor: unknown field/),
      a_string_matching(/\Aname: required/),
      a_string_matching(/\Atypes\[1\]: unknown type "wizardry" \(supported: .*land/),
      a_string_matching(/\Asupertypes\[0\]: unknown supertype "snowy"/),
      a_string_matching(/\Asubtypes\[0\]: invalid subtype/),
      a_string_matching(/\Apower: must be an integer/),
      a_string_matching(/\Arules_text: must be a string/),
      a_string_matching(/\Aabilities\[0\]\.mana\.cost: must be a non-empty list/),
      a_string_matching(/\Aabilities\[0\]\.mana\.produce: unsupported produced mana/),
      a_string_matching(/\Aabilities\[1\]: unknown ability "flying"/),
      a_string_matching(/\Aabilities\[2\]: must be a name or a single-key object/)
    )
  end

  it "rejects unknown costs and parameters inside abilities" do
    errors = errors_for("name" => "X", "types" => ["land"],
                        "abilities" => [{ "mana" => { "cost" => ["pay_with_wishes", { "tap" => { "x" => 1 } }],
                                                      "produce" => "{G}", "extra" => true } },
                                        { "mana" => "bad" }])
    expect(errors).to include(
      a_string_matching(/abilities\[0\]\.mana: unknown parameter "extra"/),
      a_string_matching(/abilities\[0\]\.mana\.cost\[0\]: unknown cost "pay_with_wishes"/),
      a_string_matching(/abilities\[0\]\.mana\.cost\[1\]\.tap: unknown parameter "x"/),
      a_string_matching(/abilities\[1\]\.mana: parameters must be an object/)
    )
  end

  it "enforces type rules" do
    expect(errors_for(forest.merge("mana_cost" => "{G}"))).to include(a_string_matching(/lands have no mana cost/))
    expect(errors_for(forest.merge("types" => []))).to include("types: must be a non-empty list")
    expect(errors_for(forest.merge("types" => "land"))).to include("types: must be a non-empty list")
    expect(errors_for(forest.merge("subtypes" => "forest"))).to include("subtypes: must be a list")
    expect(errors_for(forest.merge("abilities" => {}))).to include("abilities: must be a list")
    expect(errors_for(forest.merge("mana_cost" => "{2/W}"))).to include(a_string_matching(/unsupported mana symbol/))
  end

  it "accepts free-form subtypes but checks those with rules against the card's types" do
    defn = described_class.from_h(forest.merge("subtypes" => %w[forest Gate]))
    expect(defn.subtypes).to eq(%i[forest gate])
    expect(defn.type_line).to eq("Basic Land — Forest Gate")
    allow(Enjine.registry).to receive(:fetch).and_call_original
    allow(Enjine.registry).to receive(:fetch).with(:subtype, "forest").and_return(
      Class.new { def self.applies_to = [:creature] }
    )
    expect(errors_for(forest)).to include(a_string_matching(/forest is only valid for creature cards/))
  end

  it "reports type_line without subtypes" do
    defn = described_class.from_h("name" => "Wastes", "types" => ["land"], "supertypes" => ["basic"])
    expect(defn.type_line).to eq("Basic Land")
    expect(defn.mana_cost).to be_nil
    expect(defn.supertype?(:basic)).to be(true)
  end
end
