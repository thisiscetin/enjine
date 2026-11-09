# frozen_string_literal: true

require "tmpdir"

RSpec.describe Enjine::Collection do
  let(:dir) { DeckBuilderHelpers::SET_FIXTURES }

  def load(cards, **) = described_class.load({ "format" => 1, "cards" => cards }, sets_dir: dir, **)

  describe "resolving entries" do
    it "finds cards by name, case- and punctuation-insensitively" do
      collection = load([{ "name" => "Dawnward Squire", "count" => 2 }, { "name" => "ilsa wall keeper" },
                         { "name" => "  MISTGLASS  seer " }])
      expect(collection.entries.map { [it.name, it.count] })
        .to eq([["Dawnward Squire", 2], ["Ilsa, Wall Keeper", 1], ["Mistglass Seer", 1]])
      expect(collection.count("dawnward_squire")).to eq(2)
      expect(collection.count("Ilsa, Wall Keeper")).to eq(1)
      expect(collection.count("Halo Bearer")).to eq(0)
      expect(collection).to include("mistglass seer")
    end

    it "finds printings by set code and collector number (Integer numbers too)" do
      collection = load([{ "set" => "FXA", "number" => "12" }, { set: "fxb", number: 8, count: 3 }])
      expect(collection.entries.map { [it.name, it.count] }).to eq([["Brinespout Sprite", 3], ["Stormcrown Leviathan", 1]])
      expect(collection.report["resolved"]).to include({ "id" => "brinespout_sprite", "name" => "Brinespout Sprite",
                                                         "set" => "fxb", "count" => 3 })
    end

    it "limits a name to a set given by code or by set name" do
      collection = load([{ "name" => "Halo Bearer", "set_name" => "tidewild expanse", "count" => 2 },
                         { "name" => "Gatehold Recruit", "set" => "fxb" },
                         { "name" => "Halo Bearer", "set" => "fxb", "set_name" => "Tidewild Expanse" }])
      expect(collection.count("Halo Bearer")).to eq(3)
      expect(collection.report["resolved"].map { it["set"] }.uniq).to eq(["fxb"])
    end

    it "adds up repeated entries for the same card, however they name it" do
      collection = load([{ "set" => "fxa", "number" => "2", "count" => 2 }, { "name" => "lantern warden", "count" => 2 },
                         { "name" => "LANTERN WARDEN" }])
      expect(collection.entries.map { [it.id, it.count] }).to eq([["lantern_warden", 5]])
      expect(collection.size).to eq(5)
      expect(collection.definitions.map(&:name)).to eq(["Lantern Warden"])
    end

    it "takes a card's definition from the first set by code, then from extra cards:, whatever the entry order" do
      extra = [{ "name" => "Dawnward Squire", "mana_cost" => "{1}{W}", "types" => ["creature"], "power" => 3, "toughness" => 3 },
               { "name" => "Homebrew Golem", "mana_cost" => "{2}", "types" => %w[artifact creature], "power" => 2,
                 "toughness" => 2 }]
      collection = load([{ "name" => "Homebrew Golem" }, { "name" => "Dawnward Squire" }], cards: extra)
      expect(collection.definitions.map { [it.name, it.mana_cost.to_s] })
        .to eq([["Dawnward Squire", "{W}"], ["Homebrew Golem", "{2}"]])
      expect(collection.report["resolved"].find { it["name"] == "Homebrew Golem" }).not_to have_key("set")
      core = load([{ "name" => "Grizzly Bears" }], cards: Enjine::CardPool::Core.cards.map { Enjine::CardDefinition.from_h(it) })
      expect(core.count("Grizzly Bears")).to eq(1)
    end

    it "keeps the first set's definition when entries for one card come from several sets, in any order" do
      Dir.mktmpdir do |tmp|
        FileUtils.cp(File.join(dir, "fxa.json"), tmp)
        reprint = JSON.parse(File.read(File.join(dir, "fxa.json"))).merge("code" => "fxz", "name" => "Reprints")
        reprint["cards"] = reprint["cards"].first(1).map { it.merge("mana_cost" => "{1}{W}") }
        File.write(File.join(tmp, "fxz.json"), JSON.generate(reprint))
        entries = [{ "name" => "Dawnward Squire", "set" => "fxz", "count" => 2 }, { "name" => "Dawnward Squire" }]
        [entries, entries.reverse].each do |list|
          collection = described_class.load(list, sets_dir: tmp)
          expect(collection.entries.map { [it.definition.mana_cost.to_s, it.count] }).to eq([["{W}", 3]])
          expect(collection.report["resolved"].first["set"]).to eq("fxa")
        end
      end
    end

    it "reports unknown cards instead of dropping them" do
      collection = load([{ "name" => "Skyveil Seraph", "count" => 2 },
                         { "name" => "Unheard-of Wanderer", "count" => 3 }, { "name" => "Dawnward Squire", "set" => "zzz" },
                         { "name" => "Dawnward Squire", "set_name" => "Nowhere" },
                         { "name" => "Halo Bearer", "set" => "fxa", "set_name" => "Tidewild Expanse" },
                         { "name" => "Halo Bearer", "set" => "fxa" },
                         { "set" => "fxa", "number" => "1", "name" => "Halo Bearer" }, { "set" => "fxb", "number" => "999" }])
      expect(collection.entries).to be_empty
      expect(collection.report.keys).to eq(%w[resolved unknown])
      expect(collection.report["unknown"].map { it["reason"] }).to contain_exactly(
        "no card named \"Skyveil Seraph\"", "no card named \"Unheard-of Wanderer\"", "unknown set \"zzz\"",
        "unknown set name \"Nowhere\"", "set \"fxa\" and set_name \"Tidewild Expanse\" disagree",
        "no card named \"Halo Bearer\" in fxa", "fxa:1 is \"Dawnward Squire\", not \"Halo Bearer\"", "no printing fxb:999"
      )
      expect(collection.report["unknown"].find { it["name"] == "Unheard-of Wanderer" }).to include("count" => 3)
    end
  end

  describe "loading" do
    let(:path) { File.expand_path("../fixtures/collections/binder.json", __dir__) }

    it "reads a JSON file, remembers its path, and round-trips through to_h" do
      collection = described_class.load(path, sets_dir: dir)
      expect(collection.source).to eq(path)
      expect(described_class.load(collection)).to be(collection)
      again = described_class.load(collection.to_h, sets_dir: dir)
      expect(again.entries).to eq(collection.entries)
      expect(again.report).to eq(collection.report)
      expect(collection.to_h["cards"]).to all(include("count"))
    end

    it "accepts a bare array of entries and symbol keys" do
      collection = described_class.load([{ name: "Dawnward Squire", count: 4 }], sets_dir: dir)
      expect(collection.count("Dawnward Squire")).to eq(4)
      expect(collection.to_h).to eq("format" => 1, "cards" => [{ "name" => "Dawnward Squire", "count" => 4 }])
    end

    it "rejects malformed documents" do
      expect { described_class.load("nope.json") }.to raise_error(described_class::InvalidCollection, /not found: nope.json/)
      Dir.mktmpdir do |tmp|
        bad = File.join(tmp, "bad.json")
        File.write(bad, "{")
        expect { described_class.load(bad) }.to raise_error(described_class::InvalidCollection, /not valid JSON/)
      end
      expect { described_class.load(42) }.to raise_error(described_class::InvalidCollection, /JSON object/)
      expect { described_class.load({ "format" => 2, "cards" => [] }) }.to raise_error(described_class::InvalidCollection, /format 2/)
      expect { described_class.load({ "format" => 1 }) }.to raise_error(described_class::InvalidCollection, /"cards" array/)
      expect { load(["Dawnward Squire"]) }.to raise_error(described_class::InvalidCollection, /cards\[0\]: expected an object/)
      expect { load([{ "name" => "Dawnward Squire", "count" => 0 }]) }.to raise_error(described_class::InvalidCollection, /positive/)
      expect { load([{ "name" => "Dawnward Squire", "count" => "2" }]) }.to raise_error(described_class::InvalidCollection, /positive/)
      expect { load([{ "set" => "fxa" }]) }.to raise_error(described_class::InvalidCollection, /by "name", or by "set" and "number"/)
      expect { load([{ "number" => "1" }]) }.to raise_error(described_class::InvalidCollection, /by "name"/)
    end
  end
end
