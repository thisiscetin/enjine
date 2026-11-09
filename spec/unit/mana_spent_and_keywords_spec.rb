# frozen_string_literal: true

# Validation and path-addressed errors for the mana-spent amount (CR 601.2h) and the keyword abilities and
# actions built from card data (prowess, connive, amass, ...).
RSpec.describe "Mana spent and keyword primitives: validation" do
  def errors_for(card)
    Enjine::CardDefinition.from_h(card)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def spell_with(effect, targets: [])
    { "name" => "Spec Unit Spell", "mana_cost" => "{1}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => [effect] } }] }
  end

  def amount_errors(amount, targets: [])
    errors_for(spell_with({ "gain_life" => { "amount" => amount } }, targets: targets))
  end

  describe "the mana_spent amount" do
    it "accepts each form" do
      expect(amount_errors({ "mana_spent" => {} })).to eq([])
      expect(amount_errors({ "mana_spent" => { "colors" => true } })).to eq([])
      expect(amount_errors({ "mana_spent" => { "color" => "C" } })).to eq([])
      expect(amount_errors({ "mana_spent" => { "of" => { "triggering" => "object" } } })).to eq([])
      expect(amount_errors({ "mana_spent" => { "of" => { "target" => 0 } } }, targets: ["spell"])).to eq([])
    end

    it "names the path of each mistake" do
      path = "abilities[0].spell.effects[0].gain_life.amount.mana_spent"
      expect(amount_errors({ "mana_spent" => "self" })).to include("#{path}: must be an object")
      expect(amount_errors({ "mana_spent" => { "color" => "Q" } })).to include(a_string_starting_with("#{path}.color: must be one of"))
      expect(amount_errors({ "mana_spent" => { "colors" => 2 } })).to include("#{path}.colors: must be true")
      expect(amount_errors({ "mana_spent" => { "color" => "W", "colors" => true } }))
        .to include("#{path}: color and colors can't be used together")
      expect(amount_errors({ "mana_spent" => { "of" => "you" } })).to include(a_string_starting_with("#{path}.of: must be"))
      expect(amount_errors({ "mana_spent" => { "of" => { "triggering" => "player" } } }))
        .to include(a_string_starting_with("#{path}.of: must be"))
      expect(amount_errors({ "mana_spent" => { "of" => { "target" => 0 } } })).to include(a_string_starting_with("#{path}.of.target"))
      expect(amount_errors({ "mana_spent" => { "mana" => 1 } })).to include(a_string_starting_with(path))
    end

    it "describes itself" do
      errors = []
      text = ->(data) { Enjine::Mechanics::Amount.build({ "mana_spent" => data }, errors, "x", targets_count: 1).to_s }
      expect(text.call({})).to eq("the amount of mana spent to cast it")
      expect(text.call({ "colors" => true })).to eq("the number of colors of mana spent to cast it")
      expect(text.call({ "color" => "R", "of" => { "target" => 0 } })).to eq("the amount of {R} spent to cast target #1")
      expect(errors).to eq([])
    end
  end

  describe "enters_with_counters with a computed count" do
    def golem(counters, affects: nil)
      ability = { "counters" => counters }
      ability["affects"] = affects if affects
      { "name" => "Spec Unit Golem", "mana_cost" => "{2}", "types" => ["artifact", "creature"], "power" => 0, "toughness" => 0,
        "abilities" => [{ "enters_with_counters" => ability }] }
    end

    it "takes an amount for its own counters, and describes it" do
      expect(errors_for(golem({ "+1/+1" => { "mana_spent" => { "colors" => true } } }))).to eq([])
      defn = Enjine::CardDefinition.from_h(golem({ "+1/+1" => { "mana_spent" => {} }, "charge" => 1 }))
      expect(defn.abilities.first.to_s).to eq("enters with 1 charge counter and +1/+1 counters equal to the amount of mana spent to cast it")
    end

    it "rejects an amount for permanents it affects" do
      expect(errors_for(golem({ "+1/+1" => { "mana_spent" => {} } }, affects: { "each" => "creature" })))
        .to include("abilities[0].enters_with_counters.counters.+1/+1: must be an integer >= 1")
    end
  end

  describe "prowess" do
    it "is a keyword standing for a triggered ability (CR 702.108a)" do
      defn = Enjine::CardDefinition.from_h({ "name" => "Spec Unit Monk", "mana_cost" => "{R}", "types" => ["creature"],
                                             "keywords" => ["prowess"], "power" => 1, "toughness" => 1 })
      expect(defn.ability_instances.map(&:ref)).to eq(["keyword:prowess"])
      expect(defn.ability("keyword:prowess").kind).to eq(:triggered)
      expect(Enjine::CardDefinition.from_h({ "name" => "Spec Unit Bear", "mana_cost" => "{G}", "types" => ["creature"],
                                             "power" => 1, "toughness" => 1 }).ability("keyword:prowess").kind).to eq(:triggered)
    end

    it "fails loudly if a keyword's own data is wrong" do
      expect { Enjine::Mechanics::Keywords.ability_from_data({ "triggered" => {} }, "broken") }
        .to raise_error(ArgumentError, /keyword:broken/)
    end
  end
end
