# frozen_string_literal: true

RSpec.describe Enjine::Player do
  it "is ready only with a valid deck" do
    expect(described_class.new(name: "a", deck: basics_deck)).to be_ready
    expect(described_class.new(name: "a", deck: basics_deck("Forest" => 10))).not_to be_ready
  end

  it "requires a name" do
    expect { described_class.new(name: "", deck: basics_deck) }.to raise_error(ArgumentError)
  end

  it "locks the deck while seated in an unfinished game, unlocks when it ends" do
    alice = described_class.new(name: "alice", deck: basics_deck)
    bob = described_class.new(name: "bob", deck: basics_deck)
    game = Enjine::Setup.new(alice, bob).new_game(seed: 1)
    expect(alice).to be_playing
    expect { alice.deck.swap(out: "Forest", in: "Island") }.to raise_error(Enjine::DeckLocked, /alice/)
    expect { alice.deck.define(CardFixtures.cards.first) }.to raise_error(Enjine::DeckLocked)

    game.concede("bob")
    expect(alice).not_to be_playing
    alice.deck.swap(out: "Forest", in: "Island", count: 10)
    expect(alice.deck.count("Island")).to eq(10)
  end
end
