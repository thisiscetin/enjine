# frozen_string_literal: true

RSpec.describe Enjine::Setup do
  let(:alice) { Enjine::Player.new(name: "alice", deck: basics_deck) }
  let(:bob) { Enjine::Player.new(name: "bob", deck: basics_deck("Island" => 30, "Swamp" => 30)) }

  it "compiles a shared frozen catalog and decklists" do
    setup = described_class.new(alice, bob)
    expect(setup).to be_frozen
    expect(setup.catalog.ids).to match_array(Enjine::CardPool::Core.cards.map { Enjine::CardDefinition.slug(it["name"]) })
    expect(setup.decklists.map(&:size)).to eq([60, 60])
    expect(setup.names).to eq(%w[alice bob])
  end

  it "requires two ready players with distinct names" do
    expect { described_class.new(alice) }.to raise_error(ArgumentError, /exactly 2/)
    expect { described_class.new(alice, Enjine::Player.new(name: "alice", deck: basics_deck)) }
      .to raise_error(ArgumentError, /differ/)
    short = Enjine::Player.new(name: "carol", deck: basics_deck("Forest" => 3))
    expect { described_class.new(alice, short) }.to raise_error(Enjine::PlayerNotReady, /carol.*at least 60/m)
  end

  it "raises CatalogConflict when players define a card differently" do
    weird = Enjine::CardPool::Core.cards.map { it["name"] == "Forest" ? it.merge("supertypes" => []) : it }
    carol = Enjine::Player.new(name: "carol",
                               deck: { "cards" => weird, "main" => [{ "card" => "Island", "count" => 56 },
                                                                    { "card" => "Forest", "count" => 4 }] })
    expect { described_class.new(alice, carol) }.to raise_error(Enjine::CatalogConflict)
  end

  it "is unaffected by deck edits made after compiling" do
    setup = described_class.new(alice, bob)
    setup.new_game(seed: 1).concede("alice")
    alice.deck.swap(out: "Forest", in: "Island", count: 30)
    expect(setup.decklists.first.count("forest")).to eq(30)
  end

  it "spawns identical games for the same seed and different ones otherwise" do
    setup = described_class.new(alice, bob)
    first = setup.new_game(seed: 5).state.to_h
    expect(setup.new_game(seed: 5).state.to_h).to eq(first)
    libraries = (1..5).map do |seed|
      game = setup.new_game(seed: seed)
      game.submit(type: "play")
      game.state.players.map(&:hand)
    end
    expect(libraries.uniq.size).to be > 1
  end
end
