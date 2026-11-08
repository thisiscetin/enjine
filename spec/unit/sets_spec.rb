# frozen_string_literal: true

require "tmpdir"

RSpec.describe Enjine::Sets do
  let(:dir) { DeckBuilderHelpers::SET_FIXTURES }

  def write_set(dir, code, doc)
    File.write(File.join(dir, "#{code}.json"), doc.is_a?(String) ? doc : JSON.generate(doc))
  end

  it "lists set codes and loads a set's metadata and playable cards" do
    expect(described_class.codes(dir: dir)).to eq(%w[fxa fxb])
    set = described_class.load("FXA", dir: dir)
    expect(set).to have_attributes(code: "fxa", name: "Ashfall Reaches", released_at: Date.new(2025, 6, 13),
                                   standard_legal_until: Date.new(2027, 7, 30), standard_legal_until_estimated: false)
    expect(set.size).to eq(48)
    expect(set.cards).to all(be_a(Enjine::CardDefinition))
    expect(set.entries.first).to have_attributes(rarity: "common", collector_number: "1")
    expect(set.unsupported.map { it["name"] }).to eq(["Skyveil Seraph", "Echoing Grudge"])
    expect(described_class.load(set)).to be(set)
  end

  it "returns no codes for a missing directory and rejects unknown sets" do
    expect(described_class.codes(dir: "/nonexistent/sets")).to eq([])
    expect { described_class.load("zzz", dir: dir) }.to raise_error(described_class::InvalidSet, /unknown set "zzz".*fxa, fxb/)
  end

  it "selects the sets that are Standard-legal on a date" do
    legal = ->(date) { described_class.standard_legal(on: date, dir: dir).map(&:code) }
    expect(legal.call(Date.new(2024, 1, 1))).to eq([])
    expect(legal.call(Date.new(2026, 1, 1))).to eq(%w[fxa])
    expect(legal.call(Date.new(2026, 11, 8))).to eq(%w[fxa fxb])
    expect(legal.call(Date.new(2027, 7, 30))).to eq(%w[fxa fxb])
    expect(legal.call(Date.new(2027, 7, 31))).to eq(%w[fxb])
    expect(described_class.load("fxb", dir: dir).standard_legal_until_estimated).to be(true)
  end

  it "parses full and partial dates" do
    expect(described_class.parse_date("2029-01-19")).to eq(Date.new(2029, 1, 19))
    expect(described_class.parse_date("2029-03")).to eq(Date.new(2029, 3, 1))
    expect(described_class.parse_date("2029")).to eq(Date.new(2029, 1, 1))
    expect(described_class.parse_date(Date.new(2030, 2, 2))).to eq(Date.new(2030, 2, 2))
    expect(described_class.parse_date(nil)).to be_nil
    expect { described_class.parse_date("soon") }.to raise_error(described_class::InvalidSet, /invalid date/)
  end

  it "moves cards that no longer validate to unsupported and never loads them" do
    Dir.mktmpdir do |tmp|
      write_set(tmp, "tst", "format" => 1, "name" => "Test",
                            "cards" => [{ "card" => { "name" => "Bad Angel", "types" => ["creature"], "keywords" => ["flying"] } },
                                        "not an entry",
                                        { "card" => { "name" => "Forest", "types" => ["land"], "supertypes" => ["basic"],
                                                      "subtypes" => ["forest"] } }])
      set = described_class.load("tst", dir: tmp)
      expect(set.cards.map(&:name)).to eq(["Forest"])
      expect(set.unsupported.map { it["name"] }).to eq(["Bad Angel", nil])
      expect(set.unsupported.first["missing"]).to include(/unknown keyword "flying"/)
      expect(set).to have_attributes(code: "tst", released_at: nil, standard_legal_until: nil)
      expect(set.standard_legal?(Date.new(2000, 1, 1))).to be(true)
    end
  end

  it "rejects malformed set files" do
    Dir.mktmpdir do |tmp|
      write_set(tmp, "json", "{nope")
      write_set(tmp, "list", "[]")
      write_set(tmp, "old", "format" => 0)
      expect { described_class.load("json", dir: tmp) }.to raise_error(described_class::InvalidSet, /not valid JSON/)
      expect { described_class.load("list", dir: tmp) }.to raise_error(described_class::InvalidSet, /must be a JSON object/)
      expect { described_class.load("old", dir: tmp) }.to raise_error(described_class::InvalidSet, /unsupported format 0/)
    end
  end

  it "reads from Sets.dir, then $ENJINE_SETS_DIR, then the bundled directory" do
    expect(described_class.dir).to eq(ENV.fetch("ENJINE_SETS_DIR", described_class::DEFAULT_DIR))
    described_class.dir = dir
    expect(described_class.all.map(&:code)).to eq(%w[fxa fxb])
  ensure
    described_class.dir = nil
  end
end
