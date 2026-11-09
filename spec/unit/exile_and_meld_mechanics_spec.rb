# frozen_string_literal: true

# Validation, path-addressed errors and text of paradigm (CR 702.192), foretell (CR 702.143), suspend
# (CR 702.62), hideaway (CR 702.75), devour (CR 702.82), cast_free's `play` and the planeswalker-types amount.
RSpec.describe "Exile, suspend and meld primitives: validation" do
  def errors_for(card)
    Enjine::CardDefinition.from_h(card)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def spell(abilities: [], effects: [{ "draw" => { "amount" => 1 } }], keywords: [], types: ["sorcery"])
    { "name" => "Spec Unit Spell", "mana_cost" => "{1}", "types" => types, "keywords" => keywords,
      "abilities" => [{ "spell" => { "effects" => effects } }] + abilities }
  end

  def creature(abilities, keywords: [])
    { "name" => "Spec Unit Creature", "mana_cost" => "{1}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "keywords" => keywords, "abilities" => abilities }
  end

  it "accepts each documented form" do
    expect(errors_for(spell(keywords: ["paradigm"]))).to eq([])
    expect(errors_for(spell(abilities: [{ "foretell" => { "cost" => "{1}{R}" } }]))).to eq([])
    expect(errors_for(spell(abilities: [{ "suspend" => { "amount" => 3, "cost" => "{2}{W}" } }]))).to eq([])
    expect(errors_for(spell(effects: [{ "suspend" => { "to" => "self", "amount" => 3 } }], keywords: ["suspend"]))).to eq([])
    expect(errors_for(creature([{ "hideaway" => { "amount" => 4 } }, { "devour" => { "amount" => 1, "each" => "artifact" } }]))).to eq([])
    expect(errors_for(spell(effects: [{ "cast_free" => { "to" => "you", "play" => true } }]))).to eq([])
    expect(errors_for(spell(effects: [{ "dig" => { "amount" => 3, "put" => "exile", "link" => true } }]))).to eq([])
  end

  it "names the path of each mistake" do
    expect(errors_for(creature([], keywords: ["paradigm"]))).to include("keywords: paradigm is only for instants and sorceries")
    expect(errors_for(spell(abilities: [{ "foretell" => {} }]))).to include("abilities[1].foretell.cost: required")
    expect(errors_for(spell(abilities: [{ "suspend" => { "amount" => 0, "cost" => "{W}" } }])))
      .to include("abilities[1].suspend.amount: must be an integer >= 1")
    expect(errors_for(spell(abilities: [{ "suspend" => { "amount" => 1, "cost" => "{W}", "time" => 2 } }])))
      .to include("abilities[1].suspend: unknown parameter \"time\"")
    expect(errors_for(spell(effects: [{ "suspend" => { "to" => "self" } }]))).to include("abilities[0].spell.effects[0].suspend.amount: required")
    expect(errors_for(spell(effects: [{ "cast_free" => { "play" => "yes" } }])))
      .to include("abilities[0].spell.effects[0].cast_free.play: must be true or false")
    expect(errors_for(creature([{ "devour" => { "amount" => 2, "each" => 3 } }]))).to include(a_string_starting_with("abilities[0].devour.each"))
  end

  it "describes them" do
    card = Enjine::CardDefinition.from_h(spell(abilities: [{ "foretell" => { "cost" => "{1}{R}" } },
                                                           { "suspend" => { "amount" => 3, "cost" => "{2}{W}" } }],
                                               keywords: ["paradigm"]))
    expect(card.abilities.map(&:to_s)).to include("Foretell {1}{R}", "Suspend 3—{2}{W}", "Paradigm")
    expect(Enjine::CardDefinition.from_h(creature([{ "devour" => { "amount" => 2 } }])).abilities.first.to_s)
      .to start_with("Devour 2")
    suspend = Enjine::CardDefinition.from_h(spell(effects: [{ "suspend" => { "to" => "self", "amount" => 3 } }]))
    expect(suspend.spell_ability.effects.first.to_s).to eq("exile with 3 time counters (suspend) → itself")
    expect(Enjine::Mechanics::Keywords::Suspend.intrinsic_abilities.first.to_s).to start_with("Suspend")
    expect(Enjine::Mechanics::Keywords::Paradigm.delayed.to_s).to include("precombat main")
  end
end
