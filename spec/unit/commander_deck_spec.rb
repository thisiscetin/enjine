# frozen_string_literal: true

RSpec.describe "Commander decks (CR 903)" do
  let(:duel) { Enjine::Format::DUEL_COMMANDER }
  let(:pool) do
    [{ "name" => "Test Warden", "mana_cost" => "{2}{G}", "types" => ["creature"], "supertypes" => ["legendary"],
       "power" => 3, "toughness" => 3 },
     { "name" => "Red Bolt", "mana_cost" => "{R}", "types" => ["instant"] },
     { "name" => "Vine Charm", "mana_cost" => "{G}", "types" => ["instant"] },
     { "name" => "Wastes", "types" => ["land"], "supertypes" => ["basic"] },
     { "name" => "Forest", "types" => ["land"], "supertypes" => ["basic"], "subtypes" => ["forest"] },
     { "name" => "Mountain", "types" => ["land"], "supertypes" => ["basic"], "subtypes" => ["mountain"] },
     { "name" => "Bear", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 2, "toughness" => 2 }]
  end

  # 98 distinct filler cards are impossible with a small pool; the deck pads with basic Forests, which are exempt.
  def deck(main: [{ "card" => "Forest", "count" => 99 }], commander: "Test Warden", cards: pool, **rest)
    Enjine::Deck.from_h({ "cards" => cards, "main" => main, "commander" => commander }.compact.merge(rest.transform_keys(&:to_s)))
  end

  describe Enjine::Format do
    it "knows its presets and finds them by name" do
      expect(described_class.fetch(:duel_commander)).to be(duel)
      expect(described_class.fetch("constructed")).to be(described_class::CONSTRUCTED)
      expect(described_class.fetch(duel)).to be(duel)
      expect([duel.starting_life, duel.deck_size, duel.commander?]).to eq([40, 100..100, true])
      expect([described_class::CONSTRUCTED.starting_life, described_class::CONSTRUCTED.commander?]).to eq([20, false])
      expect(duel.to_s).to eq("duel_commander")
    end

    it "rejects unknown formats" do
      expect { described_class.fetch(:brawl) }.to raise_error(ArgumentError, /unknown format :brawl \(use :constructed, :duel_commander\)/)
    end

    it "decides who may be a commander (CR 903.3): a legendary creature, Vehicle or Spacecraft with P/T" do
      card = ->(extra) { Enjine::CardDefinition.from_h({ "name" => "C", "types" => ["artifact"], "supertypes" => ["legendary"] }.merge(extra)) }
      symbol = { "station_symbol" => { "at" => 3, "power" => 2, "toughness" => 2 } }
      expect(described_class.commander_card?(card.call("types" => ["creature"], "power" => 1, "toughness" => 1))).to be(true)
      expect(described_class.commander_card?(card.call("subtypes" => ["vehicle"], "power" => 1, "toughness" => 1))).to be(true)
      expect(described_class.commander_card?(card.call("subtypes" => ["spacecraft"], "keywords" => ["station"],
                                                       "abilities" => [symbol]))).to be(true)
      expect(described_class.commander_card?(card.call("subtypes" => ["spacecraft"], "keywords" => ["station"]))).to be(false)
      expect(described_class.commander_card?(card.call({}))).to be(false)
      expect(described_class.commander_card?(card.call("supertypes" => [], "types" => ["creature"], "power" => 1,
                                                       "toughness" => 1))).to be(false)
    end
  end

  describe Enjine::ColorIdentity do
    def identity(card) = Enjine::CardDefinition.from_h(card).color_identity

    it "takes the colors of the mana cost, hybrid and monocolored hybrid symbols included" do
      expect(identity("name" => "A", "types" => ["instant"], "mana_cost" => "{1}{U}{U}")).to eq([:U])
      expect(identity("name" => "A", "types" => ["instant"], "mana_cost" => "{R/G}{R/G}")).to eq(%i[R G])
      expect(identity("name" => "A", "types" => ["instant"], "mana_cost" => "{2/W}")).to eq([:W])
      expect(identity("name" => "A", "types" => ["artifact"], "mana_cost" => "{3}")).to eq([])
    end

    it "includes the symbols in abilities: costs and produced mana (CR 903.4)" do
      pay = { "activated" => { "cost" => [{ "mana" => "{2}{B}" }], "effects" => [{ "gain_life" => { "amount" => 1 } }] } }
      card = { "name" => "A", "types" => ["creature"], "power" => 1, "toughness" => 1, "mana_cost" => "{1}{W}",
               "abilities" => [pay,
                               { "mana" => { "cost" => ["tap"], "produce" => "{R}" } }] }
      expect(identity(card)).to eq(%i[W B R])
    end

    it "never reads the rules text (reminder text doesn't count, CR 903.4c)" do
      expect(identity("name" => "A", "types" => ["instant"], "mana_cost" => "{G}",
                      "rules_text" => "{T}: Add {U}. ({R} and more)")).to eq([:G])
    end

    it "adds the color indicator and the colors of basic land types (CR 903.5d)" do
      expect(identity("name" => "A", "types" => ["creature"], "power" => 1, "toughness" => 1, "colors" => ["u"])).to eq([:U])
      expect(identity("name" => "Isle", "types" => ["land"], "subtypes" => %w[island swamp])).to eq(%i[U B])
    end

    it "can be stated by hand for a face the data can't describe" do
      card = { "name" => "A", "types" => ["instant"], "mana_cost" => "{R}", "color_identity" => ["w"] }
      expect(identity(card)).to eq([:W])
      expect(Enjine::CardDefinition.from_h(card).to_h["color_identity"]).to eq(["W"])
      expect { Enjine::CardDefinition.from_h(card.merge("color_identity" => ["x"])) }
        .to raise_error(Enjine::InvalidCardDefinition, /color_identity: must be a list of W, U, B, R, G/)
    end

    it "covers every face of a double-faced card (CR 903.4d)" do
      monica = CardFixtures.real_cards.find { it["name"].start_with?("Monica Rambeau") }
      expect(identity(monica)).to eq(%i[W R])
      void = CardFixtures.real_cards.find { it["name"].start_with?("Void Extrapolator") } # a prepare card's second face (CR 903.4e)
      expect(identity(void)).to eq(%i[U B])
    end

    it "matches real cards" do
      real = CardFixtures.real_cards.to_h { [it["name"], it] }
      expect(identity(real.fetch("Pumpkin Bombardment"))).to eq(%i[B R])
      expect(identity(real.fetch("Theorist's Sanctum"))).to eq([:U])
      expect(identity(real.fetch("Plains"))).to eq([:W])
    end
  end

  describe Enjine::Deck do
    it "is legal with a commander and 99 other cards (CR 903.5a)" do
      expect(deck.errors(duel)).to eq([])
      expect(deck.commander).to eq("test_warden")
      expect(deck.size).to eq(99)
      expect(deck).to be_valid(duel)
    end

    it "keeps its commander through a document round trip" do
      doc = deck.to_h
      expect(doc["commander"]).to eq("test_warden")
      expect(Enjine::Deck.from_h(doc).commander).to eq("test_warden") # rubocop:disable RSpec/DescribedClass -- nested describe
    end

    it "needs exactly 100 cards, its commander included (CR 903.5a)" do
      expect(deck(main: [{ "card" => "Forest", "count" => 98 }]).errors(duel))
        .to eq(["deck has 99 cards; exactly 100 are required, its commander included (CR 903.5a)"])
      expect(deck(main: [{ "card" => "Forest", "count" => 100 }]).errors(duel))
        .to eq(["deck has 101 cards; exactly 100 are required, its commander included (CR 903.5a)"])
    end

    it "needs a commander" do
      expect(deck(commander: nil).errors(duel)).to include("a Commander deck needs a commander (CR 903.3)")
    end

    it "is singleton: only basic lands may repeat (CR 903.5b)" do
      main = [{ "card" => "Forest", "count" => 97 }, { "card" => "Bear", "count" => 2 }]
      expect(deck(main: main).errors(duel)).to eq(["Bear: 2 copies; at most 1 are allowed (CR 903.5b)"])
    end

    it "counts the commander, and cards outside the game, toward the singleton rule" do
      main = [{ "card" => "Forest", "count" => 98 }, { "card" => "Test Warden", "count" => 1 }]
      expect(deck(main: main).errors(duel)).to eq(["Test Warden: 2 copies; at most 1 are allowed (CR 903.5b)"])
      expect(deck(outside: [{ "card" => "Test Warden", "count" => 1 }]).errors(duel))
        .to eq(["Test Warden: 2 copies; at most 1 are allowed (CR 903.5b)"])
    end

    it "doesn't exempt \"any number\" cards from the singleton rule (only basic lands are, CR 903.5b)" do
      rats = { "name" => "Rats", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 1, "toughness" => 1, "deck_limit" => "any" }
      main = [{ "card" => "Forest", "count" => 97 }, { "card" => "Rats", "count" => 2 }]
      expect(deck(main: main, cards: pool + [rats]).errors(duel)).to eq(["Rats: 2 copies; at most 1 are allowed (CR 903.5b)"])
      expect(deck(main: main,
                  cards: pool + [rats]).errors(Enjine::Format::CONSTRUCTED)).to eq(["commander: only a Commander deck has one (CR 903.3)"])
    end

    it "keeps every card inside the commander's color identity (CR 903.5c)" do
      main = [{ "card" => "Forest", "count" => 98 }, { "card" => "Red Bolt", "count" => 1 }]
      expect(deck(main: main).errors(duel)).to eq(["Red Bolt: color identity {R} is not in its commander's (CR 903.5c)"])
    end

    it "bars basic lands of other colors (CR 903.5d)" do
      main = [{ "card" => "Forest", "count" => 98 }, { "card" => "Mountain", "count" => 1 }]
      expect(deck(main: main).errors(duel)).to eq(["Mountain: color identity {R} is not in its commander's (CR 903.5c)"])
      expect(deck(main: [{ "card" => "Forest", "count" => 98 }, { "card" => "Wastes", "count" => 1 }]).errors(duel)).to eq([])
    end

    it "needs a legal commander card (CR 903.3)" do
      expect(deck(commander: "Bear").errors(duel).first).to include("Bear: can't be a commander; it must be a legendary creature")
    end

    it "reports a commander that isn't in the deck's cards" do
      expect(deck(commander: "Nobody").errors(duel)).to include("commander: \"Nobody\" is not defined in cards")
      expect do
        Enjine::Deck.from_h("cards" => pool, "main" => [], "commander" => 3) # rubocop:disable RSpec/DescribedClass
      end.to raise_error(Enjine::InvalidDeck, /commander: must be a card name/)
    end

    it "has no commander in constructed (CR 903.3)" do
      constructed = deck(main: [{ "card" => "Forest", "count" => 60 }])
      expect(constructed.errors).to eq(["commander: only a Commander deck has one (CR 903.3)"])
      expect(deck(commander: nil, main: [{ "card" => "Forest", "count" => 60 }])).to be_valid
    end

    it "is not ready for a format it doesn't fit" do
      player = Enjine::Player.new(name: "alice", deck: deck)
      expect(player.ready?(duel)).to be(true)
      expect(player.ready?).to be(false) # constructed rejects a commander
      expect do
        Enjine::Setup.new(player,
                          Enjine::Player.new(name: "bob", deck: deck))
      end.to raise_error(Enjine::PlayerNotReady, /only a Commander deck has one/)
    end
  end

  describe Enjine::Setup do
    let(:players) { %w[alice bob].map { Enjine::Player.new(name: it, deck: deck) } }

    it "carries the format and the commanders it was compiled with" do
      setup = described_class.new(*players, format: :duel_commander)
      expect([setup.format, setup.commanders]).to eq([Enjine::Format::DUEL_COMMANDER, %w[test_warden test_warden]])
      expect(described_class.new(Enjine::Player.new(name: "a", deck: basics_deck), Enjine::Player.new(name: "b", deck: basics_deck)).format)
        .to be(Enjine::Format::CONSTRUCTED)
    end

    it "refuses a deck that is not legal Commander" do
      bad = Enjine::Player.new(name: "bob", deck: deck(main: [{ "card" => "Forest", "count" => 60 }]))
      expect { described_class.new(players.first, bad, format: :duel_commander) }
        .to raise_error(Enjine::PlayerNotReady, /bob is not ready.*exactly 100/m)
    end

    it "resumes a Commander snapshot" do
      setup = described_class.new(*players, format: :duel_commander)
      game = through_pregame(setup.new_game(seed: 3))
      expect(setup.import(game.export).state.to_h).to eq(game.state.to_h)
    end
  end
end
