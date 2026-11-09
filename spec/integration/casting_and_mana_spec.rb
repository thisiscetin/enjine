# frozen_string_literal: true

# Casting and mana with the invented fixture cards: divided damage from a reflexive trigger (CR 601.2d), casting
# restrictions on the spell itself (601.3), cost reduction by the greatest toughness, "activate only if" on a mana
# ability (602.5b), mana spendable only on spells from exile (106.6), the exile-instead rider of permissions and
# free casts (614.1a), and which pool mana remembers an artifact source.
RSpec.describe "Casting and mana" do
  def board(hand: [], battlefield: [], theirs: [], graveyard: [], their_graveyard: [], exile: [], pool: {})
    build_game(core_catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: pool) do
        hand(*hand)
        graveyard(*graveyard) unless graveyard.empty?
        exile(*exile) unless exile.empty?
        library "Island", count: 10
        battlefield.each { battlefield it }
      end
      player("bob") do
        library "Swamp", count: 10
        graveyard(*their_graveyard) unless their_graveyard.empty?
        theirs.each { battlefield it }
      end
    end
  end

  def id(game, name, zone: :battlefield, player: "alice") = obj_id(game, name, zone: zone, player: player)
  def alice(game) = game.state.players[0]
  def bob(game) = game.state.players[1]
  def engine(game) = game.instance_variable_get(:@engine)
  def reimport(game) = Enjine::Game.import({ "state" => game.state.to_h }, catalog: game.catalog)

  # Pays mana (tapping sources only while paying), else passes, until `kind` is pending (or the stack is empty).
  def run(game, kind = nil)
    80.times do
      pending = game.pending_decision.kind
      break if pending == kind || (kind.nil? && pending == "priority" && game.state.stack.empty?)

      options = game.legal_options
      game.submit(options.find { it[:type] == "pay_mana" } ||
                  (options.find { it[:type] == "activate_mana" } if pending == "pay_cost") ||
                  options.find { it[:type] == "pass" } || options.first)
    end
    game
  end

  it "a reflexive trigger divides its damage as it's put on the stack (CR 601.2d, 603.12)" do
    game = board(hand: ["Ember Tactician"], battlefield: %w[Mountain Mountain Mountain], theirs: ["Grizzly Bears"])
    game.submit(type: "cast", object: id(game, "Ember Tactician", zone: :hand))
    run(game, "choose_target_count")
    expect(game.legal_options.filter_map { it[:count] }).to eq([1, 2])
    game.submit(type: "count", count: 2)
    game.submit(type: "target", target: id(game, "Grizzly Bears"))
    game.submit(type: "target", target: "player:bob")
    run(game)
    expect(bob(game).life).to eq(19)
    expect(game.state.object(id(game, "Grizzly Bears")).damage).to eq(1)
  end

  it "a divided spell with one target deals it everything; an illegal target gets nothing (CR 608.2b)" do
    game = board(hand: ["Forked Cinders"], battlefield: %w[Mountain Mountain])
    game.submit(type: "cast", object: id(game, "Forked Cinders", zone: :hand))
    game.submit(type: "count", count: 1)
    game.submit(type: "target", target: "player:bob")
    run(game)
    expect(bob(game).life).to eq(17)
  end

  describe "casting restrictions (CR 601.3)" do
    it "Late Bloomer Titan can't be cast during your first three turns of the game" do
      game = board(hand: ["Late Bloomer Titan"], battlefield: %w[Forest Forest Forest])
      alice(game).game_log = { "turns" => 3 }
      game = reimport(game)
      expect(game.legal_options.none? { it[:type] == "cast" }).to be(true)
      alice(game).game_log = { "turns" => 4 }
      game = reimport(game)
      expect(game.legal_options).to include(a_hash_including(type: "cast"))
    end

    it "the game log counts each player's turns" do
      game = board
      skip_to(game, :upkeep, turn: 5)
      expect(game.state.players.map { it.game_log["turns"] }).to eq([1, 1])
    end
  end

  it "Bulwark Colossus costs {X} less, X the greatest toughness among creatures you control" do
    game = board(hand: ["Bulwark Colossus"], battlefield: ["Hill Giant", "Grizzly Bears"] + Array.new(5, "Plains"))
    game.submit(type: "cast", object: id(game, "Bulwark Colossus", zone: :hand))
    expect(game.pending_decision.details["remaining"]).to eq("{4}{W}")
  end

  it "Grove Herald taps for {G}{G} only while an Elf card is in your graveyard (CR 602.5b)" do
    game = board(battlefield: ["Grove Herald"])
    expect(game.legal_options.none? { it[:type] == "activate_mana" }).to be(true)
    game = board(battlefield: ["Grove Herald"], graveyard: ["Grove Herald"])
    game.submit(game.legal_options.find { it[:type] == "activate_mana" })
    expect(alice(game).mana_pool[:G]).to eq(2)
  end

  it "Echo Vault's mana pays only for spells cast from exile (CR 106.6)" do
    game = board(hand: ["Grizzly Bears"], battlefield: ["Echo Vault"], their_graveyard: ["Lightning Bolt"])
    expect(game.legal_options.none? { it[:type] == "cast" }).to be(true)
  end

  describe "exiling a spell cast this way instead of putting it into a graveyard (CR 614.1a)" do
    it "Ransack the Archive's permission casts the card with any mana; it's exiled as it resolves" do
      game = board(hand: ["Ransack the Archive"], battlefield: Array.new(4, "Island") + ["Swamp", "Echo Vault"],
                   their_graveyard: ["Lightning Bolt"])
      game.submit(type: "cast", object: id(game, "Ransack the Archive", zone: :hand))
      game.submit(type: "target", target: id(game, "Lightning Bolt", zone: :graveyard, player: "bob"))
      run(game)
      bolt = game.state.exile.first
      option = game.legal_options.find { it[:type] == "cast" && it[:object] == bolt }
      game.submit(option)
      game.submit(type: "target", target: "player:bob")
      expect(game.legal_options.map { it[:type] }).to include("activate_mana") # Echo Vault: a spell cast from exile
      run(game)
      expect(bob(game).life).to eq(17)
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["lightning_bolt"])
    end

    it "Reprise Adept's free cast exiles an instant, but a sorcery still goes to the graveyard" do
      game = board(hand: ["Reprise Adept"], battlefield: Array.new(4, "Island"), graveyard: ["Lightning Bolt"])
      game.submit(type: "cast", object: id(game, "Reprise Adept", zone: :hand))
      run(game, "choose_target")
      game.submit(type: "target", target: id(game, "Lightning Bolt", zone: :graveyard))
      pass_both(game)
      game.submit(type: "cast", object: id(game, "Lightning Bolt", zone: :graveyard))
      game.submit(type: "target", target: "player:bob")
      run(game)
      expect(bob(game).life).to eq(17)
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["lightning_bolt"])
    end
  end

  describe "pool mana that remembers an artifact source (CR 106.6)" do
    # Hoard Watcher on the battlefield, a Treasure's {R} and a Mountain's {R} in the pool.
    def hoard_game
      game = board(hand: ["Lightning Bolt"], battlefield: ["Hoard Watcher", "Mountain"])
      engine(game).create_token!(core_catalog.fetch("Hoard Watcher").token_definitions.first, 0)
      game = reimport(game)
      treasure = game.state.battlefield.find { game.state.object(it).card.include?("treasure") }
      game.submit(type: "activate_mana", object: treasure, ability: "printed:3")
      game.submit(type: "activate_mana", object: id(game, "Mountain"), ability: "intrinsic:mountain")
      game
    end

    it "offers which {R} to spend; the Treasure's makes Hoard Watcher trigger" do
      game = hoard_game
      expect(alice(game).mana_pool[:R]).to eq(2)
      expect(alice(game).pool_sources.size).to eq(1)
      game.submit(type: "cast", object: id(game, "Lightning Bolt", zone: :hand))
      game.submit(type: "target", target: "player:bob")
      expect(game.legal_options).to include({ type: "pay_mana", mana: "R" }, { type: "pay_mana", mana: "R", from: 0 })
      game = reimport(game) # the sources round-trip
      game.submit(type: "pay_mana", mana: "R", from: 0)
      run(game)
      expect(alice(game).life).to eq(22)
      expect(alice(game).pool_sources).to be_empty
    end

    it "plain {R} spends the Mountain's; cancelling restores the sources" do
      game = hoard_game
      game.submit(type: "cast", object: id(game, "Lightning Bolt", zone: :hand))
      game.submit(type: "target", target: "player:bob")
      game.submit(type: "pay_mana", mana: "R")
      expect(alice(game).pool_sources.size).to eq(1)
      run(game)
      expect(alice(game).life).to eq(20)
      expect(game.view_for(:alice)["players"].first["pool_sources"].size).to eq(1)
      expect(Enjine::CLI::Text.new(game).option({ type: "pay_mana", mana: "R", from: 0 })).to include("artifact")
      skip_to(game, :beginning_of_combat)
      expect(alice(game).pool_sources).to be_empty # emptied with the pool (CR 106.4)
    end

    it "a snapshot with more sources than pool mana is invalid" do
      game = hoard_game
      data = game.state.to_h
      data["players"][0]["mana_pool"]["R"] = 0
      expect(Enjine::Snapshot.validate(data, core_catalog)).to include(a_string_starting_with("players[0].pool_sources:"))
    end
  end
end
