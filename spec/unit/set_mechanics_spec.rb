# frozen_string_literal: true

# Validation of the Star Trek set mechanics and Sagas (rule numbers from the 2026-11-06 CR).
RSpec.describe "Set mechanics validation" do
  def errors_for(card)
    Enjine::CardDefinition.from_h(card)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def spacecraft(*abilities)
    { "name" => "Test Hull", "mana_cost" => "{2}", "types" => ["artifact"], "subtypes" => ["spacecraft"],
      "keywords" => ["station"], "abilities" => abilities }
  end

  def saga(*abilities, types: ["enchantment"])
    { "name" => "Test Annals", "mana_cost" => "{1}", "types" => types, "subtypes" => ["saga"], "abilities" => abilities }
  end

  describe "station_symbol (CR 722.2)" do
    it "accepts keywords, abilities and a power/toughness box; nested abilities get their own refs" do
      attack = { "triggered" => { "when" => { "attacks" => {} }, "effects" => [{ "draw" => { "amount" => 1 } }] } }
      symbol = { "at" => 5, "power" => 3, "toughness" => 2, "keywords" => ["Flying"], "abilities" => [attack] }
      defn = Enjine::CardDefinition.from_h(spacecraft({ "station_symbol" => symbol }))
      expect(defn.ability_instances.map(&:ref)).to eq(%w[printed:0 keyword:station])
      expect(defn.nested_instances("printed:0").map(&:ref)).to eq(["printed:0:0"])
      expect(defn.ability("printed:0:0").kind).to eq(:triggered)
      expect(defn.ability("printed:0").to_s).to eq("5+ | 3/2 creature; flying; Whenever this attacks, draw 1 → you")
      expect(defn.triggered?).to be(true)
      expect(defn.ability("keyword:station").to_s).to start_with("Tap another untapped creature you control: put charge")
    end

    it "reports path-addressed errors" do
      expect(errors_for(spacecraft({ "station_symbol" => { "at" => 0, "power" => 2 } })))
        .to include(a_string_matching(/abilities\[0\]\.station_symbol\.at: must be an integer >= 1/),
                    a_string_matching(/station_symbol: power and toughness must both be integers/))
      expect(errors_for(spacecraft({ "station_symbol" => { "at" => 2 } })))
        .to include(a_string_matching(%r{station_symbol: needs power/toughness, keywords or abilities}))
      expect(errors_for(spacecraft({ "station_symbol" => { "at" => 2, "keywords" => ["warp"], "color" => "red" } })))
        .to include(a_string_matching(/keywords: unknown keyword "warp"/), a_string_matching(/unknown parameter "color"/))
      expect(errors_for(spacecraft({ "station_symbol" => { "at" => 2,
                                                           "abilities" => [{ "station_symbol" => { "at" => 3,
                                                                                                   "keywords" => ["flying"] } }] } })))
        .to include(a_string_matching(/abilities\[0\]: station symbols can't be nested/))
      expect(errors_for(spacecraft({ "station_symbol" => { "at" => 2, "abilities" => [{ "warp" => {} }] } })))
        .to include(a_string_matching(/station_symbol.abilities\[0\]: unknown ability "warp"/))
    end

    it "station cards keep power/toughness off the card itself (CR 722.2c)" do
      expect(errors_for(spacecraft.merge("power" => 2, "toughness" => 2))).to include(a_string_matching(/only creatures have power/))
    end
  end

  describe "tap_another_creature cost (CR 702.184a)" do
    it "takes no parameters and can be used by any activated ability" do
      card = { "name" => "Test Rig", "mana_cost" => "{1}", "types" => ["artifact"],
               "abilities" => [{ "activated" => { "cost" => ["tap_another_creature"], "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
      expect(errors_for(card)).to eq([])
      expect(errors_for(card.merge("abilities" => [{ "activated" => { "cost" => [{ "tap_another_creature" => { "n" => 2 } }],
                                                                      "effects" => [{ "draw" => { "amount" => 1 } }] } }])))
        .to include(a_string_matching(/tap_another_creature: unknown parameter "n"/))
    end
  end

  describe "chapter abilities and the saga subtype (CR 715.2)" do
    it "needs a chapter number and an enchantment" do
      expect(errors_for(saga({ "chapter" => { "effects" => [{ "draw" => { "amount" => 1 } }] } })))
        .to include(a_string_matching(/abilities\[0\]\.chapter\.chapter: must be an integer >= 1/))
      expect(errors_for(saga({ "chapter" => { "chapter" => 1, "draw" => 1 } })))
        .to include(a_string_matching(/chapter: unknown parameter "draw"/))
      expect(errors_for(saga({ "chapter" => { "chapter" => 1, "effects" => [] } }, types: ["artifact"])))
        .to include(a_string_matching(/saga is only valid for enchantment cards/),
                    a_string_matching(/chapter abilities need a enchantment card/))
    end

    it "describes itself and accepts modes" do
      modes = [{ "effects" => [{ "draw" => { "amount" => 1 } }] }, { "effects" => [{ "gain_life" => { "amount" => 1 } }] }]
      defn = Enjine::CardDefinition.from_h(saga({ "chapter" => { "chapter" => 2, "modes" => modes } }))
      ability = defn.ability("printed:0")
      expect(ability).to have_attributes(kind: :triggered, chapter: 2, condition: nil)
      expect(ability.to_s).to start_with("Chapter 2 — choose 1")
      expect(ability.trigger.to_s).to eq("Chapter 2")
    end
  end

  describe "faces_dilemma trigger (CR 700.17)" do
    it "validates its controller and describes itself" do
      errors = []
      built = Enjine::Mechanics.build_entry(:trigger, { "faces_dilemma" => { "controller" => "nobody" } }, errors, "when")
      expect(errors).to include(a_string_matching(/when.faces_dilemma.controller: must be one of you, opponent, any/))
      expect(built.to_s).to eq("Whenever a player faces a dilemma")
      %w[you opponent].each do |who|
        trigger = Enjine::Mechanics.build_entry(:trigger, { "faces_dilemma" => { "controller" => who } }, [], "when")
        expect(trigger.to_s).to match(/\AWhenever (you face|an opponent faces) a dilemma\z/)
      end
    end
  end

  describe "assimilate and graveyard_card" do
    it "builds with a target and describes itself" do
      errors = []
      effect = Enjine::Mechanics.build_entry(:effect, { "assimilate" => { "to" => { "target" => 0 } } }, errors, "e", targets_count: 1)
      expect(errors).to eq([])
      expect(effect.to_s).to eq("assimilate → target #1")
      filter = Enjine::Mechanics.build_entry(:filter, { "graveyard_card" => { "any_of" => ["creature"] } }, errors, "t")
      expect(errors).to eq([])
      expect(filter.to_s).to eq("creature")
    end
  end

  describe "distinct_names amount" do
    it "is a known amount kind" do
      errors = []
      amount = Enjine::Mechanics::Amount.build({ "distinct_names" => { "each" => "land", "controller" => "you" } }, errors, "a",
                                               targets_count: 0)
      expect(errors).to eq([])
      expect(amount.to_s).to eq("the distinct names of each land you control")
    end
  end
end
