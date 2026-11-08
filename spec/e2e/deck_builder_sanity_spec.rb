# frozen_string_literal: true

require "enjine/deck_builder"

# Generated decks must look like constructed decks: never land-starved or land-flooded,
# always a mana source for every color they cast.
RSpec.describe "Deck builder sanity over many decks" do
  let(:dir) { File.expand_path("../fixtures/sets", __dir__) }

  it "keeps land counts, creature counts and color sources in constructed ranges" do
    lands_seen = []
    [[%w[fxa], 1], [%w[fxb], 2], [%w[fxa fxb], 3], [%w[fxa fxb], :any]].each do |sets, colors|
      25.times do |seed|
        deck = Enjine::DeckBuilder.build(seed: seed, sets: sets, colors: colors, sets_dir: dir)
        defs = deck["cards"].to_h { [Enjine::CardDefinition.slug(it["name"]), Enjine::CardDefinition.from_h(it)] }
        counts = deck["main"].to_h { [Enjine::CardDefinition.slug(it["card"]), it["count"]] }
        lands = counts.sum { |id, n| defs[id].land? ? n : 0 }
        spell_colors = counts.flat_map { |id, _| defs[id].land? ? [] : defs[id].mana_cost&.colored&.keys.to_a }.uniq
        land_colors = counts.flat_map { |id, _| defs[id].land? ? defs[id].mana_abilities.flat_map(&:produce) : [] }.uniq

        expect(counts.values.sum).to eq(60)
        expect(lands).to be_between(20, 27), "#{sets} #{colors} seed #{seed}: #{lands} lands"
        expect(spell_colors - land_colors).to be_empty, "#{sets} #{colors} seed #{seed}: no source for #{spell_colors - land_colors}"
        expect(Enjine::Deck.from_h(deck)).to be_valid
        lands_seen << lands
      end
    end
    expect(lands_seen.sum / lands_seen.size.to_f).to be_within(1.0).of(24)
  end

  it "stays inside its colors and balances them, so no chosen color is a token splash" do
    shares = []
    [[%w[fxa fxb], 2], [%w[fxa], %w[W U]]].each do |sets, colors|
      40.times do |seed|
        deck = Enjine::DeckBuilder.build(seed: seed, sets: sets, colors: colors, sets_dir: dir)
        chosen = deck["description"][/colors=([WUBRG]+)/, 1].chars
        symbols = Hash.new(0)
        deck["main"].each do |entry|
          defn = Enjine::CardDefinition.from_h(deck["cards"].find do
            Enjine::CardDefinition.slug(it["name"]) == Enjine::CardDefinition.slug(entry["card"])
          end)
          defn.mana_cost&.colored&.each { |color, n| symbols[color.to_s] += n * entry["count"] } unless defn.land?
        end
        expect(symbols.keys.sort).to eq(chosen.sort), "seed #{seed}: chose #{chosen}, used #{symbols.keys}"
        shares << (symbols.values.min.to_f / symbols.values.sum)
      end
    end
    expect(shares.min).to be >= 0.25
  end
end
