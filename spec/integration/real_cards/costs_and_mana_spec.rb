# frozen_string_literal: true

# Real cards that needed costs and mana primitives: pay life (Desolation Prowler, Vicious Rivalry), behold
# (Champion of the Weird), monocolored hybrid (Defibrillating Current), improvise (Arc Reactor), mana of the
# chosen color (Uncharted Haven) and "activate only once" (Mild-Mannered Librarian).
RSpec.describe "Real cards: costs and mana" do
  let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.real_cards) }

  def board(hand: [], battlefield: [], theirs: [], life: 20)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", life: life) do
        hand(*hand)
        library "Island", count: 10
        battlefield.each { battlefield it }
      end
      player("bob") do
        library "Swamp", count: 10
        theirs.each { battlefield it }
      end
    end
  end

  def id(game, name, zone: :battlefield) = obj_id(game, name, zone: zone, player: "alice")
  def alice(game) = game.state.players[0]

  # Answers each decision with the first option matching `prefer` (a block), else pays mana, else passes.
  def run(game, &prefer)
    80.times do
      break if game.pending_decision.kind == "priority" && game.state.stack.empty?

      options = game.legal_options
      choice = (prefer && options.find(&prefer)) || options.find { it[:type] == "pay_mana" } ||
               options.find { it[:type] == "activate_mana" } || options.find { it[:type] == "pass" } || options.first
      game.submit(choice)
    end
    game
  end

  it "Desolation Prowler pays 2 life for +2/+2, once each turn (CR 119.4, 602.5b)" do
    game = board(battlefield: ["Desolation Prowler"])
    game.submit(game.legal_options.find { it[:type] == "activate" })
    run(game)
    expect(alice(game).life).to eq(18)
    expect(game.instance_variable_get(:@engine).power(game.state.object(id(game, "Desolation Prowler")))).to eq(4)
    expect(game.legal_options.none? { it[:type] == "activate" }).to be(true)
  end

  it "Vicious Rivalry pays X life and destroys artifacts and creatures with mana value X or less" do
    game = board(hand: ["Vicious Rivalry"], battlefield: %w[Swamp Swamp Forest Forest],
                 theirs: ["Desolation Prowler", "Champion of the Weird"])
    game.submit(type: "cast", object: id(game, "Vicious Rivalry", zone: :hand))
    game.submit(type: "x", value: 2)
    run(game)
    expect(alice(game).life).to eq(18)
    names = game.state.battlefield.map { game.state.object(it).card }
    expect(names).to include("champion_of_the_weird")
    expect(names).not_to include("desolation_prowler")
  end

  it "Champion of the Weird beholds a Goblin, exiles it and returns it when it leaves (CR 701.4, 607.2a)" do
    game = board(hand: ["Champion of the Weird", "Goblin Glasswright // Craft with Pride"], battlefield: %w[Swamp] * 4)
    goblin = id(game, "Goblin Glasswright // Craft with Pride", zone: :hand)
    game.submit(type: "cast", object: id(game, "Champion of the Weird", zone: :hand))
    game.submit(type: "cost", object: goblin)
    run(game)
    expect(game.state.exile.map { game.state.object(it).card }).to eq(["goblin_glasswright"])
    game.instance_variable_get(:@engine).move!(id(game, "Champion of the Weird"), :graveyard, reason: "destroy")
    game.submit(type: "pass") # the leaves-the-battlefield trigger goes on the stack as Bob gets priority
    run(game)
    expect(alice(game).hand.map { game.state.object(it).card }).to include("goblin_glasswright")
  end

  it "Defibrillating Current is paid with one mana of each color or two of any type per symbol (CR 107.4e)" do
    game = board(hand: ["Defibrillating Current"], battlefield: %w[Mountain Plains Island Island], theirs: ["Desolation Prowler"])
    expect(game.legal_options.map { it[:type] }).to include("cast")
    game.submit(type: "cast", object: id(game, "Defibrillating Current", zone: :hand))
    game.submit(type: "target", target: obj_id(game, "Desolation Prowler"))
    run(game)
    expect(game.state.battlefield.map { game.state.object(it).card }).not_to include("desolation_prowler")
    expect(alice(game).life).to eq(22)
    expect(game.state.players[0].graveyard.map { game.state.object(it).card }).to eq(["defibrillating_current"])
  end

  it "Arc Reactor is cast with improvise: artifacts pay generic mana (CR 702.126)" do
    game = board(hand: ["Arc Reactor"], battlefield: ["Island", "Island", "Bat'leth", "Bat'leth", "Bat'leth"])
    game.submit(type: "cast", object: id(game, "Arc Reactor", zone: :hand))
    run(game) { it[:type] == "improvise" }
    reactor = id(game, "Arc Reactor")
    expect(game.state.object(reactor).tapped).to be(true)
    expect(game.state.battlefield.count { game.state.object(it).tapped }).to eq(6)
  end

  it "Uncharted Haven adds one mana of the color chosen as it entered (CR 607.2d)" do
    game = board(hand: ["Uncharted Haven"])
    game.submit(type: "play_land", object: id(game, "Uncharted Haven", zone: :hand))
    game.submit(game.legal_options.find { it[:color] == "G" })
    haven = game.state.object(id(game, "Uncharted Haven"))
    expect([haven.tapped, haven.memory["chosen_color"]]).to eq([true, "G"])
    haven.tapped = false
    game.submit(game.legal_options.find { it[:type] == "activate_mana" })
    expect(alice(game).mana_pool[:G]).to eq(1)
  end

  it "Mild-Mannered Librarian becomes a Werewolf once (CR 602.5b)" do
    game = board(battlefield: ["Mild-Mannered Librarian", "Forest", "Forest", "Forest", "Forest", "Forest", "Forest", "Forest", "Forest"])
    librarian = id(game, "Mild-Mannered Librarian")
    game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == librarian })
    run(game)
    engine = game.instance_variable_get(:@engine)
    expect(engine.chars(game.state.object(librarian)).subtypes).to eq([:werewolf])
    expect(game.state.object(librarian).counters).to eq("+1/+1" => 2)
    expect(game.legal_options.none? { it[:type] == "activate" && it[:object] == librarian }).to be(true)
  end
end
