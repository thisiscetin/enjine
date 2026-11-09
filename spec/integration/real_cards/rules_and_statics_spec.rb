# frozen_string_literal: true

# Real cards that change the rules or other objects' abilities (spec/fixtures/cards/real/rules_and_statics.json),
# written by hand in the card DSL. Creatures from creatures_combat_keywords.json stand in as targets.
RSpec.describe "Real cards: losing abilities, restrictions and other rules effects" do
  let(:cards) { (CardFixtures.real("rules_and_statics") + CardFixtures.real("creatures_combat_keywords")).uniq { it["name"] } }
  let(:catalog) { Enjine::Catalog.from_definitions(cards) }

  def board(hand: [], mine: [], theirs: [], mana: {}, their_mana: {})
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: mana) do
        hand(*hand)
        mine.each { |card, opts| battlefield card, **(opts || {}) }
        library "Island", count: 10
      end
      player("bob", mana_pool: their_mana) do
        theirs.each { |card, opts| battlefield card, **(opts || {}) }
        library "Island", count: 10
      end
    end
  end

  # Submits `action`, answers further decisions with `answers` in order, pays from the pool and passes until
  # the stack is empty.
  def play(game, action, *answers)
    game.submit(action)
    until game.over? || ((decision = game.pending_decision).kind == "priority" && game.state.stack.empty?)
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { it[:type] == "pay_mana" } || raise("can't pay"))
      else game.submit(answers.shift || raise("no answer for #{decision.kind}: #{game.legal_options}"))
      end
    end
    expect(answers).to be_empty
    game
  end

  def cast(game, card, *) = play(game, { type: "cast", object: obj_id(game, card, zone: :hand, player: "alice") }, *)
  def target(game, card) = { type: "target", target: obj_id(game, card) }
  def chars(game, id) = game.instance_variable_get(:@engine).chars(id)
  def life(game, player) = game.state.players[game.names.index(player)].life

  it "every card validates and keeps its rarity and printing" do
    CardFixtures.real("rules_and_statics").each { expect(Enjine::CardDefinition.from_h(it).to_h).to include("printing", "rarity") }
  end

  it "Fresh Start: enchanted creature gets -5/-0 and loses all abilities (CR 613.1f, 613.4c)" do
    game = board(hand: ["Fresh Start"], theirs: ["Vampire Nighthawk"], mana: { U: 2 })
    hawk = obj_id(game, "Vampire Nighthawk")
    cast(game, "Fresh Start", target(game, "Vampire Nighthawk"))
    expect([chars(game, hawk).keywords, chars(game, hawk).power, chars(game, hawk).toughness]).to eq([[], -3, 3])
  end

  it "Noggle the Mind: a colorless Noggle with base power and toughness 1/1 and no abilities (CR 613.1d-f, 613.4b)" do
    game = board(hand: ["Noggle the Mind"], theirs: ["Vampire Nighthawk"], mana: { U: 2 })
    hawk = obj_id(game, "Vampire Nighthawk")
    cast(game, "Noggle the Mind", target(game, "Vampire Nighthawk"))
    c = chars(game, hawk)
    expect([c.colors, c.subtypes, c.keywords, c.power, c.toughness]).to eq([[], [:noggle], [], 1, 1])
  end

  it "Day of Black Sun: creatures with mana value X or less lose their abilities, then are destroyed (CR 603.10a)" do
    game = board(hand: ["Day of Black Sun"], theirs: ["Adorned Crocodile", "Vampire Nighthawk"], mana: { B: 7 })
    cast(game, "Day of Black Sun", { type: "x", value: 5 })
    expect(game.state.battlefield).to be_empty # no Zombie Druid token: its dies ability was lost
    expect(game.state.pending_triggers).to be_empty
  end

  it "Giant Cindermaw: players can't gain life, not even from lifelink (CR 119.7)" do
    game = board(mine: ["Giant Cindermaw"], theirs: ["Vampire Nighthawk"])
    engine = game.instance_variable_get(:@engine)
    engine.deal_damage!(obj_id(game, "Vampire Nighthawk"), "player:alice", 2)
    expect([life(game, "alice"), life(game, "bob")]).to eq([18, 20])
  end

  it "Voice of Victory: opponents can't cast spells during your turn (CR 101.2, 604.2)" do
    game = board(mine: ["Voice of Victory"], their_mana: { R: 1 })
    game.state.players[1].hand << game.instance_variable_get(:@engine).create_object("burst_lightning", 1, :hand).id
    game.submit(type: "pass")
    expect(game.pending_decision.player).to eq("bob")
    expect(game.legal_options.map { it[:type] }).not_to include("cast")
  end

  it "Frenzied Baloth: creature spells you control can't be countered (CR 101.2)" do
    game = board(hand: ["Vampire Nighthawk"], mine: ["Frenzied Baloth"], mana: { B: 3 }, their_mana: { U: 2 })
    game.state.players[1].hand << game.instance_variable_get(:@engine).create_object("essence_scatter", 1, :hand).id
    game.submit(type: "cast", object: obj_id(game, "Vampire Nighthawk", zone: :hand, player: "alice"))
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
    game.submit(type: "pass")
    play(game, { type: "cast", object: ids_in(game, "bob", :hand).first }, { type: "target", target: game.state.stack.first })
    expect(game.state.battlefield.map { game.state.object(it).card }).to include("vampire_nighthawk")
  end

  it "Impractical Joke: damage can't be prevented this turn, so a shield counter doesn't save it (CR 615.12)" do
    game = board(hand: ["Impractical Joke"], theirs: [["Vampire Nighthawk", { counters: { "shield" => 1 } }]], mana: { R: 1 })
    hawk = obj_id(game, "Vampire Nighthawk")
    cast(game, "Impractical Joke", target(game, "Vampire Nighthawk"))
    expect(game.state.battlefield).not_to include(hawk)
  end

  it "The Wondrous Wasp: the target loses all abilities only while the Wasp remains (CR 611.2b)" do
    game = board(hand: ["The Wondrous Wasp"], theirs: ["Vampire Nighthawk"], mana: { U: 2 })
    hawk = obj_id(game, "Vampire Nighthawk")
    cast(game, "The Wondrous Wasp", target(game, "Vampire Nighthawk"))
    expect(game.state.object(hawk).tapped).to be(true)
    expect(chars(game, hawk).keywords).to be_empty
    engine = game.instance_variable_get(:@engine)
    engine.move!(obj_id(game, "The Wondrous Wasp"), :graveyard, reason: "test")
    expect(chars(game, hawk).keywords).to contain_exactly(:flying, :deathtouch, :lifelink)
  end
end
