# frozen_string_literal: true

RSpec.describe Enjine::Deck do
  let(:pool) { Enjine::CardPool::Core.cards }
  let(:nonbasic) { { "name" => "Lone Tower", "types" => ["land"] } }

  def deck(main, cards: pool)
    described_class.from_h("cards" => cards, "main" => main)
  end

  it "is valid with 60 basic lands" do
    d = deck([{ "card" => "Forest", "count" => 60 }])
    expect(d).to be_valid
    expect(d.size).to eq(60)
    expect(d.count("Forest")).to eq(60)
    expect(d.card_ids.uniq).to eq(["forest"])
  end

  it "requires at least 60 cards (CR 100.2a)" do
    expect(deck([{ "card" => "Forest", "count" => 59 }]).errors).to eq(
      ["deck has 59 cards; at least 60 are required (CR 100.2a)"]
    )
  end

  it "limits non-basic cards to four copies" do
    d = deck([{ "card" => "Lone Tower", "count" => 5 }, { "card" => "Forest", "count" => 55 }], cards: pool + [nonbasic])
    expect(d.errors).to eq(["Lone Tower: 5 copies; at most 4 are allowed (CR 100.2a)"])
  end

  it "reports malformed and undefined entries" do
    d = deck([{ "card" => "Bolt", "count" => 1 }, { "card" => "Forest" }, "x"])
    expect(d.errors).to include(a_string_matching(/main\[0\]: card "Bolt" is not defined/),
                                a_string_matching(/main\[1\]: must be/), a_string_matching(/main\[2\]: must be/))
  end

  it "rejects malformed documents" do
    expect { described_class.from_h("x") }.to raise_error(Enjine::InvalidDeck)
    expect { described_class.from_h("cards" => {}) }.to raise_error(Enjine::InvalidDeck, /cards: must be a list/)
    expect { described_class.from_h("main" => {}) }.to raise_error(Enjine::InvalidDeck, /main: must be a list/)
    expect { described_class.from_h("cards" => [{ "name" => "?" }]) }.to raise_error(Enjine::InvalidCardDefinition)
  end

  it "adds, removes and swaps cards between games" do
    d = deck([{ "card" => "Forest", "count" => 60 }])
    d.swap(out: "Forest", in: "Island", count: 20)
    expect(d.entries).to eq("forest" => 40, "island" => 20)
    d.remove("Island", count: 20)
    expect(d.entries).to eq("forest" => 40)
    expect(d).not_to be_valid
    d.add("Mountain", count: 20)
    expect(d).to be_valid
    d.define(nonbasic)
    d.add("Lone Tower")
    expect(d.size).to eq(61)
  end

  it "rejects edits that reference undefined cards or impossible counts" do
    d = deck([{ "card" => "Forest", "count" => 60 }])
    expect { d.add("Black Lotus") }.to raise_error(Enjine::InvalidDeck, /not defined/)
    expect { d.remove("Island") }.to raise_error(Enjine::InvalidDeck, /deck has 0/)
    expect { d.add("Forest", count: 0) }.to raise_error(ArgumentError)
    expect { d.swap(out: "Forest", in: "Black Lotus") }.to raise_error(Enjine::InvalidDeck)
    expect(d.count("Forest")).to eq(60)
  end

  it "round-trips through to_h" do
    d = deck([{ "card" => "Forest", "count" => 30 }, { "card" => "Island", "count" => 30 }])
    copy = described_class.from_h(d.to_h)
    expect(copy.entries).to eq(d.entries)
    expect(described_class.from_h(copy)).to be(copy)
  end
end
