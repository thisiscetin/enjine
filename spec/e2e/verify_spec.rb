# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "enjine/verify"

# Enjine::Verify and `enjine --verify`: a folder of card JSON in, a report of what's invalid, what was never used
# in play and what went wrong out.
RSpec.describe Enjine::Verify do
  # A mono-green folder from the fixtures: real cards as one array file, invented ones one card per file.
  def green_folder(dir)
    green = ->(card) { Enjine::DeckBuilder.fits?(Enjine::CardDefinition.from_h(card), %i[G]) }
    real = CardFixtures.real_cards.select(&green).reject { it["supertypes"]&.include?("basic") }.first(8)
    invented = CardFixtures.cards.select(&green).reject { it["supertypes"]&.include?("basic") }.first(5)
    FileUtils.mkdir_p(File.join(dir, "invented"))
    File.write(File.join(dir, "real.json"), JSON.generate(real))
    invented.each_with_index { |card, i| File.write(File.join(dir, "invented", "#{i}.json"), JSON.generate(card)) }
    real + invented
  end

  def write(dir, name, text) = File.write(File.join(dir, name), text).then { dir }

  it "validates, plays and reports a folder of real and invented cards, the same way for the same seed" do
    Dir.mktmpdir do |dir|
      cards = green_folder(dir)
      report = described_class.new(dir, games: 2, seed: 3).run
      expect(report).to include("ok" => true, "cards" => cards.size, "invalid" => [], "findings" => [], "errors" => [])
      expect(report["games"]).to be >= 2
      expect(report["types"]["creature"]).to include("total" => report["types"]["creature"]["valid"])
      exercised = report["types"].values.sum { it["exercised"] }
      expect(exercised).to be_positive
      expect(report["unexercised"].size).to be < cards.size
      expect(described_class.new(dir, games: 2, seed: 3).run).to eq(report)
    end
  end

  it "reports invalid cards by file, index and name with path-addressed errors, reprints once, conflicts as invalid" do
    Dir.mktmpdir do |dir|
      bears = { "name" => "Grizzly Bears", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 2, "toughness" => 2 }
      write(dir, "a.json", JSON.generate([{ "name" => "Bad", "types" => ["instantt"] }, 3, bears]))
      write(dir, "b.json", JSON.generate(bears.merge("rarity" => "common"))) # a reprint: the same card
      write(dir, "c.json", JSON.generate(bears.merge("power" => 3)))
      write(dir, "d.json", "{oops")
      report = described_class.new(dir, games: 1).run
      expect(report).to include("ok" => false, "cards" => 1)
      expect(report["invalid"]).to contain_exactly(
        { "file" => "a.json", "index" => 0, "name" => "Bad", "errors" => [a_string_starting_with("types[0]: unknown type \"instantt\"")] },
        { "file" => "a.json", "index" => 1, "name" => nil, "errors" => ["a card must be a JSON object"] },
        { "file" => "c.json", "index" => nil, "name" => "Grizzly Bears", "errors" => ["differs from Grizzly Bears in a.json"] },
        { "file" => "d.json", "index" => nil, "name" => nil, "errors" => [a_string_starting_with("not valid JSON")] }
      )
      expect(report["types"]["creature"]).to eq("total" => 2, "valid" => 1, "exercised" => report["types"]["creature"]["exercised"])
      expect(report["types"]).to include("instantt" => { "total" => 1, "valid" => 0, "exercised" => 0 })
      expect(described_class.new(write(Dir.mktmpdir, "x.json", "[3]"), games: 1).run).to include("cards" => 0, "games" => 0)
    end
  end

  it "sorts what goes wrong in play into findings, engine errors and unfinished games, and keeps going" do
    Dir.mktmpdir do |dir|
      green_folder(dir)
      kinds = %i[finding error stall].cycle
      allow(Enjine::Fuzz).to receive(:play) do |*, seed, _max, _rt, _inv, _monitor|
        raise Enjine::Fuzz::Failure.new("boom", seed: seed, decisions: 5, kind: kinds.next)
      end
      report = described_class.new(dir, games: 3, seed: 7).run
      expect(report["ok"]).to be(false)
      expect(report["findings"].first).to include("seed" => 7, "decisions" => 5, "message" => "boom (seed 7, after 5 decisions)",
                                                  "decks" => [a_string_starting_with("random deck"), a_string_starting_with("random deck")])
      expect(report["errors"].first).to include("seed" => 8)
      expect(report["unfinished"].first).to include("seed" => 9)
      expect(report["unexercised"].size).to eq(report["cards"]) # nothing played, every round
    end
  end

  it "reports a deck it can't build or a game it can't set up as an engine error" do
    Dir.mktmpdir do |dir|
      green_folder(dir)
      allow(Enjine::DeckBuilder).to receive(:new).and_wrap_original do |make, *args|
        make.call(*args).tap do |builder|
          allow(builder).to receive(:build).and_wrap_original do |build, **opts|
            opts[:including] ? raise(ArgumentError, "no deck") : build.call(**opts)
          end
        end
      end
      allow(Enjine::Setup).to receive(:new).and_raise(Enjine::Error, "no seat")
      report = described_class.new(dir, games: 1).run
      expect(report["errors"].map { it["message"] }).to include(/building a deck with .*: no deck/, "Enjine::Error: no seat")
    end
  end

  it "writes a readable report" do
    report = { "engine_version" => "1", "rules_version" => "r", "seed" => 2, "cards" => 1, "games" => 1, "decisions" => 9,
               "types" => { "land" => { "total" => 2, "valid" => 1, "exercised" => 1 } },
               "invalid" => [{ "file" => "a.json", "index" => 0, "name" => "Bad", "errors" => %w[x y] }],
               "unexercised" => [{ "name" => "Idle", "file" => "b.json" }],
               "findings" => [{ "seed" => 4, "message" => "CR 1", "decks" => %w[d1 d2] }],
               "errors" => [{ "seed" => 5, "message" => "boom" }], "unfinished" => [{ "seed" => 6 }], "ok" => false }
    text = described_class.text(report)
    expect(text).to include("land                2      1          1", "Invalid cards (1):\n  a.json[0] Bad: x; y",
                            "Never exercised (1):\n  Idle (b.json)", "seed 4: CR 1 — d1 vs d2", "Engine errors (1):\n  seed 5: boom",
                            "Unfinished games (decision cap) (1):\n  seed 6")
    expect(text).to end_with("FAILED")
    expect(described_class.text(report.merge("invalid" => [], "ok" => true))).not_to include("Invalid")
  end

  it "needs a directory" do
    expect { described_class.new("nope/") }.to raise_error(ArgumentError, "nope/: not a directory")
  end

  describe "enjine --verify" do
    def run(args)
      out = StringIO.new
      [Enjine::CLI.new(args, output: out).run, out.string]
    end

    it "prints a readable or a JSON report, exit code 0 when everything passed and 1 otherwise" do
      Dir.mktmpdir do |dir|
        write(dir, "bears.json", JSON.generate(CardFixtures.real_cards.find { it["name"] == "Llanowar Elves" } ||
                                               CardFixtures.cards.find { it["name"] == "Grizzly Bears" }))
        code, out = run(["--verify", dir, "--games", "1", "--seed", "4"])
        expect([code, out]).to match([0, /seed 4\n1 valid cards, \d+ games.*\nOK\n\z/m])
        code, out = run(["--verify", dir, "--games", "1", "--json"])
        expect(code).to eq(0)
        expect(JSON.parse(out)).to include("seed" => 0, "cards" => 1, "ok" => true)
        write(dir, "bad.json", "[]x")
        expect(run(["--verify", dir, "--games", "1"])).to match([1, /Invalid cards \(1\):.*FAILED\n\z/m])
      end
      expect(run(%w[--verify nope/])).to eq([1, "error: nope/: not a directory\n"])
    end
  end
end
