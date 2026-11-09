# frozen_string_literal: true

RSpec.describe "Random decks from a multi-set collection" do
  let(:dir) { DeckBuilderHelpers::SET_FIXTURES }
  let(:collection) { Enjine::Collection.load(DeckBuilderHelpers::BINDER, sets_dir: dir) }

  it "resolves the binder's cards from both sets and reports the rest" do
    report = collection.report
    expect(report["resolved"].map { it["set"] }.uniq).to contain_exactly("fxa", "fxb")
    expect(report["unknown"].map { it["name"] }).to include("Prismatic Tidecaller", "Skyveil Seraph")
    expect(report["unknown"].size).to eq(6)
    expect(collection.count("Lantern Warden")).to eq(5)
    expect(collection.count("Mountain")).to eq(16)
  end

  ["WU", "R", "WR", "UR", 1, 2, :any].each do |colors|
    it "builds valid #{colors} decks that only use owned cards, at most the copies owned" do
      6.times do |seed|
        doc = build_deck(collection: collection, colors: colors, seed: seed)
        player = Enjine::Player.new(name: "p", deck: doc)
        expect(player).to be_ready, player.deck.errors.join("; ")
        expect(player.deck.size).to eq(60)

        deck_colors = Enjine::DeckBuilder.parse_colors(doc["description"][/colors=(\w+)/, 1])
        defs = doc["cards"].map { Enjine::CardDefinition.from_h(it) }
        expect(defs).to all(satisfy { Enjine::DeckBuilder.fits?(it, deck_colors) })
        used = defs.reject(&:land?).flat_map { Enjine::DeckBuilder.colors_of(it) }.uniq
        expect(used).to match_array(deck_colors)
        doc["main"].each do |entry|
          next if %w[Plains Island Swamp Mountain Forest].include?(entry["card"])

          expect(entry["count"]).to be <= [collection.count(entry["card"]), 4].min, entry["card"]
        end
        expect(doc["description"]).to start_with("random deck: collection=binder.json colors=")
      end
    end
  end

  it "uses only the owned basics with basics: :owned" do
    6.times do |seed|
      doc = build_deck(collection: collection, colors: "WU", seed: seed, basics: :owned)
      expect(Enjine::Player.new(name: "p", deck: doc)).to be_ready
      main = doc["main"].to_h { [it["card"], it["count"]] }
      expect(main.fetch("Plains", 0)).to be <= 16
      expect(main.fetch("Island", 0)).to be <= 14
    end
  end

  it "explains which colors the collection can't fill" do
    expect { build_deck(collection: collection, colors: "B", seed: 1) }
      .to raise_error(Enjine::DeckBuilder::NotEnoughCards, /60-card B deck from the collection binder.json/) do
        expect(it.details).to include(collection: "binder.json", colors: "B", creatures_available: 4)
      end
  end
end
