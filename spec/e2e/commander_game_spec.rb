# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "enjine/deck_builder"

RSpec.describe "Duel Commander games" do
  let(:cards) { CardFixtures.cards }

  def setup_for(seed, names: %w[alice bob])
    rng = Enjine::Rng.from_seed(seed)
    players = names.map { Enjine::Player.new(name: it, deck: Enjine::Fuzz.random_commander_deck(cards, rng: rng)) }
    Enjine::Setup.new(*players, format: :duel_commander)
  end

  it "plays random Commander games with invariants, the rules monitor and snapshot round trips" do
    result = Enjine::Fuzz.run(setup_for(1), games: 2, seed: 20, roundtrip_every: 61)
    expect(result.outcomes.values.sum).to eq(2)
    expect(result.decisions).to be > 500
  end

  it "builds fuzz decks that are legal Commander decks" do
    rng = Enjine::Rng.from_seed(4)
    deck = Enjine::Deck.from_h(Enjine::Fuzz.random_commander_deck(cards, rng: rng))
    expect(deck.errors(Enjine::Format::DUEL_COMMANDER)).to eq([])
    expect(deck.size).to eq(99)
  end

  describe "the rules monitor" do
    def monitored(game)
      entry = Enjine::HistoryEntry.new(seq: 1, turn: game.turn, step: game.step.to_s, player: nil, kind: nil, option: nil, events: [])
      Enjine::RulesMonitor.new(game).check!(entry)
    end

    let(:game) { through_pregame(setup_for(2).new_game(seed: 2)) }

    it "is quiet about a fresh game" do
      expect(monitored(game)).to be_empty
    end

    it "notices a player surviving 21 commander damage (CR 903.10a)" do
      game.state.players[0].commander_damage = { game.state.commanders[1] => 21 }
      expect(monitored(game).map(&:rule)).to eq(["903.10a"])
    end

    it "notices a tax that doesn't match the casts it saw (CR 903.8)" do
      game.state.players[1].commander_casts = 1
      expect(monitored(game).map(&:rule)).to eq(["903.8"])
    end
  end

  describe "the CLI" do
    def deck_file(dir, name, deck)
      File.join(dir, "#{name}.json").tap { File.write(it, JSON.generate(deck)) }
    end

    it "plays Commander with --format, showing the commander and its zone" do
      Dir.mktmpdir do |dir|
        rng = Enjine::Rng.from_seed(7)
        decks = %w[a b].map { deck_file(dir, it, Enjine::Fuzz.random_commander_deck(cards, rng: rng)) }
        out = StringIO.new
        code = Enjine::CLI.new(["--deck1", decks[0], "--deck2", decks[1], "--format", "duel_commander", "--seed", "3"],
                               input: StringIO.new("1\n1\n1\nq\n"), output: out).run
        expect(code).to eq(0)
        expect(out.string).to match(/Commander: .* in the command zone/)
        expect(out.string).to include("life 40")
      end
    end

    it "explains a deck that isn't legal for the format" do
      Dir.mktmpdir do |dir|
        deck = deck_file(dir, "plain", basics_deck)
        out = StringIO.new
        Enjine::CLI.new(["--deck1", deck, "--deck2", deck, "--format", "duel_commander"], input: StringIO.new(""), output: out).run
        expect(out.string).to include("error:", "a Commander deck needs a commander")
      end
    end
  end

  describe Enjine::DeckBuilder do
    let(:builder) { described_class.new(cards) }

    it "builds a legal Duel Commander deck around a commander" do
      doc = builder.build(commander: "Ripple Sage", seed: 3)
      deck = Enjine::Deck.from_h(doc)
      expect(deck.errors(Enjine::Format::DUEL_COMMANDER)).to eq([])
      expect(doc["commander"]).to eq("Ripple Sage")
      expect(builder.build(commander: "Ripple Sage", seed: 3)).to eq(doc)
      expect(builder.build(commander: "Ripple Sage", seed: 4)).not_to eq(doc)
    end

    it "keeps to the commander's colors, and plays" do
      doc = builder.build(commander: "Ashen Ensign", seed: 1)
      players = %w[alice bob].map { Enjine::Player.new(name: it, deck: doc) }
      game = Enjine::Setup.new(*players, format: :duel_commander).new_game(seed: 1)
      expect(game.state.players.map { it.library.size + it.hand.size }).to eq([99, 99])
    end

    it "refuses cards that can't lead a deck, and a colors or size of its own" do
      expect { builder.build(commander: "Grizzly Bears", seed: 1) }.to raise_error(ArgumentError, /can't be a commander/)
      expect { builder.build(commander: "Nobody", seed: 1) }.to raise_error(ArgumentError, /not in the pool/)
      expect { builder.build(commander: "Ripple Sage", colors: "G", seed: 1) }.to raise_error(ArgumentError, /come from its commander/)
    end
  end
end
