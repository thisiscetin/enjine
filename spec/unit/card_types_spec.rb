# frozen_string_literal: true

RSpec.describe "Creating cards of every type from data" do
  def card(data) = Enjine::CardDefinition.from_h(data)

  def errors_for(data)
    card(data)
    raise "expected InvalidCardDefinition"
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  it "creates a creature" do
    bears = card("name" => "Grizzly Bears", "mana_cost" => "{1}{G}", "types" => ["creature"],
                 "subtypes" => ["bear"], "power" => 2, "toughness" => 2)
    expect(bears).to be_creature
    expect(bears).to be_permanent
    expect(bears).to be_castable
    expect(bears).not_to be_instant_speed
    expect([bears.power, bears.toughness]).to eq([2, 2])
    expect(bears.type_line).to eq("Creature — Bear")
  end

  it "creates a creature with keywords; flash makes it instant speed (CR 702.8a)" do
    sentry = card("name" => "Sentry", "mana_cost" => "{1}{W}", "types" => ["creature"], "keywords" => %w[flash haste],
                  "power" => 2, "toughness" => 1)
    expect(sentry.keywords).to eq(%i[flash haste])
    expect(sentry).to be_instant_speed
    expect(sentry.to_h["keywords"]).to eq(%w[flash haste])
  end

  it "creates an instant with targets and effects" do
    bolt = card(Enjine::CardPool::Core.cards.find { it["name"] == "Lightning Bolt" })
    expect(bolt).to be_instant_speed
    expect(bolt).not_to be_permanent
    expect(bolt.spell_ability.targets).to eq([Enjine::Mechanics::Filters::AnyTarget])
    expect(bolt.spell_ability.effects.first).to be_a(Enjine::Mechanics::Effects::DealDamage)
    expect(bolt.spell_ability.effects.first.amount).to eq(3)
  end

  it "creates a sorcery, an artifact and an enchantment" do
    expect(card("name" => "Think", "mana_cost" => "{U}", "types" => ["sorcery"],
                "abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 1 } }] } }])).not_to be_instant_speed
    expect(card("name" => "Relic", "mana_cost" => "{2}", "types" => ["artifact"])).to be_permanent
    expect(card("name" => "Aura", "mana_cost" => "{W}", "types" => ["enchantment"])).to be_permanent
    expect(card("name" => "Golem", "mana_cost" => "{3}", "types" => %w[artifact creature], "power" => 3,
                "toughness" => 3).type_line).to eq("Artifact Creature")
  end

  it "creates a planeswalker with loyalty abilities (CR 306, 606)" do
    vessa = card(Enjine::CardPool::Core.cards.find { it["name"] == "Vessa, Rally Captain" })
    expect(vessa).to be_planeswalker
    expect(vessa.loyalty).to eq(3)
    expect(vessa.abilities.map(&:loyalty_cost)).to eq([1, -2, -3])
    expect(vessa.abilities.map(&:to_s)).to eq(["+1: +1/+1 until end of turn → each creature you control",
                                               "-2: 1 +1/+1 counter(s) → each creature you control",
                                               "-3: deal damage 3 → target #1"])
    expect(vessa.abilities.all?(&:sorcery_speed?)).to be(true)
  end

  it "creates a creature with an activated ability" do
    pyro = card(Enjine::CardPool::Core.cards.find { it["name"] == "Prodigal Pyromancer" })
    ability = pyro.abilities.first
    expect(ability.kind).to eq(:activated)
    expect(ability.costs.map(&:to_s)).to eq(["{T}"])
    expect(ability.mana_cost.mana_value).to eq(0)
  end

  it "parses activated abilities with mana costs and sorcery timing" do
    defn = card("name" => "Forge", "mana_cost" => "{2}", "types" => ["artifact"],
                "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{1}{R}" }, "tap"], "timing" => "sorcery",
                                                   "effects" => [{ "lose_life" => { "amount" => 1, "to" => "each_opponent" } }] } }])
    expect(defn.abilities.first.mana_cost.to_s).to eq("{1}{R}")
    expect(defn.abilities.first).to be_sorcery_speed
  end

  it "round-trips every card in the core pool" do
    Enjine::CardPool::Core.cards.each do |data|
      defn = card(data)
      expect(card(defn.to_h)).to eq(defn)
    end
  end

  it "enforces type-specific rules with paths" do
    expect(errors_for("name" => "X", "mana_cost" => "{1}", "types" => ["creature"]))
      .to include(a_string_matching(/power: creatures need/), a_string_matching(/toughness: creatures need/))
    expect(errors_for("name" => "X", "mana_cost" => "{1}", "types" => ["planeswalker"]))
      .to include(a_string_matching(/loyalty: planeswalkers need/))
    expect(errors_for("name" => "X", "mana_cost" => "{1}", "types" => ["instant"], "power" => 1))
      .to include(a_string_matching(/only creatures have power/))
    expect(errors_for("name" => "X", "mana_cost" => "{1}", "types" => ["instant"], "loyalty" => 1))
      .to include(a_string_matching(/only planeswalkers have loyalty/))
    expect(errors_for("name" => "X", "mana_cost" => "{1}", "types" => ["creature"], "power" => 1, "toughness" => 1,
                      "abilities" => [{ "spell" => {} }, { "loyalty" => { "cost" => 1 } }]))
      .to include("abilities[0]: spell abilities need a instant/sorcery card",
                  "abilities[1]: loyalty abilities need a planeswalker card")
  end

  it "reports unknown keywords, effects, filters and bad selectors" do
    errors = errors_for("name" => "X", "mana_cost" => "{1}", "types" => ["instant"], "keywords" => ["banding"],
                        "abilities" => [{ "spell" => {
                          "targets" => %w[creature walrus],
                          "effects" => [{ "explode" => {} },
                                        { "deal_damage" => { "amount" => -1, "to" => { "target" => 5 } } },
                                        { "pump" => { "to" => "everyone" } },
                                        { "add_counters" => { "counter" => "+2/+2", "amount" => 1, "to" => "self" } },
                                        { "destroy" => { "to" => { "each" => "creature", "controller" => "nobody" } } },
                                        { "destroy" => { "to" => {} } },
                                        { "destroy" => {} }]
                        } }])
    expect(errors).to include(
      a_string_matching(/keywords\[0\]: unknown keyword "banding"/),
      a_string_matching(/targets\[1\]: unknown filter "walrus"/),
      a_string_matching(/effects\[0\]: unknown effect "explode"/),
      a_string_matching(/deal_damage\.amount: must be an integer >= 0/),
      a_string_matching(/deal_damage\.to\.target: must refer to one of the \d declared targets/),
      a_string_matching(/pump\.to: must be/),
      a_string_matching(/add_counters\.counter: must be one of/),
      a_string_matching(/destroy\.to\.controller: must be one of/),
      a_string_matching(/effects\[5\]\.destroy\.to: needs "target" or "each"/),
      a_string_matching(/effects\[6\]\.destroy\.to: required/)
    )
  end

  it "rejects malformed ability parameters" do
    errors = errors_for("name" => "X", "mana_cost" => "{1}", "types" => ["artifact"],
                        "abilities" => [{ "activated" => { "cost" => [], "timing" => "whenever", "targets" => "creature",
                                                           "effects" => {} } },
                                        { "activated" => { "cost" => [{ "mana" => "{Z}" }] } }])
    expect(errors).to include(a_string_matching(/activated\.timing/), a_string_matching(/activated\.cost: must be a non-empty list/),
                              a_string_matching(/activated\.targets: must be a list/),
                              a_string_matching(/activated\.effects: must be a list/),
                              a_string_matching(/unsupported mana symbol \{Z\}/))
    expect(errors_for("name" => "PW", "mana_cost" => "{1}", "types" => ["planeswalker"], "loyalty" => 1,
                      "abilities" => [{ "loyalty" => { "cost" => "+1" } }]))
      .to include(a_string_matching(/loyalty\.cost: must be an integer/))
  end
end
