# frozen_string_literal: true

RSpec.describe Enjine::CardDefinition do
  def defn(card) = described_class.from_h(card)

  describe "color identity from mana abilities (CR 903.4)" do
    def land(*abilities) = { "name" => "Spec Land", "types" => ["land"], "abilities" => abilities }

    it "doesn't count mana of the color chosen for the permanent, only its fixed color (a Thriving land)" do
      card = land({ "choose_option" => { "options" => %w[white blue black green] } },
                  { "mana" => { "cost" => ["tap"], "produce" => "{R}" } },
                  *%w[white blue black green].zip(%w[W U B G]).map do |word, sym|
                    { "mana" => { "cost" => ["tap"], "produce" => "{#{sym}}", "only_if" => { "chosen" => word } } }
                  end)
      expect(defn(card).color_identity).to eq([:R])
    end

    it "counts a fixed color gated on some other choice, and the costs of a chosen-color ability" do
      card = land({ "choose_option" => { "options" => %w[white fast] } },
                  { "mana" => { "cost" => ["tap"], "produce" => "{G}", "only_if" => { "chosen" => "white" } } },
                  { "mana" => { "cost" => [{ "mana" => "{U}" }, "tap"], "produce" => "{B}", "only_if" => { "chosen" => "fast" } } },
                  { "mana" => { "cost" => [{ "mana" => "{R}" }, "tap"], "produce" => "{W}", "only_if" => { "chosen" => "white" } } })
      expect(defn(card).color_identity).to eq(%i[U B R G])
    end

    it "counts the colors of a choice among some (\"Add {B} or {G}\"), not any color or the chosen color" do
      expect(defn(land({ "mana" => { "cost" => ["tap"], "color" => "any_one", "colors" => %w[B G] } })).color_identity)
        .to eq(%i[B G])
      expect(defn(land({ "mana" => { "cost" => ["tap"], "color" => "any_one" } })).color_identity).to eq([])
      expect(defn(land({ "choose_color" => {} }, { "mana" => { "cost" => ["tap"], "color" => "chosen" } })).color_identity).to eq([])
      spell = { "name" => "Spec Ritual", "mana_cost" => "{1}", "types" => ["instant"],
                "abilities" => [{ "spell" => { "effects" => [{ "add_mana" => { "amount" => 2, "color" => "any",
                                                                               "colors" => %w[R W] } }] } }] }
      expect(defn(spell).color_identity).to eq(%i[W R])
    end

    it "never counts color words of filters (CR 903.4: only mana symbols)" do
      spell = { "name" => "Spec Smite", "mana_cost" => "{1}", "types" => ["instant"],
                "abilities" => [{ "spell" => { "targets" => [{ "creature" => { "colors" => ["B"] } }],
                                               "effects" => [{ "destroy" => { "to" => { "target" => 0 } } }] } }] }
      expect(defn(spell).color_identity).to eq([])
    end
  end

  describe "repeated keyword instances (CR 702.85c, 702.2f)" do
    def creature(keywords)
      { "name" => "Spec Hydra", "mana_cost" => "{6}", "types" => ["creature"], "power" => 6,
        "toughness" => 6, "keywords" => keywords }
    end

    it "keeps one instance per listed cascade, storm, extort or increment, each triggering separately" do
      card = defn(creature(%w[cascade cascade cascade extort extort flying]))
      refs = card.ability_instances.map(&:ref)
      expect(refs.count("keyword:cascade")).to eq(3)
      expect(refs.count("keyword:extort")).to eq(2)
      expect(card.keywords).to eq(%i[cascade extort flying])
      expect(card.to_h["keywords"]).to eq(%w[cascade cascade cascade extort extort flying])
      expect(described_class.from_h(card.to_h).ability_instances.map(&:ref).count("keyword:cascade")).to eq(3)
    end

    it "keeps redundant keywords (flying) one instance" do
      card = defn(creature(%w[flying flying prowess prowess]))
      expect(card.keywords).to eq(%i[flying prowess])
      expect(card.ability_instances.map(&:ref).count("keyword:prowess")).to eq(1)
      expect(card.to_h["keywords"]).to eq(%w[flying prowess])
    end
  end
end
