# frozen_string_literal: true

RSpec.describe Enjine::Deck do
  let(:pool) { CardFixtures.cards }
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

  it "honours a card's own deck limit: any number, or up to N (CR 100.2a)" do
    swarm = { "name" => "Spec Hare Swarm", "mana_cost" => "{1}{W}", "types" => ["creature"], "power" => 1, "toughness" => 1,
              "deck_limit" => "any" }
    dwarves = { "name" => "Spec Seven Smiths", "mana_cost" => "{1}{R}", "types" => ["creature"], "power" => 2, "toughness" => 2,
                "deck_limit" => 7 }
    d = deck([{ "card" => "Spec Hare Swarm", "count" => 30 }, { "card" => "Spec Seven Smiths", "count" => 8 },
              { "card" => "Forest", "count" => 22 }], cards: pool + [swarm, dwarves])
    expect(d.errors).to eq(["Spec Seven Smiths: 8 copies; at most 7 are allowed (CR 100.2a)"])
    expect(d.catalog.fetch("spec_hare_swarm").deck_limit).to be_nil
    expect(d.catalog.fetch("spec_hare_swarm").source["deck_limit"]).to eq("any")
    expect { Enjine::CardDefinition.from_h(swarm.merge("deck_limit" => 0)) }
      .to raise_error(Enjine::InvalidCardDefinition, /deck_limit: must be "any" or an integer >= 1/)
  end

  it "reports malformed and undefined entries" do
    d = deck([{ "card" => "Bolt", "count" => 1 }, { "card" => "Forest" }, "x"])
    expect(d.errors).to include(a_string_matching(/main\[0\].card: "Bolt" is not defined/),
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
    expect(copy.to_h).not_to have_key("outside")
  end

  describe "cards outside the game (CR 400.11a, 100.4a)" do
    let(:forests) { [{ "card" => "Forest", "count" => 56 }, { "card" => "Lone Tower", "count" => 4 }] }

    def with_outside(outside, main: forests)
      described_class.from_h("cards" => pool + [nonbasic], "main" => main, "outside" => outside)
    end

    it "keeps an outside list that isn't part of the 60 and round-trips through to_h" do
      d = with_outside([{ "card" => "Grizzly Bears", "count" => 2 }, { "card" => "Island", "count" => 13 }])
      expect(d).to be_valid
      expect(d.size).to eq(60)
      expect(d.outside_size).to eq(15)
      expect(d.outside_entries).to eq("grizzly_bears" => 2, "island" => 13)
      expect(d.outside_ids.count("island")).to eq(13)
      copy = described_class.from_h(d.to_h)
      expect(copy.to_h["outside"]).to eq([{ "card" => "grizzly_bears", "count" => 2 }, { "card" => "island", "count" => 13 }])
      expect(copy.outside_entries).to eq(d.outside_entries)
    end

    it "holds at most 15 cards" do
      expect(with_outside([{ "card" => "Island", "count" => 16 }]).errors)
        .to eq(["outside: 16 cards; at most 15 are allowed (CR 100.4a)"])
    end

    it "applies the four-copy limit to the deck and the outside list together" do
      d = with_outside([{ "card" => "Lone Tower", "count" => 1 }])
      expect(d.errors).to eq(["Lone Tower: 5 copies; at most 4 are allowed (CR 100.2a, 100.4a)"])
    end

    it "reports path-addressed errors for bad entries" do
      d = with_outside([{ "card" => "Grizzly Bears", "count" => 1 }, { "card" => "Black Lotus", "count" => 1 }, { "card" => "x" }])
      expect(d.errors).to eq(["outside[1].card: \"Black Lotus\" is not defined in cards",
                              "outside[2]: must be {\"card\": name, \"count\": positive integer}"])
      expect { described_class.from_h("outside" => {}) }.to raise_error(Enjine::InvalidDeck, /outside: must be a list/)
    end

    it "adds cards to the outside list" do
      d = with_outside([])
      d.add_outside("Grizzly Bears", count: 2)
      expect(d.outside_entries).to eq("grizzly_bears" => 2)
      expect { d.add_outside("Black Lotus") }.to raise_error(Enjine::InvalidDeck, /not defined/)
    end
  end
end
