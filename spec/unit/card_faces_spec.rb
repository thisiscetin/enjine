# frozen_string_literal: true

# Card data with faces (CardDefinition::Faces): CR 712, 716, 721, 723. Invented card names only.
RSpec.describe "Card faces" do
  let(:front) { { "name" => "Ember Pup", "mana_cost" => "{R}", "types" => ["creature"], "power" => 1, "toughness" => 1 } }
  let(:back) { { "name" => "Ember Hound", "colors" => ["R"], "types" => ["creature"], "power" => 3, "toughness" => 3 } }
  let(:spell) do
    { "name" => "Ember Snap", "mana_cost" => "{R}", "types" => ["instant"], "subtypes" => ["adventure"],
      "abilities" => [{ "spell" => { "effects" => [{ "create_token" => { "token" => {
        "name" => "Spark", "colors" => ["R"], "types" => ["creature"], "power" => 1, "toughness" => 1
      } } }] } }] }
  end

  def build(data) = Enjine::CardDefinition.from_h(data)

  def errors_for(data)
    build(data)
    raise "expected InvalidCardDefinition"
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  it "has the front face's characteristics and an id per face (CR 712.6a)" do
    defn = build("layout" => "transform", "faces" => [front, back])
    expect([defn.id, defn.name, defn.full_name]).to eq(["ember_pup", "Ember Pup", "Ember Pup // Ember Hound"])
    expect(defn.faces.map(&:id)).to eq(%w[ember_pup ember_pup/1])
    expect(defn.face(1)).to have_attributes(name: "Ember Hound", face_index: 1, layout: "transform", card: defn)
    expect(defn.face(1).other_face).to be(defn)
    expect(defn.other_face).to be(defn.face(1))
    expect(defn).to be_double_faced
    expect(defn.to_h["name"]).to eq("Ember Pup // Ember Hound")
    expect(build(defn.to_h)).to eq(defn)
  end

  it "leaves single-faced cards unchanged" do
    defn = build(front)
    expect([defn.layout, defn.faces, defn.other_faces, defn.face_index, defn.card]).to eq([nil, [defn], [], 0, defn])
    expect(defn).not_to be_double_faced
  end

  it "finds faces in a catalog by face id and the card by its full name; registers every face's tokens" do
    catalog = Enjine::Catalog.from_definitions([{ "layout" => "adventure", "faces" => [front, spell] }])
    expect(catalog.fetch("ember_pup/1").name).to eq("Ember Snap")
    expect(catalog["ember_pup/1"].name).to eq("Ember Snap")
    expect(catalog).to include("ember_pup/1")
    expect(catalog.fetch("Ember Pup // Ember Snap").id).to eq("ember_pup")
    expect(catalog.map(&:name)).to include(a_string_starting_with("Spark"))
    expect(catalog.map(&:id)).not_to include("ember_pup/1")
  end

  it "reports problems of the whole card and of each face with their paths" do
    errors = errors_for("name" => "Wrong", "layout" => "flip", "mana_cost" => "{R}",
                        "faces" => [front.merge("power" => "x"), back.merge("types" => ["wizardry"])])
    expect(errors).to include(
      a_string_matching(/\Amana_cost: a card with faces keeps its characteristics in each face/),
      a_string_matching(/\Alayout: required with faces, one of transform, modal, adventure, omen, prepare/),
      a_string_matching(/\Afaces\[0\]\.power: must be an integer/),
      a_string_matching(/\Afaces\[1\]\.types\[0\]: unknown type "wizardry"/),
      a_string_matching(%r{\Aname: must be "Ember Pup // Ember Hound"})
    )
  end

  it "needs exactly two faces" do
    expect(errors_for("layout" => "modal", "faces" => [front])).to include(
      "faces: must be a list of two faces, each a card object", a_string_matching(/\Afaces\[1\]\.name: required/)
    )
    expect(errors_for("layout" => "modal", "faces" => "two")).to include(a_string_matching(/\Afaces: must be a list/))
  end

  it "checks the spell face of adventurer, omen and preparation cards (CR 716.2, 721.2, 723.2, 205.3k)" do
    expect(errors_for("layout" => "adventure", "faces" => [front, back])).to include(
      a_string_matching(/\Afaces\[1\]\.types: the adventure face is an instant or sorcery/),
      a_string_matching(/\Afaces\[1\]\.subtypes: an adventure face has the spell type adventure/)
    )
    omen = spell.merge("subtypes" => ["omen"])
    expect(build("layout" => "omen", "faces" => [front, omen]).face(1).subtypes).to eq([:omen])
    expect(errors_for("layout" => "prepare", "faces" => [spell.merge("subtypes" => []), spell.merge("subtypes" => [])]))
      .to include(a_string_matching(/\Afaces\[0\]\.types: the main face of a prepare card is a permanent card/))
  end

  it "only lets a card with a prepare spell enter prepared (CR 723.3a)" do
    expect(errors_for(front.merge("abilities" => ["enters_prepared"])))
      .to include(a_string_matching(/\Aabilities\[0\]: only a card with a prepare spell/))
    prepare = build("layout" => "prepare", "faces" => [front.merge("abilities" => ["enters_prepared"]),
                                                       spell.merge("subtypes" => [])])
    expect(prepare.ability("printed:0").to_s).to eq("enters prepared")
  end

  it "describes the face primitives" do
    errors = []
    effects = [{ "transform" => {} }, { "prepare" => { "to" => "self" } }, { "unprepare" => {} },
               { "return_to_battlefield" => { "to" => "self", "transformed" => true } }]
    built = effects.map { Enjine::Mechanics.build_entry(:effect, it, errors, "e") }
    trigger = Enjine::Mechanics.build_entry(:trigger, { "transforms" => {} }, errors, "t")
    expect(errors).to be_empty
    expect(built.map(&:to_s)).to eq(["transform → itself", "prepare → itself", "unprepare → itself",
                                     "return to the battlefield transformed → itself"])
    expect(trigger.to_s).to eq("whenever this transforms")
  end

  it "rejects prepared and transformed filters in static abilities (they aren't characteristics)" do
    errors = []
    filter = Enjine::Mechanics.build_entry(:filter, { "creature" => { "prepared" => true, "transformed" => false } }, errors, "f")
    expect(errors).to be_empty
    expect(filter.live_keys).to include("prepared", "transformed")
  end
end
