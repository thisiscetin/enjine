# frozen_string_literal: true

RSpec.describe "Random decks from card pools" do
  [%w[fxa], %w[fxb], %w[fxa fxb]].each do |pools|
    [1, 2, 3].each do |count|
      it "builds valid #{count}-color decks from #{pools.join(" + ")}" do
        deck_builder = builder(*pools)
        12.times do |seed|
          doc = deck_builder.build(colors: count, seed: seed)
          player = Enjine::Player.new(name: "p", deck: doc)
          expect(player).to be_ready, player.deck.errors.join("; ")
          expect(player.deck.size).to eq(60)

          colors = Enjine::DeckBuilder.parse_colors(doc["description"][/colors=(\w+)/, 1])
          expect(colors.size).to eq(count)
          defs = doc["cards"].map { Enjine::CardDefinition.from_h(it) }
          expect(defs).to all(satisfy { Enjine::DeckBuilder.fits?(it, colors) })
          expect(defs.select(&:land?).flat_map { Enjine::DeckBuilder.produced_colors(it) } - colors).to be_empty
        end
      end
    end
  end

  it "builds explicit-color decks that use every requested color" do
    %w[W U B R G WU BR GW UBR WBG].each do |colors|
      doc = build_deck(%w[fxa fxb], colors: colors, seed: colors.sum)
      used = doc["cards"].flat_map { Enjine::DeckBuilder.colors_of(Enjine::CardDefinition.from_h(it)) }.uniq
      expect(Enjine::DeckBuilder.parse_colors(colors) - used).to be_empty
      expect(Enjine::Player.new(name: "p", deck: doc)).to be_ready
    end
  end

  it "draws from the whole fixture card pool, every mechanic family" do
    core = Enjine::DeckBuilder.new(CardFixtures.cards).build(colors: "RG", seed: 5)
    expect(Enjine::Player.new(name: "p", deck: core)).to be_ready
  end

  it "seats two generated decks from different pools in one Setup" do
    alice = Enjine::Player.new(name: "alice", deck: build_deck(%w[fxa], colors: 2, seed: 1))
    bob = Enjine::Player.new(name: "bob", deck: build_deck(%w[fxb fxa], colors: 3, seed: 2))
    setup = Enjine::Setup.new(alice, bob)
    expect(setup.new_game(seed: 1).pending_decision).not_to be_nil
  end
end
