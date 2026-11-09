# frozen_string_literal: true

# Validation, path-addressed errors and descriptions for earthbend, waterbend, airbend, saddle, exert, decayed
# and wither (CR 701.66, 701.67, 701.65, 702.171, 701.43, 702.147, 702.80).
RSpec.describe "Bending and mount primitives: validation" do
  def errors_for(card)
    Enjine::CardDefinition.from_h(card)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def spell_with(effect, targets: [], extra: [])
    { "name" => "Spec Unit Spell", "mana_cost" => "{1}", "types" => ["sorcery"],
      "abilities" => extra + [{ "spell" => { "targets" => targets, "effects" => [effect] } }] }
  end

  def creature_with(abilities, keywords: [])
    { "name" => "Spec Unit Creature", "mana_cost" => "{1}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "keywords" => keywords, "abilities" => abilities }
  end

  def land = { "land" => { "controller" => "you" } }
  def activated(cost) = { "activated" => { "cost" => cost, "effects" => [{ "draw" => { "amount" => 1 } }] } }
  def text(effect, targets: []) = Enjine::CardDefinition.from_h(spell_with(effect, targets: targets)).spell_ability.effects.first.to_s

  it "accepts each form" do
    expect(errors_for(spell_with({ "earthbend" => { "amount" => "x", "to" => { "target" => 0 } } }, targets: [land]))).to eq([])
    expect(errors_for(spell_with({ "airbend" => { "to" => { "target" => 0 } } }, targets: [{ "one_of" => %w[creature spell] }])))
      .to eq([])
    expect(errors_for(creature_with([activated([{ "waterbend" => "{X}" }, "tap", "exert"])]))).to eq([])
    expect(errors_for(spell_with({ "draw" => { "amount" => 1 } }, extra: [{ "kicker" => { "cost" => [{ "waterbend" => "{4}" }] } }])))
      .to eq([])
    expect(errors_for(spell_with({ "pay" => { "waterbend" => "{2}", "then" => [{ "draw" => { "amount" => 1 } }] } }))).to eq([])
    expect(errors_for(creature_with([{ "saddle" => { "power" => 2 } },
                                     { "triggered" => { "when" => { "becomes_saddled" => {} },
                                                        "effects" => [{ "draw" => { "amount" => 1 } }] } },
                                     { "triggered" => { "when" => { "saddles_mount" => {} }, "effects" => [{ "become_saddled" => {} }] } }],
                                    keywords: %w[decayed wither]))).to eq([])
    expect(errors_for(spell_with({ "draw" => { "amount" => 1 } },
                                 targets: [{ "creature" => { "saddled" => true } }]))).to eq([])
  end

  it "names the path of each mistake" do
    at = "abilities[0].spell.effects[0]"
    expect(errors_for(spell_with({ "earthbend" => { "amount" => 2 } }, targets: [land]))).to include("#{at}.earthbend.to: required")
    expect(errors_for(spell_with({ "earthbend" => { "to" => { "target" => 0 } } }, targets: [land])))
      .to include("#{at}.earthbend.amount: required")
    expect(errors_for(spell_with({ "airbend" => { "to" => { "target" => 0 }, "amount" => 1 } }, targets: ["creature"])))
      .to include(a_string_starting_with("#{at}.airbend: unknown parameter"))
    expect(errors_for(creature_with([activated([{ "waterbend" => "3" }])])))
      .to include(a_string_starting_with("abilities[0].activated.cost[0].waterbend"))
    expect(errors_for(creature_with([activated(["exert"])]).merge("abilities" => [activated([{ "exert" => { "x" => 1 } }])])))
      .to include(a_string_starting_with("abilities[0].activated.cost[0].exert"))
    expect(errors_for(spell_with({ "pay" => { "waterbend" => "{2}", "mana" => "{1}" } })))
      .to include("#{at}.pay: needs exactly one of mana, life, waterbend")
    expect(errors_for(creature_with([{ "ward" => { "cost" => "{1}", "waterbend" => "{2}" } }])))
      .to include("abilities[0].ward: needs exactly one of cost, waterbend")
    expect(errors_for(spell_with({ "counter_unless_pays" => { "mana" => "{1}", "waterbend" => "{2}", "to" => { "target" => 0 } } },
                                 targets: ["spell"])))
      .to include("#{at}.counter_unless_pays: needs exactly one of mana, waterbend")
    expect(errors_for(creature_with([{ "saddle" => { "power" => 0 } }]))).to include(a_string_starting_with("abilities[0].saddle.power"))
    expect(errors_for(creature_with([{ "saddle" => {} }]))).to include(a_string_starting_with("abilities[0].saddle.power"))
    expect(errors_for(spell_with({ "become_saddled" => { "to" => "self", "amount" => 1 } })))
      .to include(a_string_starting_with("#{at}.become_saddled: unknown parameter"))
    expect(errors_for(spell_with({ "draw" => { "amount" => 1 } }, targets: [{ "creature" => { "saddled" => "yes" } }])))
      .to include("abilities[0].spell.targets[0].creature.saddled: must be true or false")
  end

  it "describes each one" do
    expect(text({ "earthbend" => { "amount" => 2, "to" => { "target" => 0 } } }, targets: [land])).to eq("earthbend 2 → target #1")
    expect(text({ "airbend" => { "to" => { "target" => 0 } } }, targets: ["creature"])).to eq("airbend → target #1")
    expect(text({ "become_saddled" => {} })).to eq("becomes saddled until end of turn → itself")
    expect(text({ "pay" => { "waterbend" => "{2}" } })).to eq("you may pay waterbend {2}")
    body = Enjine::CardDefinition.from_h(creature_with([{ "saddle" => { "power" => 3 } }, activated([{ "waterbend" => "{3}" }, "exert"])]))
    expect(body.abilities.map(&:to_s)).to eq(["Saddle 3", "Waterbend {3}, Exert this: draw 1 → you"])
    ward = Enjine::CardDefinition.from_h(creature_with([{ "ward" => { "waterbend" => "{4}" } }])).abilities.first
    expect([ward.to_s, ward.effects.first.to_s]).to eq(["Ward—Waterbend {4}",
                                                        "counter that spell or ability unless its controller pays waterbend {4}"])
    triggers = %w[earthbends waterbends airbends firebends].map do
      Enjine::CardDefinition.from_h(creature_with([{ "triggered" => { "when" => { it => {} },
                                                                      "effects" => [{ "draw" => { "amount" => 1 } }] } }]))
                            .abilities.first.trigger.to_s
    end
    expect(triggers).to eq(["Whenever you earthbend", "Whenever you waterbend", "Whenever you airbend", "Whenever you firebend"])
    filter = Enjine::CardDefinition.from_h(spell_with({ "draw" => { "amount" => 1 } }, targets: [{ "creature" => { "saddled" => false } }]))
    expect(filter.spell_ability.targets.first.to_s).to include("unsaddled")
  end
end
