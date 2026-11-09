# frozen_string_literal: true

# Validation and path-addressed errors for casting and mana primitives: divided damage (CR 601.2d), "you can't cast
# this spell unless" (601.3), amounts compared with amounts, mana_value / greatest_toughness / turns_taken, the
# exile_instead rider (614.1a), spend_only from a zone and only_if on mana abilities (106.6, 602.5b), and the
# sources of mana spent (mana_spent from).
RSpec.describe "Casting and mana primitives: validation" do
  def errors_for(card)
    Enjine::CardDefinition.from_h(card)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def spell(body) = { "name" => "Spec Unit Spell", "mana_cost" => "{1}", "types" => ["sorcery"], "abilities" => [{ "spell" => body }] }

  def creature(*abilities)
    { "name" => "Spec Unit Creature", "mana_cost" => "{1}", "types" => ["creature"], "power" => 1,
      "toughness" => 1, "abilities" => abilities }
  end

  def amount_errors(amount, targets: [])
    errors_for(spell({ "targets" => targets, "effects" => [{ "gain_life" => { "amount" => amount } }] }))
  end

  describe "divide (CR 601.2d)" do
    it "takes an amount and a counted target, and refuses an optional single target" do
      ok = { "targets" => [{ "filter" => "any_target", "count" => 3, "optional" => true }],
             "divide" => { "count" => { "each" => "land", "controller" => "you" } }, "effects" => [{ "distribute_damage" => {} }] }
      expect(errors_for(spell(ok))).to eq([])
      bad = ok.merge("targets" => [{ "filter" => "any_target", "optional" => true }], "divide" => 0)
      expect(errors_for(spell(bad))).to include(a_string_starting_with("abilities[0].spell.divide: must be an integer >= 1"),
                                                "abilities[0].spell.divide: needs a first target that isn't optional")
    end

    it "is checked on a reflexive trigger too" do
      effect = { "reflexive_trigger" => { "targets" => [{ "filter" => "any_target", "optional" => true }], "divide" => 2,
                                          "effects" => [{ "distribute_damage" => {} }] } }
      expect(errors_for(spell({ "effects" => [effect] })))
        .to eq(["abilities[0].spell.effects[0].reflexive_trigger.divide: needs a first target that isn't optional"])
    end
  end

  describe "cast_restriction (CR 601.3)" do
    it "needs only_if, a condition" do
      expect(errors_for(creature({ "cast_restriction" => {} }))).to eq(["abilities[0].cast_restriction.only_if: required"])
      expect(errors_for(creature({ "cast_restriction" => { "only_if" => 3 } })))
        .to eq(["abilities[0].cast_restriction.only_if: must be a condition object"])
      expect(errors_for(creature({ "cast_restriction" => { "only_if" => { "amount" => { "turns_taken" => "you" }, "at_least" => 4 } } })))
        .to eq([])
    end
  end

  describe "amounts" do
    it "accepts mana_value, greatest_toughness and turns_taken, and amounts as comparison bounds" do
      expect(amount_errors({ "mana_value" => { "target" => 0 } }, targets: ["spell"])).to eq([])
      expect(amount_errors({ "greatest_toughness" => { "each" => "creature", "controller" => "you" } })).to eq([])
      condition = { "amount" => { "life" => "you" }, "at_most" => { "plus" => [{ "mana_value" => { "target" => 0 } }, -1] } }
      expect(errors_for(spell({ "targets" => ["spell"], "effects" => [{ "draw" => { "amount" => 1, "if" => condition } }] }))).to eq([])
      bad = condition.merge("at_most" => "lots")
      expect(errors_for(spell({ "targets" => ["spell"], "effects" => [{ "draw" => { "amount" => 1, "if" => bad } }] })))
        .to include(a_string_starting_with("abilities[0].spell.effects[0].draw.if.at_most: must be an integer"))
    end

    it "mana_spent from takes a card spec and no color" do
      expect(amount_errors({ "mana_spent" => { "from" => { "subtypes" => ["treasure"] } } })).to eq([])
      expect(amount_errors({ "mana_spent" => { "from" => { "subtypes" => ["treasure"] }, "color" => "R" } }))
        .to include("abilities[0].spell.effects[0].gain_life.amount.mana_spent: from can't be used with color or colors")
    end
  end

  describe "exile_instead (CR 614.1a)" do
    it "is true or a card spec on cast_free, cast and play_permission" do
      %w[cast_free cast play_permission].each do |kind|
        effect = { kind => { "to" => { "target" => 0 }, "exile_instead" => { "types" => ["instant"] } } }
        expect(errors_for(spell({ "targets" => [{ "graveyard_card" => {} }], "effects" => [effect] }))).to eq([])
        effect = { kind => { "to" => { "target" => 0 }, "exile_instead" => { "colour" => "red" } } }
        expect(errors_for(spell({ "targets" => [{ "graveyard_card" => {} }], "effects" => [effect] })))
          .to include(a_string_starting_with("abilities[0].spell.effects[0].#{kind}.exile_instead"))
      end
    end
  end

  describe "mana abilities" do
    it "spend_only takes from / not_from a zone" do
      mana = ->(spend) { creature({ "mana" => { "cost" => ["tap"], "produce" => "{U}", "spend_only" => spend } }) }
      expect(errors_for(mana.call({ "not_from" => "hand" }))).to eq([])
      expect(errors_for(mana.call({ "from" => "pocket" })))
        .to include(a_string_starting_with("abilities[0].mana.spend_only.from: must be one of"))
      expect(Enjine::CardDefinition.from_h(mana.call({ "not_from" => "hand" })).abilities.first.to_s)
        .to eq("{T}: Add {U}. Spend this mana only to cast spells from anywhere other than your hand.")
    end

    it "only_if is a condition" do
      ability = { "mana" => { "cost" => ["tap"], "produce" => "{G}", "only_if" => { "your_turn" => true } } }
      expect(Enjine::CardDefinition.from_h(creature(ability)).abilities.first.to_s).to eq("{T}: Add {G}. Activate only if it's your turn.")
      expect(errors_for(creature({ "mana" => ability["mana"].merge("only_if" => "sometimes") })))
        .to eq(["abilities[0].mana.only_if: must be a condition object"])
    end
  end
end
