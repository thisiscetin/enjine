# frozen_string_literal: true

# Validation of crew and Vehicles (CR 702.122, 301.7), type-changing effects (CR 205.1b), exhaust (CR 702.177) and
# start your engines! / max speed (CR 702.178, 702.179).
RSpec.describe "Vehicles, type changes, exhaust and speed validation" do
  def errors_for(card)
    Enjine::CardDefinition.from_h(card)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def vehicle(*abilities, **extra)
    { "name" => "Test Buggy", "mana_cost" => "{2}", "types" => ["artifact"], "subtypes" => ["vehicle"], "power" => 3,
      "toughness" => 2, "abilities" => abilities }.merge(extra.transform_keys(&:to_s))
  end

  def activated(effect, **extra) = { "activated" => { "cost" => ["tap"], "effects" => [effect] }.merge(extra.transform_keys(&:to_s)) }

  describe "crew (CR 702.122)" do
    it "is an activated ability with a crew cost; a Vehicle may have printed power and toughness (CR 301.7a)" do
      defn = Enjine::CardDefinition.from_h(vehicle({ "crew" => { "power" => 2 } }))
      crew = defn.ability("printed:0")
      expect(crew).to have_attributes(kind: :activated, power: 2, to_s: "Crew 2", sorcery_speed?: false)
      expect(crew.costs.first.to_s).to eq("Tap any number of other untapped creatures you control with total power 2 or greater")
      expect(crew.effects.first.to_s).to eq("this becomes an artifact creature until end of turn")
      expect(defn.power).to eq(3)
    end

    it "reports path-addressed errors" do
      expect(errors_for(vehicle({ "crew" => { "power" => 0 } }))).to include("abilities[0].crew.power: must be an integer >= 1")
      expect(errors_for(vehicle({ "crew" => { "power" => 1, "cost" => [] } })))
        .to include("abilities[0].crew: unknown parameter \"cost\"")
      expect(errors_for(vehicle.merge("subtypes" => [])))
        .to include("power/toughness: only creatures and Vehicles have power and toughness")
    end

    it "has crew triggers" do
      defn = Enjine::CardDefinition.from_h(vehicle(
                                             { "triggered" => { "when" => { "becomes_crewed" => {} },
                                                                "effects" => [{ "draw" => { "amount" => 1 } }] } },
                                             { "triggered" => { "when" => { "crews_vehicle" => { "subject" => { "each" => "creature" } } },
                                                                "effects" => [{ "draw" => { "amount" => 1 } }] } }
                                           ))
      expect(defn.ability("printed:0").to_s).to start_with("Whenever this becomes crewed")
      expect(defn.ability("printed:1").to_s).to start_with("Whenever creature crews a Vehicle")
      expect(errors_for(vehicle({ "triggered" => { "when" => { "crews_vehicle" => { "subject" => 3 } }, "effects" => [] } })))
        .to include(a_string_matching(/crews_vehicle\.subject: must be/))
    end
  end

  describe "become and static types (CR 205.1b, 613.1d-e)" do
    let(:become) do
      { "types" => %w[artifact creature], "supertypes" => ["legendary"], "subtypes" => ["construct"], "colors" => ["U"],
        "keywords" => ["flying"], "duration" => "indefinite", "to" => "self" }
    end

    it "adds card types, supertypes and subtypes, sets colors and grants keywords" do
      effect = Enjine::CardDefinition.from_h(vehicle(activated({ "become" => become }))).ability("printed:0").effects.first
      expect(effect).to have_attributes(card_types: %i[artifact creature], supertypes: [:legendary], subtypes: ["construct"],
                                        colors: ["U"], keywords: [:flying])
      expect(effect.to_s).to eq("becomes legendary U construct artifact creature, flying → itself")
    end

    it "reports path-addressed errors" do
      path = "abilities[0].activated.effects[0].become"
      expect(errors_for(vehicle(activated({ "become" => { "types" => ["instant"], "to" => "self" } }))))
        .to include(a_string_matching(/#{Regexp.escape(path)}\.types: must be a non-empty list of types \(artifact, creature/))
      expect(errors_for(vehicle(activated({ "become" => { "colors" => ["X"], "keywords" => ["zooming"], "to" => "self" } }))))
        .to include("#{path}.colors: must be a list of W, U, B, R, G ([] for colorless)",
                    a_string_matching(/#{Regexp.escape(path)}\.keywords: must be a non-empty list of keywords/))
      expect(errors_for(vehicle(activated({ "become" => { "subtypes" => ["Big Bad"], "supertypes" => "legendary", "to" => "self" } }))))
        .to include("#{path}.subtypes: must be a non-empty list of lowercase subtypes",
                    a_string_matching(/#{Regexp.escape(path)}\.supertypes: must be a non-empty list of supertypes/))
    end

    it "a static ability adds card types" do
      static = { "static" => { "affects" => "self", "types" => %w[artifact creature] } }
      expect(Enjine::CardDefinition.from_h(vehicle(static)).ability("printed:0").to_s).to eq("it gets types artifact creature")
      expect(errors_for(vehicle({ "static" => { "affects" => "self", "types" => ["planeswalker"] } })))
        .to include(a_string_matching(/abilities\[0\]\.static\.types: must be a non-empty list of types/))
    end
  end

  describe "exhaust (CR 702.177)" do
    it "marks an activated ability, and activates_ability can watch for exhaust abilities" do
      card = vehicle(activated({ "draw" => { "amount" => 1 } }, exhaust: true),
                     { "triggered" => { "when" => { "activates_ability" => { "exhaust" => true } },
                                        "effects" => [{ "draw" => { "amount" => 1 } }] } })
      defn = Enjine::CardDefinition.from_h(card)
      expect(defn.ability("printed:0")).to have_attributes(exhaust?: true)
      expect(defn.ability("printed:0").to_s).to eq("Exhaust — {T}: draw 1 → you")
      expect(defn.ability("printed:1").to_s).to start_with("Whenever you activate an exhaust ability")
    end

    it "reports path-addressed errors" do
      expect(errors_for(vehicle(activated({ "draw" => { "amount" => 1 } }, exhaust: "yes"))))
        .to include("abilities[0].activated.exhaust: must be true or false")
      expect(errors_for(vehicle({ "triggered" => { "when" => { "activates_ability" => { "exhaust" => 1 } }, "effects" => [] } })))
        .to include("abilities[0].triggered.when.activates_ability.exhaust: must be true or false")
    end
  end

  describe "start your engines! and max speed (CR 702.178, 702.179)" do
    it "the keyword carries the speed trigger, which never triggers from the permanent itself" do
      defn = Enjine::CardDefinition.from_h(vehicle(keywords: ["start your engines"]))
      speed = defn.ability("keyword:start_your_engines")
      expect(speed).to have_attributes(kind: :triggered, zone: :rules)
      expect(speed.to_s).to eq("Whenever one or more opponents lose life during your turn, if the speed of you is at most 3, " \
                               "your speed increases by 1 (only once each turn)")
      expect(speed.trigger.watches?(nil)).to be(false)
      expect(speed.trigger.leaves_battlefield?).to be(false)
    end

    it "max speed nests keywords and abilities" do
      draw = activated({ "draw" => { "amount" => 1 } })
      defn = Enjine::CardDefinition.from_h(vehicle({ "max_speed" => { "keywords" => ["haste"], "abilities" => [draw] } }))
      expect(defn.nested_instances("printed:0").map(&:ref)).to eq(["printed:0:0"])
      expect(defn.ability("printed:0").to_s).to eq("Max speed — haste; {T}: draw 1 → you")
    end

    it "reports path-addressed errors" do
      expect(errors_for(vehicle({ "max_speed" => {} }))).to include("abilities[0].max_speed: needs keywords or abilities")
      expect(errors_for(vehicle({ "max_speed" => { "abilities" => [{ "max_speed" => { "keywords" => ["haste"] } }] } })))
        .to include("abilities[0].max_speed.abilities[0]: max speed abilities can't be nested")
      expect(errors_for(vehicle({ "max_speed" => { "keywords" => ["warp"], "power" => 1 } })))
        .to include("abilities[0].max_speed: unknown parameter \"power\"",
                    a_string_matching(/max_speed\.keywords: unknown keyword "warp"/))
    end

    it "speed is an amount and max speed a condition" do
      errors = []
      condition = Enjine::Mechanics::Condition.build({ "max_speed" => true }, errors, "if")
      expect(condition.to_s).to eq("you have max speed")
      expect(Enjine::Mechanics::Condition.build({ "max_speed" => false }, errors, "if").to_s).to eq("you don't have max speed")
      expect(Enjine::Mechanics::Amount.build({ "speed" => "you" }, errors, "amount", targets_count: 0).to_s).to eq("the speed of you")
      expect(errors).to be_empty
    end
  end
end
