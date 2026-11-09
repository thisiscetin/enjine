# frozen_string_literal: true

RSpec.describe Enjine::DeckBuilder, ".new with owned counts" do
  def counts(doc) = doc["main"].to_h { [it["card"], it["count"]] }

  # Every card of `pool` owned `copies` times.
  def owned(copies, pool = big_pool) = described_class.new(pool.map { { "card" => it, "count" => copies } })

  it "adds up entries for the same card; a card listed without a count is uncapped" do
    hoard = pool_card("W Hoard", "{W}")
    builder = described_class.new([{ card: hoard, count: 2 }, { "card" => Enjine::CardDefinition.from_h(hoard), "count" => 3 },
                                   { "card" => big_pool[0], "count" => 1 }, big_pool[0], big_pool[1]])
    expect([builder.count("w hoard"), builder.count(big_pool[0]["name"]), builder.count(big_pool[1]["name"])]).to eq([5, nil, nil])
    expect(builder.count("Unknown")).to eq(0)
    expect(builder.cards.map(&:name)).to eq(builder.cards.map(&:name).sort_by { Enjine::CardDefinition.slug(it) })
  end

  it "never uses more copies than owned, nor more than 4" do
    builder = described_class.new(big_pool.map { { "card" => it, "count" => 2 } } +
                                  [{ "card" => pool_card("W Hoard", "{W}"), "count" => 9 }])
    hoarded = 0
    8.times do |seed|
      doc = builder.build(colors: "WU", seed: seed)
      expect(Enjine::Player.new(name: "p", deck: doc)).to be_ready
      counts(doc).each do |name, n|
        next if %w[Plains Island].include?(name)

        expect(n).to be <= [builder.count(name), 4].min
      end
      hoarded = [hoarded, counts(doc).fetch("W Hoard", 0)].max
    end
    expect(hoarded).to eq(4)
  end

  it "tops up copies only to what is owned, then plays more lands or raises" do
    singles = owned(1, big_pool.select { it["mana_cost"].include?("R") })
    expect { singles.build(colors: "R", seed: 1) }.to raise_error(described_class::NotEnoughCards, /from 18 cards/) do
      expect(it.details).to include(pool: 18, colors: "R", max_spell_copies: 18, colors_without_cards: "")
    end
  end

  it "raises when a deck color has no cards, and never picks such a color at random" do
    builder = owned(4, big_pool.reject { it["mana_cost"].include?("G") })
    expect { builder.build(colors: "WG", seed: 1) }
      .to raise_error(described_class::NotEnoughCards, /no.*playable G card/) { expect(it.details[:colors_without_cards]).to eq("G") }
    picks = (1..10).map { builder.build(colors: 2, seed: it)["description"][/colors=(\w+)/, 1] }
    expect(picks.join).not_to include("G")
  end

  it "always adds the basic lands a deck needs, owned or not" do
    one_plains = described_class.new(big_pool.map { { "card" => it, "count" => 4 } } +
                                     [{ "card" => CardFixtures.pool("fxa").find { it["name"] == "Plains" }, "count" => 1 }])
    expect(counts(one_plains.build(colors: "W", seed: 1))["Plains"]).to be >= 16
    expect(counts(owned(4).build(colors: "G", seed: 1))["Forest"]).to be >= 16
  end
end
