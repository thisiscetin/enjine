# frozen_string_literal: true

RSpec.describe Enjine::DeckBuilder do
  let(:fxa) { builder("fxa") }

  def card(name) = fxa.cards.find { it.name == name }
  def defn(data) = Enjine::CardDefinition.from_h(data)
  def colors(doc) = described_class.parse_colors(doc["description"][/colors=(\w+)/, 1])

  describe "colors" do
    it "derives a card's colors from its mana cost symbols (CR 105.2, 202.2)" do
      expect(described_class.colors_of(card("Skyshore Paladin"))).to eq(%i[W U])
      expect(described_class.colors_of(card("Clockwork Sentry"))).to eq([])
      expect(described_class.colors_of(card("Forest"))).to eq([])
      expect(described_class.colors_of(defn(pool_card("Odd", "{C}{2}")))).to eq([])
    end

    it "also requires the colors of activation costs, and fits colorless cards anywhere" do
      splash = pool_card("Splashy", "{1}{G}").merge(
        "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{R}" }], "effects" => [{ "draw" => { "amount" => 1 } }] } }]
      )
      expect(described_class.required_colors(defn(splash))).to eq(%i[R G])
      expect(described_class.fits?(defn(splash), %i[G])).to be(false)
      expect(described_class.fits?(defn(splash), %i[R G])).to be(true)
      expect(described_class.fits?(card("Clockwork Sentry"), %i[B])).to be(true)
      expect(described_class.fits?(card("Skyshore Paladin"), %i[W])).to be(false)
    end

    it "reads the colors a land produces, intrinsic basic land types included" do
      expect(described_class.produced_colors(card("Ember Thicket"))).to eq(%i[R G])
      expect(described_class.produced_colors(card("Seagate Bastion"))).to eq(%i[W U])
      expect(described_class.produced_colors(card("Barren Monolith"))).to eq([])
    end

    it "normalizes color lists" do
      expect(described_class.parse_colors("uw")).to eq(%i[W U])
      expect(described_class.parse_colors(%w[G B])).to eq(%i[B G])
      expect(described_class.parse_colors("W,U")).to eq(%i[W U])
      expect { described_class.parse_colors("WX") }.to raise_error(ArgumentError, /unknown color X/)
      expect { described_class.parse_colors("") }.to raise_error(ArgumentError, /at least one color/)
    end

    it "picks random colors among the combinations the pool can fill" do
      wu_only = big_pool.select { it["mana_cost"].match?(/[WU]/) }
      wu = described_class.new(wu_only)
      picks = (1..20).map { colors(wu.build(colors: 1, seed: it)) }
      expect(picks.uniq.sort).to eq([%i[U], %i[W]])
      expect(colors(wu.build(colors: "2", seed: 1))).to eq(%i[W U])
      big = described_class.new(big_pool)
      counts = (1..60).map { colors(big.build(colors: :any, seed: it)).size }
      expect(counts.uniq.sort).to eq([1, 2, 3])
      expect(counts.count(2)).to be > counts.count(3)
      expect { big.build(colors: 6, seed: 1) }.to raise_error(ArgumentError, /1 to 5 colors/)
    end

    it "falls back to the closest combination when none can be filled, so the error explains what's missing" do
      white = described_class.new(big_pool.select { it["mana_cost"].include?("W") })
      expect { white.build(colors: 3, seed: 1) }.to raise_error(described_class::NotEnoughCards, /none of them is a playable/) do
        expect(it.details[:colors]).to include("W")
        expect(it.details[:colors_without_cards].size).to eq(2)
      end
    end
  end

  describe "profile" do
    let(:decks) { (1..150).map { deck_stats(described_class.new(big_pool).build(colors: %w[W U], seed: it)) } }

    it "draws land and creature counts from the ranges, with occasional outliers" do
      lands = decks.map { it[:lands] }
      creatures = decks.map { it[:creatures] }
      expect(lands).to all(be_between(20, 27))
      expect(creatures).to all(be_between(10, 28))
      expect(lands.count { (22..26).cover?(it) }).to be >= 120
      expect(lands.count { !(22..26).cover?(it) }).to be_positive
      expect(lands.sum.fdiv(lands.size)).to be_within(1).of(24)
      expect(creatures.count { (14..24).cover?(it) }).to be >= 120
      expect(decks).to all(satisfy { it[:lands] + it[:creatures] + it[:others] == 60 })
    end

    it "weights the curve toward 1-3 mana value and mostly plays 4-ofs" do
      spells = decks.flat_map { it[:counts] }.reject { |d, _| d.land? }
      by_mv = spells.group_by { |d, _| d.mana_cost.mana_value.clamp(1, 6) }.transform_values { |pairs| pairs.sum { |_, n| n } }
      expect(by_mv.values_at(1, 2, 3).sum).to be > 3 * by_mv.values_at(5, 6).sum
      expect(by_mv[2]).to be > by_mv[5]
      copies = spells.map { it[1] }.tally
      expect(copies[4]).to be > copies[2]
      expect(copies[4]).to be > copies[1]
      expect(copies.keys).to all(be_between(1, 4))
    end

    it "accepts overrides and scales counts with the deck size" do
      fixed = { lands: { range: 30..30, center: 30 }, creatures: { range: 20..20 }, outlier_chance: 0 }
      stats = deck_stats(described_class.new(big_pool).build(colors: "R", seed: 3, profile: fixed))
      expect(stats.values_at(:lands, :creatures, :others)).to eq([30, 20, 10])
      big = deck_stats(described_class.new(big_pool).build(colors: "R", seed: 3, size: 90, profile: fixed))
      expect(big.values_at(:lands, :creatures, :others)).to eq([45, 30, 15])
      flat = described_class.new(big_pool).build(colors: "G", seed: 3, profile: { "curve" => { 1 => 0, 2 => 0 } })
      expect(Enjine::Player.new(name: "p", deck: flat)).to be_ready
      zero = { curve: (1..6).to_h { [it, 0] } }
      expect(Enjine::Player.new(name: "p", deck: described_class.new(big_pool).build(colors: "G", seed: 3, profile: zero)))
        .to be_ready
    end

    it "rejects bad arguments" do
      expect { described_class.new(big_pool).build(seed: 1, profile: { mana: 1 }) }
        .to raise_error(ArgumentError, /unknown profile keys: mana/)
      expect { described_class.new(big_pool).build(seed: 1, size: 40) }.to raise_error(ArgumentError, /at least 60/)
      expect { described_class.new(big_pool).build(seed: 1, profile: { copies: { 4 => 0, 3 => 0, 2 => 0, 1 => 0 } }) }
        .to raise_error(ArgumentError, /positive weight/)
      expect { described_class.new([{ "card" => pool_card("Odd", "{W}"), "count" => 0 }]) }
        .to raise_error(ArgumentError, /positive Integer, got 0/)
      expect { described_class.new([pool_card("Odd", "{W}"), pool_card("Odd", "{U}")]) }
        .to raise_error(Enjine::CatalogConflict, /Odd/)
    end
  end

  describe "determinism" do
    it "builds the same deck from the same inputs and seed, regardless of input order" do
      both = builder("fxa", "fxb")
      one = both.build(colors: %w[W U], seed: 7)
      expect(builder("fxb", "fxa").build(colors: "UW", seed: 7)).to eq(one)
      expect(described_class.new(fxa.cards + CardFixtures.pool("fxb")).build(colors: %w[W U], seed: 7)).to eq(one)
      expect(both.build(colors: %w[W U], seed: 7)).to eq(one) # a builder keeps no state between decks
      expect(described_class.new(big_pool.reverse).build(colors: 2, seed: 9))
        .to eq(described_class.new(big_pool).build(colors: 2, seed: 9))
      expect(one["description"]).to start_with("random deck: colors=WU seed=7 — ")
    end

    it "builds different decks from different seeds" do
      both = builder("fxa", "fxb")
      decks = (1..6).map { both.build(colors: %w[W U], seed: it)["main"] }
      expect(decks.uniq.size).to be >= 5
    end
  end

  describe "deck construction" do
    it "respects the four-copy rule; only basic lands exceed it" do
      40.times do |seed|
        doc = fxa.build(colors: 1, seed: seed)
        deck_stats(doc)[:counts].each do |d, n|
          expect(n).to be <= 4 unless d.supertype?(:basic)
        end
        expect(Enjine::Deck.from_h(doc)).to be_valid
      end
    end

    it "splits basics by colored mana symbols, with at least one of each color that has symbols" do
      pool = (1..12).map { pool_card("White #{it}", "{W}{W}") } + [pool_card("Lone Blue", "{U}")]
      counts = deck_stats(described_class.new(pool).build(colors: "WU", seed: 2))[:counts].to_h { |d, n| [d.name, n] }
      expect(counts["Island"]).to be_between(1, 3)
      expect(counts["Plains"]).to be > 20
      hybrid = (1..12).map { pool_card("Ogre #{it}", "{2}{B/R}") } # hybrid symbols aren't colored pips: an even split
      split = deck_stats(described_class.new(hybrid).build(colors: "BR", seed: 2))[:counts]
      low, high = split.select { |d, _| d.land? }.map { it[1] }.minmax
      expect(high - low).to be <= 1
    end

    it "uses the pool's own basic lands when it has them, built-in ones otherwise" do
      only_b = build_deck(%w[fxb], colors: "W", seed: 1)
      expect(only_b["cards"]).to include(described_class::BASIC_LANDS[:W])
      expect(fxa.build(colors: "W", seed: 1)["cards"]).to include(card("Plains").to_h)
    end

    it "only adds nonbasic lands whose mana is within the deck's colors" do
      seen = []
      both = builder("fxa", "fxb")
      30.times do |seed|
        doc = both.build(colors: %w[W U], seed: seed)
        deck_stats(doc)[:counts].map(&:first).each do |d|
          next unless d.land? && !d.supertype?(:basic)

          seen << d.name
          expect(described_class.produced_colors(d) - %i[W U]).to be_empty
        end
      end
      expect(seen.uniq).to include("Seagate Bastion")
      expect(seen).not_to include("Murkwater Cove", "Cindermarsh", "Ember Thicket")
    end

    it "includes the cards it's asked to, four copies each, and checks they fit the colors" do
      pool = described_class.new(CardFixtures.pool("fxa") + CardFixtures.cards.select { it["name"] == "Wastes" })
      doc = pool.build(colors: "G", seed: 5, including: ["Elderbark Ancient", "verdant_blessing", "Forest", "Wastes"])
      counts = deck_stats(doc)[:counts].to_h { |d, n| [d.name, n] }
      expect(counts).to include("Elderbark Ancient" => 4, "Verdant Blessing" => 4, "Wastes" => 4)
      expect(counts["Forest"]).to be > 4 # a basic of the deck's colors comes anyway
      expect(Enjine::Deck.from_h(doc)).to be_valid
      expect { pool.build(colors: "G", seed: 5, including: ["Searing Jolt"]) }
        .to raise_error(ArgumentError, /Searing Jolt does not fit a G deck/)
      expect { pool.build(colors: "G", seed: 5, including: ["Nope"]) }.to raise_error(ArgumentError, /"Nope" is not in the pool/)
      expect { pool.build(colors: "R", seed: 5, including: ["Ember Thicket"]) }.to raise_error(ArgumentError, /Ember Thicket does not fit/)
    end

    it "builds a deck around included cards in colors the pool has no other card of, padding with basics" do
      pool = described_class.new([pool_card("Lone Bear", "{1}{G}")])
      doc = pool.build(colors: "GU", seed: 1, including: ["Lone Bear"], profile: { outlier_chance: 0, lands: { outliers: 20..60 } })
      counts = deck_stats(doc)[:counts].to_h { |d, n| [d.name, n] }
      expect(counts).to include("Lone Bear" => 4, "Forest" => 56)
    end
  end

  describe "scarcity" do
    it "fills with more copies, then moves slots between creatures and other spells" do
      creatures_only = (1..9).map { pool_card("Soldier #{it}", "{#{it % 3}}{W}") }
      stats = deck_stats(described_class.new(creatures_only).build(colors: "W", seed: 4))
      expect(stats[:others]).to eq(0)
      expect(stats[:creatures]).to eq(60 - stats[:lands])
      expect(stats[:counts].count { |d, _| !d.land? }).to eq(9)
      spells_only = (1..9).map { pool_card("Charm #{it}", "{#{it % 3}}{W}", type: "sorcery") } +
                    [pool_card("Lone Soldier", "{W}")]
      stats = deck_stats(described_class.new(spells_only).build(colors: "W", seed: 4))
      expect(stats[:creatures]).to eq(4)
      expect(stats[:lands] + stats[:others] + 4).to eq(60)
    end

    it "plays more lands, up to the outlier maximum, before giving up" do
      pool = (1..8).map { pool_card("Knight #{it}", "{1}{W}") } # 32 cards: 28 lands needed, 27 allowed
      expect { described_class.new(pool).build(colors: "W", seed: 1) }
        .to raise_error(described_class::NotEnoughCards, /8 creature and 0 other.*at most 32 copies.*1 short.*27 lands/) do |e|
          expect(e.details).to include(colors: "W", size: 60, lands: 27, missing: 1, creatures_available: 8, max_spell_copies: 32)
        end
      stats = deck_stats(described_class.new(pool + [pool_card("Squire", "{W}")]).build(colors: "W", seed: 1))
      expect(stats[:lands]).to be_between(24, 27)
      expect(stats[:creatures]).to eq(60 - stats[:lands])
    end

    it "explains what's missing for a pool and colors that can't make a deck" do
      expect { fxa.build(colors: %w[W], seed: 1, profile: { lands: { range: 15..15, center: 15, outliers: 15..15 } }) }
        .to raise_error(described_class::NotEnoughCards, /60-card W deck from 48 cards/)
    end
  end
end
