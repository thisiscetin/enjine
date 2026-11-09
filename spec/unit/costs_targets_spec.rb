# frozen_string_literal: true

# Validation and descriptions of costs, kicker, target options, modes, payments and ward.
RSpec.describe "Costs, kicker, targets and payments: card data (unit)" do
  def card(abilities, extra = {})
    { "name" => "Spec Unit Card", "mana_cost" => "{1}", "types" => ["instant"], "abilities" => abilities }.merge(extra)
  end

  def creature(abilities) = card(abilities, "types" => ["creature"], "power" => 1, "toughness" => 1)

  def errors_for(data)
    Enjine::CardDefinition.from_h(data)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def spell(body) = card([{ "spell" => body }])

  def activated(body)
    creature([{ "activated" => { "cost" => [{ "mana" => "{1}" }], "effects" => [{ "draw" => { "amount" => 1 } }] }.merge(body) }])
  end

  def draw = [{ "draw" => { "amount" => 1 } }]
  def sacrifice_creature = { "sacrifice_permanent" => { "filter" => "creature" } }
  def either = { "one_of" => %w[artifact creature] }

  it "validates target options" do
    expect(errors_for(spell("targets" => [{ "filter" => "creature", "optional" => "yes" }], "effects" => draw)))
      .to include(a_string_matching(/optional: must be true or false/))
    expect(errors_for(spell("targets" => [{ "filter" => "creature", "distinct_from" => [0] }], "effects" => draw)))
      .to include(a_string_matching(/distinct_from: must list earlier targets/))
    expect(errors_for(spell("targets" => [{ "filter" => "creature", "extra" => 1 }], "effects" => draw)))
      .to include(a_string_matching(/unknown parameter "extra"/))
    expect(errors_for(spell("targets" => ["creature"], "kicked_targets" => %w[spell spell], "effects" => draw)))
      .to include(a_string_matching(/kicked_targets: must list as many targets as targets/))
    expect(errors_for(spell("divide" => 2, "targets" => [{ "filter" => "creature", "optional" => true }], "effects" => draw)))
      .to include(a_string_matching(/divide: needs a first target that isn't optional/))
    expect(errors_for(spell("divide" => 0, "targets" => ["creature"],
                            "effects" => draw))).to include(a_string_matching(/divide: must be an integer >= 1/))
    mine = { "creature" => { "controller" => "you" } }
    spec = Enjine::CardDefinition.from_h(spell("targets" => [{ "filter" => mine, "optional" => true }],
                                               "effects" => draw)).spell_ability.targets.first
    expect(spec.to_s).to eq("up to one creature you control")
    expect(Enjine::CardDefinition.from_h(spell("targets" => [{ "filter" => "creature" }],
                                               "effects" => draw)).spell_ability.targets.first.to_s)
      .to eq("creature")
  end

  it "validates mode counts" do
    modes = [{ "effects" => draw }, { "effects" => draw }]
    expect(errors_for(spell("choose" => { "min" => 2, "max" => 1 },
                            "modes" => modes))).to include(a_string_matching(/choose: must be an integer/))
    expect(errors_for(spell("choose" => 3, "modes" => modes))).to include(a_string_matching(/can't exceed the number of modes/))
    expect(errors_for(spell("choose_if" => { "if" => { "your_turn" => true } },
                            "modes" => modes))).to include(a_string_matching(/choose_if: must be/))
    expect(errors_for(spell("choose_if" => { "if" => { "your_turn" => true }, "choose" => 1, "x" => 1 }, "modes" => modes)))
      .to include(a_string_matching(/unknown parameter "x"/))
    expect(errors_for(spell("unchosen" => 1, "modes" => modes))).to include(a_string_matching(/unchosen: must be true or false/))
  end

  it "validates activation restrictions and cost zones" do
    expect(errors_for(activated("timing" => "never"))).to include(a_string_matching(/timing: must be one of instant, sorcery, your_turn/))
    expect(errors_for(activated("limit" => "twice"))).to include(a_string_matching(/limit: must be one of once_each_turn/))
    expect(errors_for(activated("cost" => %w[tap exile_self_from_graveyard])))
      .to include(a_string_matching(/a cost paid from the graveyard can't be combined with tap or sacrifice/))
    expect(errors_for(activated("cost" => %w[discard_self exile_self_from_graveyard])))
      .to include(a_string_matching(/costs can't be paid from both hand and graveyard/))
  end

  it "validates chosen costs and describes them" do
    expect(errors_for(activated("cost" => [{ "sacrifice_permanent" => { "other" => 1 } }])))
      .to include(a_string_matching(/other: must be true or false/))
    expect(errors_for(activated("cost" => [{ "tap_permanents" => { "count" => 0 } }])))
      .to include(a_string_matching(/count: must be an integer >= 1/))
    expect(errors_for(activated("cost" => [{ "remove_counters" => { "count" => 2, "counter" => "Bad Name" } }])))
      .to include(a_string_matching(/counter: must be a counter name/))
    costs = Enjine::CardDefinition.from_h(activated("cost" => [
                                                      { "tap_permanents" => { "count" => 2, "filter" => either } },
                                                      { "sacrifice_permanent" => { "filter" => "creature", "other" => true } },
                                                      { "remove_counters" => { "count" => 3, "counter" => "charge" } },
                                                      { "tap_permanents" => {} }, "bottom_self_from_graveyard"
                                                    ])).abilities.first.costs
    expect(costs.map(&:to_s)).to eq(["Tap 2 untapped artifact or creatures you control", "Sacrifice another creature",
                                     "Remove 3 charge counters from among creatures you control",
                                     "Tap an untapped creature you control",
                                     "Put this card from your graveyard on the bottom of your library"])
    expect(costs.first.pay!(nil, nil)).to be_nil
  end

  it "validates kicker and additional costs" do
    expect(errors_for(card([{ "kicker" => { "cost" => [] } },
                            { "spell" => { "effects" => draw } }]))).to include(a_string_matching(/kicker.cost: must be a non-empty list/))
    expect(errors_for(card([{ "kicker" => { "cost" => ["tap"] } }, { "spell" => { "effects" => draw } }])))
      .to include(a_string_matching(/additional cost must be mana, life or a chosen cost/))
    abilities = Enjine::CardDefinition.from_h(card([{ "kicker" => { "cost" => [{ "mana" => "{1}{U}" }] } },
                                                    { "additional_cost" => { "cost" => [sacrifice_creature] } },
                                                    { "spell" => { "effects" => draw } }])).abilities
    expect(abilities.first(2).map(&:to_s)).to eq(["Kicker {1}{U}", "As an additional cost to cast this spell: Sacrifice a creature"])
    expect(abilities.first.mana_cost.to_s).to eq("{1}{U}")
  end

  it "validates payments, counters, ward, mana colors and the stack-ability filter" do
    expect(errors_for(spell("effects" => [{ "pay" => { "then" => draw } }])))
      .to include(a_string_matching(/needs exactly one of mana, life/))
    expect(errors_for(spell("effects" => [{ "pay" => { "life" => 0 } }]))).to include(a_string_matching(/life: must be an integer >= 1/))
    expect(errors_for(spell("targets" => ["spell"], "effects" => [{ "counter_unless_pays" => { "to" => { "target" => 0 } } }])))
      .to include(a_string_matching(/counter_unless_pays.mana: required/))
    expect(errors_for(creature([{ "ward" => {} }]))).to include(a_string_matching(/ward.cost: required/))
    expect(errors_for(spell("effects" => [{ "add_mana" => { "color" => "any_one", "colors" => ["R"] } }])))
      .to include(a_string_matching(/colors: must list two or more colors/))
    expect(errors_for(spell("targets" => [{ "stack_ability" => { "kind" => "static" } }], "effects" => draw)))
      .to include(a_string_matching(/kind: must be one of activated, triggered/))
    expect(errors_for(spell("effects" => [{ "distribute_counters" => { "counter" => "+1/x" } }])))
      .to include(a_string_matching(/counter: must be a counter name/))
    expect(errors_for(spell("effects" => [{ "draw" => { "amount" => 1, "if" => { "sacrificed" => { "names" => ["x"] } } } }])))
      .to include(a_string_matching(/sacrificed: must be/))
    effects = Enjine::CardDefinition.from_h(spell("targets" => [{ "stack_ability" => { "kind" => "triggered" } }], "effects" => [
                                                    { "pay" => { "mana" => "{1}", "then" => draw, "otherwise" => draw } },
                                                    { "pay" => { "life" => 2 } },
                                                    { "counter_unless_pays" => { "mana" => "{2}", "to" => { "target" => 0 } } },
                                                    { "distribute_counters" => { "counter" => "+1/+1" } },
                                                    { "add_mana" => { "color" => "any_one", "colors" => %w[R G] } },
                                                    { "draw" => { "amount" => 1, "if" => { "kicked" => true } } },
                                                    { "draw" => { "amount" => 1,
                                                                  "if" => { "sacrificed" => { "subtypes" => ["klingon"] } } } }
                                                  ])).spell_ability
    expect(effects.effects.first(5).map(&:to_s)).to eq(["you may pay {1} — if paid: draw 1 → you — if not: draw 1 → you",
                                                        "you may pay 2 life", "counter target #1 unless its controller pays {2}",
                                                        "distribute +1/+1 counters among the targets", "add 1 mana: {R} or {G}"])
    expect(effects.effects.last(2).map { it.condition.to_s }).to eq(["it was kicked", "a sacrificed permanent was klingon"])
    expect(effects.targets.first.to_s).to eq("triggered ability")
    ward = Enjine::CardDefinition.from_h(creature([{ "ward" => { "cost" => "{1}" } }])).abilities.first
    expect([ward.to_s, ward.effects.first.to_s, ward.trigger.to_s])
      .to eq(["Ward {1}", "counter that spell or ability unless its controller pays {1}",
              "When this becomes the target of a spell or ability an opponent controls"])
    expect(Enjine::Mechanics::Condition.build({ "kicked" => false }, [], "c").to_s).to eq("it wasn't kicked")
    filter = Enjine::Mechanics::Filters::StackAbility::Narrowed.new("activated", nil, nil)
    expect([filter.primitive_name, filter.matches_types?([:creature]), filter.matches_facts?(nil),
            filter.live_keys]).to eq(["stack_ability", false, false, []])
  end

  it "validates and describes discard, graveyard, life and behold costs (CR 701.9, 119.4, 701.4)" do
    expect(errors_for(activated("cost" => [{ "discard" => { "count" => 0, "random" => "yes", "card" => 3 } }])))
      .to match(["abilities[0].activated.cost[0].discard.count: must be an integer >= 1",
                 a_string_starting_with("abilities[0].activated.cost[0].discard.card: must be \"card\" or an object"),
                 "abilities[0].activated.cost[0].discard.random: must be true or false"])
    expect(errors_for(activated("cost" => [{ "exile_from_graveyard" => { "count" => 2, "other" => true } }])))
      .to eq(["abilities[0].activated.cost[0].exile_from_graveyard: unknown parameter \"other\""])
    expect(errors_for(activated("cost" => [{ "pay_life" => 0 }, { "pay_life" => "Y" }])))
      .to eq(["abilities[0].activated.cost[0].pay_life: must be an integer >= 1 or \"X\"",
              "abilities[0].activated.cost[1].pay_life: must be an integer >= 1 or \"X\""])
    expect(errors_for(activated("cost" => [{ "behold" => { "exile" => 1 } }])))
      .to eq(["abilities[0].activated.cost[0].behold.card: required", "abilities[0].activated.cost[0].behold.exile: must be true or false"])
    expect(errors_for(spell("effects" => [{ "behold" => {} }]))).to eq(["abilities[0].spell.effects[0].behold.card: required"])
    mana_costs = ["tap", "discard", { "pay_life" => "X" }, { "mana" => "{2/W}" }]
    expect(errors_for(creature([{ "mana" => { "cost" => mana_costs, "produce" => "{C}" } }])))
      .to eq((1..3).map { "abilities[0].mana.cost[#{it}]: a mana ability's cost can't need a choice, X or {2/B}" })
    expect(errors_for(creature([{ "mana" => { "cost" => ["tap"], "color" => "chosen", "colors" => %w[W U] } }])))
      .to eq(["abilities[0].mana.colors: must list two or more colors (W U B R G), with color"])
    costs = Enjine::CardDefinition.from_h(activated("cost" => [
                                                      "discard", { "discard" => { "count" => 2, "random" => true } },
                                                      { "discard" => { "card" => { "types" => ["land"] } } },
                                                      { "exile_from_graveyard" => { "count" => 2, "card" => { "types" => ["creature"] } } },
                                                      { "pay_life" => 2 }, { "pay_life" => "X" },
                                                      { "behold" => { "card" => { "subtypes" => ["goblin"] }, "exile" => true } },
                                                      { "behold" => { "card" => { "subtypes" => ["elf"] }, "count" => 2 } }
                                                    ], "limit" => "once")).abilities.first
    expect(costs.costs.map(&:to_s)).to eq(["Discard a card", "Discard 2 cards at random", "Discard a land card",
                                           "Exile 2 creature cards from your graveyard", "Pay 2 life", "Pay X life",
                                           "Behold a Goblin and exile it", "Behold 2 Elf"])
    expect(costs.to_s).to end_with("(activate only once)")
    additional = Enjine::CardDefinition.from_h(card([{ "additional_cost" => { "cost" => [{ "pay_life" => "X" }] } },
                                                     { "spell" => { "effects" => draw } }])).abilities.first
    expect(additional.to_s).to eq("As an additional cost to cast this spell: Pay X life")
    expect(Enjine::CardDefinition.from_h(creature([{ "mana" => { "cost" => ["tap"], "color" => "chosen" } }])).abilities.first.to_s)
      .to eq("{T}: Add 1 mana of the chosen color.")
    expect(Enjine::Mechanics::Effects::AddMana.build({ "color" => "chosen" }, [], "e").to_s).to eq("add 1 mana of the chosen color")
  end
end
