# frozen_string_literal: true

RSpec.describe Enjine::DeckBuilder, ".build with collection:" do
  let(:dir) { DeckBuilderHelpers::SET_FIXTURES }

  def counts(doc) = doc["main"].to_h { [it["card"], it["count"]] }

  # Every big_pool card owned `copies` times, resolved through extra cards: (no set files involved).
  def owned_pool(copies, pool = big_pool)
    Enjine::Collection.load(pool.map { { "name" => it["name"], "count" => copies } },
                            sets_dir: dir, cards: pool)
  end

  it "never uses more copies than owned, nor more than 4" do
    pool = big_pool + [pool_card("W Hoard", "{W}")]
    entries = big_pool.map { { "name" => it["name"], "count" => 2 } } + [{ "name" => "w hoard", "count" => 9 }]
    collection = Enjine::Collection.load(entries, sets_dir: dir, cards: pool)
    hoarded = 0
    8.times do |seed|
      doc = described_class.build(collection: collection, colors: "WU", seed: seed, sets_dir: dir)
      expect(Enjine::Player.new(name: "p", deck: doc)).to be_ready
      counts(doc).each do |name, n|
        next if %w[Plains Island].include?(name)

        expect(n).to be <= [collection.count(name), 4].min
      end
      hoarded = [hoarded, counts(doc).fetch("W Hoard", 0)].max
    end
    expect(hoarded).to eq(4)
  end

  it "tops up copies only to what is owned, then plays more lands or raises" do
    singles = owned_pool(1, big_pool.select { it["mana_cost"].include?("R") })
    error = nil
    begin
      described_class.build(collection: singles, colors: "R", seed: 1, sets_dir: dir)
    rescue described_class::NotEnoughCards => e
      error = e
    end
    expect(error.message).to include("from the collection (18 cards)", "Add cards to the collection")
    expect(error.details).to include(collection: "(18 cards)", colors: "R", max_spell_copies: 18, colors_without_cards: "")
  end

  it "raises when a deck color has no owned cards, naming the colors" do
    collection = owned_pool(4, big_pool.reject { it["mana_cost"].include?("G") })
    expect { described_class.build(collection: collection, colors: "WG", seed: 1, sets_dir: dir) }
      .to raise_error(described_class::NotEnoughCards, /no playable G cards/) { expect(it.details[:colors_without_cards]).to eq("G") }
    picks = (1..10).map { described_class.new(collection: collection, colors: 2, seed: it, sets_dir: dir).colors }
    expect(picks.flatten).not_to include(:G)
  end

  it "gives the same deck for the same collection and seed, whatever the entry order" do
    path = File.expand_path("../fixtures/collections/binder.json", __dir__)
    collection = Enjine::Collection.load(path, sets_dir: dir)
    shuffled = collection.to_h.merge("cards" => collection.to_h["cards"].shuffle(random: Random.new(4)))
    [1, 2, 5].each do |seed|
      expect(described_class.build(collection: shuffled, seed: seed, sets_dir: dir)["main"])
        .to eq(described_class.build(collection: path, seed: seed, sets_dir: dir)["main"])
    end
  end

  describe "basics:" do
    let(:path) { File.expand_path("../fixtures/collections/binder.json", __dir__) }

    it "adds unlimited basic lands by default, from the collection's sets or built in" do
      one_plains = Enjine::Collection.load(big_pool.map { { "name" => it["name"], "count" => 4 } } + [{ "name" => "Plains" }],
                                           sets_dir: dir, cards: big_pool)
      expect(one_plains.count("Plains")).to eq(1)
      expect(counts(described_class.build(collection: one_plains, colors: "W", seed: 1, sets_dir: dir))["Plains"]).to be >= 16
      expect(counts(described_class.build(collection: owned_pool(4), colors: "G", seed: 1, sets_dir: dir))["Forest"]).to be >= 16
    end

    it "uses only owned basics with :owned, moving the shortfall to colors with spares" do
      entries = big_pool.map { { "name" => it["name"], "count" => 4 } } + [{ "name" => "Plains", "count" => 2 },
                                                                           { "name" => "Island", "count" => 40 }]
      collection = Enjine::Collection.load(entries, sets_dir: dir, cards: big_pool)
      doc = described_class.build(collection: collection, colors: "WU", seed: 3, sets_dir: dir, basics: "owned")
      stats = deck_stats(doc)
      expect(counts(doc)["Plains"]).to eq(2)
      expect(counts(doc)["Island"]).to eq(stats[:lands] - 2)
      expect(doc["description"]).to include("collection=(", "basics=owned colors=WU")
      expect(Enjine::Player.new(name: "p", deck: doc)).to be_ready
    end

    it "raises when the owned basics can't cover the lands" do
      expect { described_class.build(collection: path, colors: "R", seed: 1, sets_dir: dir, basics: :owned) }
        .to raise_error(described_class::NotEnoughCards, /needs \d+ basic lands but owns 16/) do
          expect(it.details).to include(basics_owned: { "R" => 16 }, collection: "binder.json")
        end
    end

    it "rejects bad values and :owned without a collection, and sets: with a collection" do
      expect { described_class.build(cards: big_pool, seed: 1, basics: :some) }.to raise_error(ArgumentError, /one of unlimited, owned/)
      expect { described_class.build(cards: big_pool, seed: 1, basics: :owned) }.to raise_error(ArgumentError, /needs a collection/)
      expect { described_class.build(collection: path, sets: %w[fxa], seed: 1, sets_dir: dir) }
        .to raise_error(ArgumentError, /either sets: or collection:/)
    end
  end
end
