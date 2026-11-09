# frozen_string_literal: true

# Validation and descriptions of choices between costs (CR 601.2b), optional additional costs (CR 118.8b),
# costs paid while resolving (CR 118.12), ward costs (CR 702.21a) and beholding as a permanent enters.
RSpec.describe "Cost options: card data (unit)" do
  def card(abilities, extra = {})
    { "name" => "Spec Unit Card", "mana_cost" => "{1}", "types" => ["instant"], "abilities" => abilities }.merge(extra)
  end

  def creature(abilities) = card(abilities, "types" => ["creature"], "power" => 1, "toughness" => 1)
  def draw = [{ "draw" => { "amount" => 1 } }]
  def spell(effects) = { "spell" => { "effects" => effects } }

  def errors_for(data)
    Enjine::CardDefinition.from_h(data)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  it "validates one_of with path errors" do
    expect(errors_for(card([{ "additional_cost" => { "cost" => [{ "one_of" => [{ "mana" => "{1}" }] }] } }, spell(draw)])))
      .to eq(["abilities[0].additional_cost.cost[0].one_of: must be a list of at least two costs"])
    nested = { "one_of" => [{ "one_of" => ["discard", { "mana" => "{1}" }] }, { "mana" => "{2}" }] }
    expect(errors_for(card([{ "additional_cost" => { "cost" => [nested] } }, spell(draw)])))
      .to eq(["abilities[0].additional_cost.cost[0].one_of: a one_of can't contain another one_of"])
    expect(errors_for(card([{ "additional_cost" => { "cost" => [{ "one_of" => %w[discard bogus] }] } }, spell(draw)])))
      .to include(a_string_starting_with("abilities[0].additional_cost.cost[0].one_of[1]: unknown cost \"bogus\""))
    expect(errors_for(card([{ "additional_cost" => { "cost" => [{ "one_of" => %w[discard tap] }] } }, spell(draw)])))
      .to include(a_string_starting_with("abilities[0].additional_cost.cost[0]: a spell's additional cost must be"))
  end

  it "validates the optional flag, pay costs, get_counters, ward lists and enters_tapped_unless_behold" do
    expect(errors_for(card([{ "additional_cost" => { "cost" => ["discard"], "optional" => "yes" } }, spell(draw)])))
      .to include(a_string_starting_with("abilities[0].additional_cost.optional:"))
    expect(errors_for(card([spell([{ "pay" => { "cost" => [] } }])])))
      .to eq(["abilities[0].spell.effects[0].pay.cost: must be a non-empty list"])
    expect(errors_for(card([spell([{ "pay" => { "cost" => [{ "get_counters" => { "counter" => "", "amount" => 0 } }] } }])])))
      .to eq(["abilities[0].spell.effects[0].pay.cost[0].get_counters.counter: must be a counter kind, e.g. \"poison\"",
              "abilities[0].spell.effects[0].pay.cost[0].get_counters.amount: must be an integer >= 1"])
    expect(errors_for(creature([{ "ward" => { "cost" => [{ "pay_life" => 0 }] } }])))
      .to eq(["abilities[0].ward.cost[0].pay_life: must be an integer >= 1 or \"X\""])
    expect(errors_for(creature([{ "enters_tapped_unless_behold" => {} }])))
      .to eq(["abilities[0].enters_tapped_unless_behold.card: required"])
    expect(errors_for(card([spell([{ "discard" => { "hand" => true, "random" => true } }])])))
      .to eq(["abilities[0].spell.effects[0].discard: hand and random can't be combined"])
    expect(errors_for(card([spell([{ "discard" => {} }])]))).to eq(["abilities[0].spell.effects[0].discard.amount: required"])
    expect(Enjine::CardDefinition.from_h(card([spell([{ "discard" => { "hand" => true } }])])).abilities.first.to_s)
      .to eq("discard the whole hand → you")
    expect(errors_for(creature([{ "spells_have" => { "keywords" => ["flying"] } }])))
      .to eq(["abilities[0].spells_have.keywords: must be a non-empty list of convoke, improvise"])
    expect(Enjine::CardDefinition.from_h(creature([{ "spells_have" => { "keywords" => ["convoke"] } }])).abilities.first.to_s)
      .to eq("Spells you cast have convoke")
  end

  it "describes them" do
    defn = Enjine::CardDefinition.from_h(creature([
                                                    { "additional_cost" => { "cost" => [{ "one_of" => [{ "pay_life" => 5 },
                                                                                                       { "mana" => "{2}" }] }] } },
                                                    { "ward" => { "cost" => [{ "get_counters" => { "counter" => "poison",
                                                                                                   "amount" => 1 } }] } },
                                                    { "enters_tapped_unless_behold" => { "card" => { "subtypes" => ["jace"] } } }
                                                  ]))
    expect(defn.abilities.map(&:to_s)).to eq(["As an additional cost to cast this spell: Pay 5 life or pay {2}",
                                              "Ward—Get 1 poison counter",
                                              "as this enters, you may behold a Jace; if you don't, it enters tapped"])
    optional = Enjine::CardDefinition.from_h(card([{ "additional_cost" => { "cost" => [{ "mana" => "{1}" }], "optional" => true } },
                                                   spell([{ "pay" => { "life" => 2 } }])]))
    expect(optional.abilities.map(&:to_s)).to eq(["As an additional cost to cast this spell, you may: {1}", "you may pay 2 life"])
    expect(Enjine::Mechanics::Condition.build({ "cast_with" => "additional_cost" }, [], "c").to_s).to eq("its additional cost was paid")
    expect(Enjine::Mechanics::Condition.build({ "cast_with" => "teamwork" }, [], "c").to_s).to eq("it was cast using teamwork")
  end
end
