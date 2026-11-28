# frozen_string_literal: true

# Data validation and text of crimes (CR 700.13), Cases (CR 720.3), harness (CR 701.64), ninjutsu (CR 702.49), Rooms
# (CR 709.5) and face-down permanents (CR 708).
RSpec.describe "Large mechanics: data validation and text" do
  def build(category, data)
    errors = []
    built = Enjine::Mechanics.build_entry(category, data, errors, "x")
    [built, errors]
  end

  def card(abilities, **extra)
    { "name" => "Spec Thing", "mana_cost" => "{1}", "types" => ["enchantment"], "abilities" => abilities }.merge(extra)
  end

  describe "commits_crime (CR 700.13)" do
    it "validates its controller and reads naturally" do
      expect(build(:trigger, { "commits_crime" => { "controller" => "nobody" } }).last.join).to include("controller")
      expect(build(:trigger, { "commits_crime" => {} }).first.to_s).to eq("Whenever you commit a crime")
      expect(build(:trigger,
                   { "commits_crime" => { "controller" => "opponent" } }).first.to_s).to eq("Whenever an opponent commits a crime")
    end
  end

  describe "Cases (CR 720.3, 702.169)" do
    it "needs a condition for to_solve and one static, triggered or activated ability for solved" do
      expect(build(:ability, { "to_solve" => {} }).last.join).to include("must be a condition")
      expect(build(:ability, { "solved" => { "mana" => { "cost" => ["tap"], "produce" => "{W}" } } }).last.join)
        .to include("must be one static, triggered or activated ability")
      expect(build(:ability, { "solved" => { "static" => "oops" } }).last.join).to include("must be one static")
    end

    it "joins a Solved ability's own condition with being solved (CR 702.169b)" do
      static, errors = build(:ability, { "solved" => { "static" => { "affects" => "self", "if" => { "your_turn" => true },
                                                                     "pump" => { "power" => 1, "toughness" => 1 } } } })
      expect(errors).to be_empty
      expect(static.condition.to_s).to include("this permanent is solved")
    end

    it "validates the designation conditions and describes the solve effect" do
      expect(build(:ability, { "activated" => { "cost" => ["tap"], "only_if" => { "solved" => "yes" },
                                                "effects" => [{ "draw" => { "amount" => 1 } }] } }).last.join)
        .to include("must be true or false")
      expect(build(:effect, { "solve" => {} }).first.to_s).to include("becomes solved")
      expect(build(:effect, { "harness" => {} }).first.to_s).to start_with("harness")
    end
  end

  describe "exile_permanent (CR 601.2h)" do
    it "reads as a cost" do
      expect(build(:cost, { "exile_permanent" => { "filter" => "creature" } }).first.to_s).to eq("Exile a creature you control")
    end
  end

  describe "ninjutsu (CR 702.49)" do
    it "needs a cost" do
      expect(build(:ability, { "ninjutsu" => {} }).last.join).to include("cost: required")
      ability, = build(:ability, { "ninjutsu" => { "cost" => "{U}" } })
      expect([ability.to_s, ability.zone, ability.costs.map(&:to_s)])
        .to eq(["Ninjutsu {U}", :hand, ["{U}", "Reveal this card from your hand",
                                        "Return an unblocked attacking creature you control to its owner's hand"]])
      expect(ability.costs[2].what).to include("unblocked")
      expect(ability.effects.first.to_s).to include("tapped and attacking")
    end
  end

  describe "Rooms (CR 709.5)" do
    it "validates the door trigger and combines keywords and colors of the doors" do
      expect(build(:trigger, { "unlocks_door" => { "door" => "middle" } }).last.join).to include("door")
      expect(build(:trigger, { "unlocks_door" => { "door" => "left" } }).first.to_s).to eq("When you unlock the left door of this")
      expect(build(:trigger, { "unlocks_door" => { "door" => "any" } }).first.to_s).to eq("When you unlock a door of this")
      room = { "name" => "Spec Left // Spec Right", "layout" => "room", "faces" => [
        { "name" => "Spec Left", "mana_cost" => "{W}", "types" => ["enchantment"], "subtypes" => ["room"], "colors" => ["W"] },
        { "name" => "Spec Right", "types" => ["enchantment"], "subtypes" => ["room"], "keywords" => ["flash"] }
      ] }
      defn = Enjine::CardDefinition.from_h(room)
      expect([defn.name, defn.mana_cost.to_s, defn.colors, defn.keywords]).to eq(["Spec Left // Spec Right", "{W}", [:W], [:flash]])
      expect(defn.faces.size).to eq(4)
      expect(defn.face(3).name).to eq("")
      sorcery = room.merge("faces" => room["faces"].map { it.merge("types" => ["sorcery"]) })
      expect { Enjine::CardDefinition.from_h(sorcery) }.to raise_error(Enjine::InvalidCardDefinition, /is a permanent card/)
    end
  end

  describe "face-down permanents (CR 708)" do
    it "validates morph and disguise costs and describes the effects" do
      expect(build(:ability, { "morph" => { "cost" => [{ "pay_life" => { "amount" => 2 } }] } }).last.join).to include("must be mana")
      expect(build(:ability, { "disguise" => { "cost" => "{2}{G}" } }).first.to_s).to eq("Disguise {2}{G}")
      expect(build(:effect, { "manifest" => {} }).first.to_s).to eq("you manifest the top card of their library")
      expect(build(:effect, { "cloak" => { "amount" => 2, "to" => "each_opponent" } }).first.to_s)
        .to eq("each opponent cloaks the top card of their library 2 times")
      expect(build(:effect, { "manifest_dread" => {} }).first.to_s).to eq("manifest dread")
      expect(build(:trigger, { "turned_face_up" => {} }).first.to_s).to eq("When this is turned face up")
    end

    it "knows the face-down characteristics in every catalog" do
      catalog = Enjine::Catalog.new
      expect(catalog.include?("face_down_ward")).to be(true)
      expect(catalog["face_down_2_2"].name).to eq("")
      expect(catalog.fetch("face_down_2_2").token?).to be(false)
    end
  end
end
