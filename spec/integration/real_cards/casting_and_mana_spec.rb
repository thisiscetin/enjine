# frozen_string_literal: true

# Real cards that needed casting and mana primitives: damage divided among targets as the spell or ability is
# put on the stack (Twin Bolt, Gandalf, Ureni; CR 601.2d), "you can't cast this spell unless" (Proft, CR 601.3),
# mana spent compared with the mana value (Unravel, Tokka & Rahzar), "if that spell would be put into a graveyard,
# exile it instead" (Quistis Trepe, The Dawning Archaic).
RSpec.describe "Real cards: casting and mana" do
  let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.real_cards) }

  def board(hand: [], battlefield: [], theirs: [], graveyard: [], their_graveyard: [], library_top: [], turn: 3)
    build_game(catalog) do
      turn turn, active: "alice", step: :precombat_main
      player("alice") do
        hand(*hand)
        graveyard(*graveyard) unless graveyard.empty?
        library(*library_top) unless library_top.empty?
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

  # The default answer: pays mana while paying (activating sources as needed), else passes, else the first option.
  def default_choice(game)
    options = game.legal_options
    paying = game.pending_decision.kind == "pay_cost"
    options.find { it[:type] == "pay_mana" } || (options.find { it[:type] == "activate_mana" } if paying) ||
      options.find { it[:type] == "pass" } || options.first
  end

  # Answers decisions like #run until a decision of `kind` is pending.
  def run_until(game, kind)
    80.times do
      break if game.pending_decision.kind == kind

      game.submit(default_choice(game))
    end
    game
  end

  # Answers each decision with the first option matching `prefer` (a block), else the default answer.
  def run(game, &prefer)
    80.times do
      break if game.pending_decision.kind == "priority" && game.state.stack.empty?

      game.submit((prefer && game.legal_options.find(&prefer)) || default_choice(game))
    end
    game
  end

  describe "dividing damage (CR 601.2d)" do
    it "Twin Bolt deals 2 damage divided between two targets, one each" do
      game = board(hand: ["Twin Bolt"], battlefield: %w[Mountain Mountain], theirs: ["Desolation Prowler"])
      bears = id(game, "Desolation Prowler")
      game.submit(type: "cast", object: id(game, "Twin Bolt", zone: :hand))
      expect(game.legal_options.filter_map { it[:count] }).to eq([1, 2]) # one or two targets, never none
      game.submit(type: "count", count: 2)
      game.submit(type: "target", target: bears)
      game.submit(type: "target", target: "player:bob")
      run(game)
      expect(bob(game).life).to eq(19)
      expect(game.state.object(bears).damage).to eq(1)
    end

    it "Twin Bolt with one target deals it all 2" do
      game = board(hand: ["Twin Bolt"], battlefield: %w[Mountain Mountain])
      game.submit(type: "cast", object: id(game, "Twin Bolt", zone: :hand))
      game.submit(type: "count", count: 1)
      game.submit(type: "target", target: "player:bob")
      run(game)
      expect(bob(game).life).to eq(18)
    end

    it "Gandalf's enters trigger divides 3 damage among three targets as it's put on the stack" do
      game = board(hand: ["Gandalf, Spark Starter"], battlefield: Array.new(6, "Mountain"),
                   theirs: ["Desolation Prowler", "Hungry Graffalon"])
      game.submit(type: "cast", object: id(game, "Gandalf, Spark Starter", zone: :hand))
      run_until(game, "choose_target_count")
      game.submit(type: "count", count: 3)
      bears = id(game, "Desolation Prowler")
      giant = id(game, "Hungry Graffalon")
      game.submit(type: "target", target: bears)
      game.submit(type: "target", target: giant)
      game.submit(type: "target", target: "player:bob")
      expect(game.state.object(game.state.stack.first).memory["division"]).to eq(bears => 1, giant => 1, "player:bob" => 1)
      run(game)
      expect(bob(game).life).to eq(19)
      expect([bears, giant].map { game.state.object(it).damage }).to eq([1, 1])
    end

    it "Ureni divides X damage, X the lands you control, among creatures and planeswalkers of opponents" do
      lands = %w[Forest Forest Forest Island Mountain Mountain Mountain Mountain]
      game = board(hand: ["Ureni, the Song Unending"], battlefield: lands, theirs: ["Desolation Prowler", "Hungry Graffalon"])
      game.submit(type: "cast", object: id(game, "Ureni, the Song Unending", zone: :hand))
      run_until(game, "choose_target_count")
      game.submit(type: "count", count: 2)
      bears = id(game, "Desolation Prowler")
      giant = id(game, "Hungry Graffalon")
      game.submit(type: "target", target: bears)
      game.submit(type: "target", target: giant)
      expect(game.pending_decision).to have_attributes(kind: "distribute", details: { "left" => 6 })
      game.submit(type: "assign", target: bears)
      5.times { game.submit(type: "assign", target: giant) }
      run(game)
      expect(game.state.battlefield).not_to include(bears, giant)
    end
  end

  describe "mana spent compared with the mana value (CR 601.2h, 202.3)" do
    let(:colors) { %w[Mountain Plains Swamp] }

    # Casts Defibrillating Current ({2/R}{2/W}{2/B}, mana value 6) for {R}{W}{B} at the opponent's creature.
    def cast_current(game)
      game.submit(type: "cast", object: id(game, "Defibrillating Current", zone: :hand))
      game.submit(type: "target", target: id(game, "Desolation Prowler"))
      run_until(game, "priority")
    end

    it "Tokka & Rahzar deal 3 damage to a player who spent less mana than the spell's mana value" do
      game = board(hand: ["Defibrillating Current"], battlefield: colors + ["Tokka & Rahzar, Terrible Twos"],
                   theirs: ["Desolation Prowler"])
      cast_current(game)
      expect(game.state.object(game.state.stack.last).mana_spent.size).to eq(3)
      run(game)
      expect(alice(game).life).to eq(20 - 3 + 2) # Tokka's 3, the Current's 2 life
    end

    it "Tokka & Rahzar ignore a spell paid in full" do
      game = board(hand: ["Proft, Sinister Mastermind"], battlefield: ["Swamp", "Swamp", "Swamp", "Tokka & Rahzar, Terrible Twos"],
                   graveyard: Array.new(7, "Island"))
      game.submit(type: "cast", object: id(game, "Proft, Sinister Mastermind", zone: :hand))
      run(game)
      expect(alice(game).life).to eq(20)
    end

    it "Unravel counters a spell and draws, reading the countered spell as it last existed (CR 608.2h)" do
      game = board(hand: ["Defibrillating Current", "Unravel"], battlefield: colors + %w[Island Island Island],
                   theirs: ["Desolation Prowler"])
      cast_current(game)
      game.submit(type: "cast", object: id(game, "Unravel", zone: :hand))
      game.submit(type: "target", target: game.state.stack.last)
      run(game)
      expect(alice(game).hand.size).to eq(1)
      expect(game.state.battlefield).to include(id(game, "Desolation Prowler"))
    end

    it "Unravel draws nothing when the full mana value was spent" do
      game = board(hand: ["Proft, Sinister Mastermind", "Unravel"], battlefield: %w[Swamp Swamp Swamp Island Island Island],
                   graveyard: Array.new(7, "Island"))
      game.submit(type: "cast", object: id(game, "Proft, Sinister Mastermind", zone: :hand))
      run_until(game, "priority")
      game.submit(type: "cast", object: id(game, "Unravel", zone: :hand))
      game.submit(type: "target", target: game.state.stack.last)
      run(game)
      expect(alice(game).hand).to be_empty
      expect(alice(game).graveyard.map { game.state.object(it).card }).to include("proft_sinister_mastermind")
    end
  end

  describe "exiling a spell cast this way instead of putting it into a graveyard (CR 614.1a)" do
    it "Quistis Trepe casts an opponent's instant with mana of any type; it's exiled as it resolves" do
      game = board(hand: ["Quistis Trepe"], battlefield: Array.new(5, "Island"), their_graveyard: ["Twin Bolt"])
      bolt = id(game, "Twin Bolt", zone: :graveyard, player: "bob")
      game.submit(type: "cast", object: id(game, "Quistis Trepe", zone: :hand))
      run_until(game, "choose_target")
      game.submit(type: "target", target: bolt)
      pass_both(game)
      expect(game.legal_options).to include({ type: "cast", object: bolt })
      game.submit(type: "cast", object: bolt)
      game.submit(type: "count", count: 1)
      game.submit(type: "target", target: "player:bob")
      run(game) # two Islands pay {1}{R} (CR 609.4b)
      expect(bob(game).life).to eq(18)
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["twin_bolt"])
      expect(bob(game).graveyard).to be_empty
    end

    it "The Dawning Archaic costs {1} less for each instant and sorcery card in your graveyard" do
      game = board(hand: ["The Dawning Archaic"], battlefield: Array.new(6, "Island"), graveyard: Array.new(4, "Twin Bolt"),
                   their_graveyard: ["Twin Bolt"])
      game.submit(type: "cast", object: id(game, "The Dawning Archaic", zone: :hand))
      expect(game.pending_decision).to have_attributes(kind: "pay_cost", details: { "remaining" => "{6}" })
    end
  end

  describe "mana spendable only on spells cast from anywhere other than your hand (CR 106.6, 601.2a)" do
    it "Mm'menon's artifacts tap for {U} that pays for an artifact cast from the library, not from the hand" do
      game = board(hand: ["Thrór's Map"], library_top: ["Thrór's Map"],
                   battlefield: ["Mm'menon, the Right Hand", "Well-Worn Spatula", "Kyoshi Battle Fan"])
      in_hand = id(game, "Thrór's Map", zone: :hand)
      on_top = alice(game).library.first
      expect(game.legal_options).not_to include(a_hash_including(type: "cast", object: in_hand))
      game.submit(type: "cast", object: on_top, via: game.legal_options.find { it[:object] == on_top }[:via])
      expect(game.legal_options.count { it[:type] == "activate_mana" }).to eq(2)
      run(game)
      expect(game.state.battlefield.count { game.state.object(it).card == "thrors_map" }).to eq(1)
    end
  end

  describe "which sources' mana was spent (CR 106.6, 601.2h)" do
    # Smaug with a Treasure beside it (created the way Smaug's trigger does).
    def smaug_board(lands)
      game = board(hand: ["Twin Bolt"], battlefield: ["Smaug, Wicked Worm"] + lands)
      engine(game).create_token!(catalog.fetch("Smaug, Wicked Worm").token_definitions.first, 0)
      Enjine::Game.import({ "state" => game.state.to_h }, catalog: catalog)
    end

    def treasure(game) = game.state.battlefield.find { game.state.object(it).card.include?("treasure") }

    def cast_bolt(game)
      game.submit(type: "cast", object: id(game, "Twin Bolt", zone: :hand))
      game.submit(type: "count", count: 1)
      game.submit(type: "target", target: "player:bob")
    end

    it "Smaug draws a card and loses 1 life when mana from a Treasure paid for the spell" do
      game = smaug_board(["Mountain"])
      cast_bolt(game)
      game.submit(type: "activate_mana", object: treasure(game), ability: "printed:3") # {R}, sacrificing it
      expect(alice(game).pool_sources).to contain_exactly(a_hash_including("mana" => "R",
                                                                           "from" => a_hash_including("subtypes" => ["treasure"])))
      run_until(game, "priority")
      spell = game.state.stack.find { game.state.object(it).card == "twin_bolt" }
      expect(game.state.object(spell).memory["mana_from"]).to contain_exactly(a_hash_including("subtypes" => ["treasure"]))
      run(game)
      expect(alice(game).hand.size).to eq(1)
      expect(alice(game).life).to eq(19)
    end

    it "Smaug ignores spells paid without Treasure mana" do
      game = smaug_board(%w[Mountain Mountain])
      cast_bolt(game)
      mountains = game.state.battlefield.select { game.state.object(it).card == "mountain" }
      mountains.each do |land|
        game.submit(type: "activate_mana", object: land, ability: "intrinsic:mountain")
        game.submit(type: "pay_mana", mana: "R")
      end
      run(game)
      expect(alice(game).hand).to be_empty
      expect(alice(game).life).to eq(20)
      expect(game.state.battlefield).to include(treasure(game))
    end
  end

  describe "restrictions on casting the spell itself (CR 601.3)" do
    it "Proft can't be cast until there are seven cards in your graveyard; its hand ability still works" do
      game = board(hand: ["Proft, Sinister Mastermind"], battlefield: %w[Swamp Swamp Swamp], graveyard: Array.new(6, "Island"),
                   theirs: ["Desolation Prowler"])
      expect(game.legal_options.none? { it[:type] == "cast" }).to be(true)
      expect(game.legal_options.map { it[:type] }).to include("activate")

      game = board(hand: ["Proft, Sinister Mastermind"], battlefield: %w[Swamp Swamp Swamp], graveyard: Array.new(7, "Island"))
      game.submit(type: "cast", object: id(game, "Proft, Sinister Mastermind", zone: :hand))
      run(game)
      expect(game.state.battlefield.map { game.state.object(it).card }).to include("proft_sinister_mastermind")
    end
  end
end
