# frozen_string_literal: true

RSpec.describe "Small units" do
  it "redacts bottomed cards for everyone but the decider" do
    option = { type: "bottom", object: "forest#1" }
    expect(Enjine::Decisions::Bottom.redact(option, true)).to eq(option)
    expect(Enjine::Decisions::Bottom.redact(option, false)).to eq(type: "bottom")
    expect { Enjine::Decisions.fetch("vote") }.to raise_error(ArgumentError, /unknown decision kind/)
  end

  it "documents empty categories" do
    allow(Enjine.registry).to receive(:each).and_call_original
    allow(Enjine.registry).to receive(:each).with(:supertype).and_return([])
    expect(Enjine::Docs.reference(:supertype)).to include("_None yet._")
    expect(Enjine::Docs.supported).to include("## Supertypes\n\n_None yet._")
  end

  it "loads sample decks and rejects unknown ones" do
    deck = Enjine::CardPool::Core.deck("izzet_spells")
    expect(Enjine::Deck.from_h(deck)).to be_valid
    expect { Enjine::CardPool::Core.deck("nope") }.to raise_error(ArgumentError, /unknown sample deck/)
  end

  it "builds random legal decks" do
    deck = Enjine::CardPool::DeckBuilder.random(Enjine::CardPool::Core.cards, rng: Enjine::Rng.from_seed(5))
    expect(Enjine::Deck.from_h(deck)).to be_valid
    expect(deck).not_to have_key("outside")
    with_outside = Enjine::Deck.from_h(Enjine::CardPool::DeckBuilder.random(Enjine::CardPool::Core.cards,
                                                                            rng: Enjine::Rng.from_seed(5), outside: 15))
    expect(with_outside).to be_valid
    expect([with_outside.size, with_outside.outside_size]).to eq([60, 15])
    expect(with_outside.entries).to eq(Enjine::Deck.from_h(deck).entries) # the same main deck
  end
end
