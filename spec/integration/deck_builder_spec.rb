# frozen_string_literal: true

RSpec.describe "Random decks from card sets" do
  let(:dir) { DeckBuilderHelpers::SET_FIXTURES }

  [%w[fxa], %w[fxb], %w[fxa fxb]].each do |sets|
    [1, 2, 3].each do |count|
      it "builds valid #{count}-color decks from #{sets.join(" + ")}" do
        12.times do |seed|
          doc = build_deck(sets: sets, colors: count, seed: seed)
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
      doc = build_deck(sets: %w[fxa fxb], colors: colors, seed: colors.sum)
      used = doc["cards"].flat_map { Enjine::DeckBuilder.colors_of(Enjine::CardDefinition.from_h(it)) }.uniq
      expect(Enjine::DeckBuilder.parse_colors(colors) - used).to be_empty
      expect(Enjine::Player.new(name: "p", deck: doc)).to be_ready
    end
  end

  it "draws from every Standard-legal set and from the core sample pool" do
    standard = Enjine::Sets.standard_legal(on: Date.new(2026, 1, 1), dir: dir)
    doc = Enjine::DeckBuilder.build(sets: standard, colors: "R", seed: 5, sets_dir: dir)
    expect(doc["description"]).to include("sets=fxa ")
    core = Enjine::DeckBuilder.build(cards: Enjine::CardPool::Core.cards, colors: "RG", seed: 5)
    expect(Enjine::Player.new(name: "p", deck: core)).to be_ready
    expect(build_deck(colors: :any, seed: 3)["description"]).to include("sets=fxa,fxb")
  end

  it "seats two generated decks from different sets in one Setup" do
    alice = Enjine::Player.new(name: "alice", deck: build_deck(sets: %w[fxa], colors: 2, seed: 1))
    bob = Enjine::Player.new(name: "bob", deck: build_deck(sets: %w[fxb fxa], colors: 3, seed: 2))
    setup = Enjine::Setup.new(alice, bob)
    expect(setup.new_game(seed: 1).pending_decision).not_to be_nil
  end
end
