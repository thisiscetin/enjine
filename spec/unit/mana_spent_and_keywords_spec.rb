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
      { "name" => "Spec Unit Golem", "mana_cost" => "{2}", "types" => %w[artifact creature], "power" => 0, "toughness" => 0,
        "abilities" => [{ "enters_with_counters" => ability }] }
    end

    it "takes an amount for its own counters, and describes it" do
      expect(errors_for(golem({ "+1/+1" => { "mana_spent" => { "colors" => true } } }))).to eq([])
      defn = Enjine::CardDefinition.from_h(golem({ "+1/+1" => { "mana_spent" => {} }, "charge" => 1 }))
      expect(defn.abilities.first.to_s)
        .to eq("enters with 1 charge counter and +1/+1 counters equal to the amount of mana spent to cast it")
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

  describe "keyword actions and abilities" do
    def effect_errors(effect, targets: []) = errors_for(spell_with(effect, targets: targets))

    def creature_with(abilities, keywords: [], subtypes: [], types: ["creature"])
      card = { "name" => "Spec Unit Body", "mana_cost" => "{1}", "types" => types, "abilities" => abilities }
      card.merge!("power" => 1, "toughness" => 1) if types.include?("creature")
      card["keywords"] = keywords unless keywords.empty?
      card["subtypes"] = subtypes unless subtypes.empty?
      card
    end

    it "accepts the documented shapes" do
      expect(effect_errors({ "blight" => { "amount" => 2, "to" => "each_opponent" } })).to eq([])
      expect(effect_errors({ "connive" => { "amount" => { "count" => { "each" => "creature" } } } })).to eq([])
      expect(effect_errors({ "recruit" => {} })).to eq([])
      expect(effect_errors({ "amass" => { "subtype" => "goblin", "amount" => "x" } })).to eq([])
      expect(effect_errors({ "empower_jace" => { "amount" => 2 } })).to eq([])
      expect(effect_errors({ "endure" => { "amount" => 0 } })).to eq([])
      expect(effect_errors({ "add_mana" => { "produce" => "{R}", "until" => "end_of_combat" } })).to eq([])
      expect(effect_errors({ "create_token" => { "token" => "Treasure", "attacking" => true } })).to eq([])
      expect(errors_for(creature_with([{ "mobilize" => { "amount" => 1 } }, { "firebending" => { "amount" => "x" } }]))).to eq([])
      expect(errors_for(spell_with({ "draw" => { "amount" => 1 } }).merge("types" => %w[kindred sorcery]))).to eq([])
    end

    it "names the path of each mistake" do
      at = "abilities[0].spell.effects[0]"
      expect(effect_errors({ "blight" => { "amount" => 1, "count" => 2 } })).to include(a_string_starting_with("#{at}.blight"))
      expect(effect_errors({ "amass" => { "subtype" => "Army", "amount" => 1 } }))
        .to include("#{at}.amass.subtype: must be a lowercase creature type other than army")
      expect(effect_errors({ "amass" => { "subtype" => "orc" } })).to include("#{at}.amass.amount: required")
      expect(effect_errors({ "endure" => { "amount" => "x" } }))
        .to include("#{at}.endure.amount: must be an integer from 0 to 99 (the Spirit token's size)")
      expect(effect_errors({ "add_mana" => { "produce" => "{R}", "until" => "end_of_turn" } }))
        .to include("#{at}.add_mana.until: must be \"end_of_combat\"")
      expect(errors_for(creature_with([{ "mobilize" => {} }]))).to include("abilities[0].mobilize.amount: required")
      expect(errors_for(creature_with([{ "firebending" => { "amount" => -1 } }])))
        .to include(a_string_starting_with("abilities[0].firebending.effects[0].add_mana.amount"))
      expect(errors_for(creature_with([], keywords: ["job_select"]))).to include("keywords: job_select is only for Equipment")
      expect(errors_for(creature_with([], keywords: ["job_select"], subtypes: ["equipment"], types: ["artifact"]))).to eq([])
      expect(errors_for(spell_with({ "draw" => { "amount" => 1 } }).merge("types" => ["kindred"])))
        .to include("types: a kindred card needs another card type (CR 308.1)")
      cost = { "additional_cost" => { "cost" => [{ "blight" => { "amount" => 0 } }] } }
      body = spell_with({ "draw" => { "amount" => 1 } })
      expect(errors_for(body.merge("abilities" => [cost, body["abilities"][0]])))
        .to include(a_string_starting_with("abilities[0].additional_cost.cost[0].blight.amount"))
    end

    it "describes each one" do
      text = lambda do |effect|
        Enjine::CardDefinition.from_h(spell_with(effect)).spell_ability.effects.first.to_s
      end
      expect(text.call({ "blight" => { "amount" => 2 } })).to eq("blight 2 → you")
      expect(text.call({ "connive" => {} })).to eq("connive 1 → itself")
      expect(text.call({ "recruit" => {} })).to eq("recruit → you")
      expect(text.call({ "amass" => { "subtype" => "orc", "amount" => 2 } })).to eq("amass orc 2")
      expect(text.call({ "empower_jace" => { "amount" => 3 } })).to eq("empower Jace 3")
      expect(text.call({ "endure" => { "amount" => 2 } })).to eq("endure 2 → itself")
      expect(text.call({ "create_token" => { "token" => "Treasure", "tapped" => true, "attacking" => true } }))
        .to eq("create 1 Treasure token tapped attacking → you")
      body = Enjine::CardDefinition.from_h(creature_with([{ "mobilize" => { "amount" => 2 } }, { "firebending" => { "amount" => "x" } },
                                                          { "additional_cost" => { "cost" => [{ "blight" => { "amount" => 1 } }] } }]))
      expect(body.abilities.map(&:to_s).first(2)).to eq(["Mobilize 2", "Firebending X"])
      expect(body.abilities[2].costs.first.to_s).to eq("Blight 1")
    end
  end

  describe "mana kept until end of combat in snapshots and views (CR 702.189a)" do
    let(:game) do
      build_game do
        turn 3, active: "alice", step: :declare_attackers
        player("alice")
        player("bob")
      end
    end

    it "validates the entry" do
      data = game.state.to_h
      data["players"][0]["restricted_mana"] = [{ "mana" => "R", "until" => "end_of_combat" }]
      expect(Enjine::Snapshot.validate(data, game.catalog)).to eq([])
      data["players"][0]["restricted_mana"] = [{ "mana" => "R" }, { "mana" => "R", "until" => "end_of_turn" }]
      expect(Enjine::Snapshot.validate(data, game.catalog).size).to eq(2)
    end

    it "shows both a restriction and the duration" do
      entry = { "mana" => "C", "spend_only" => { "spells" => "card" }, "until" => "end_of_combat" }
      expect(Enjine::View.pool_entry_text(entry))
        .to eq("spend this mana only to cast card spells; you don't lose this mana until end of combat")
      expect(Enjine::Engine::ManaSources.mana_kept?(entry, :declare_attackers)).to be(true)
      expect(Enjine::Engine::ManaSources.mana_kept?(entry, :end_of_combat)).to be(false)
      expect(Enjine::Engine::ManaSources.mana_kept?(entry.except("until"), :declare_attackers)).to be(false)
    end
  end
end
