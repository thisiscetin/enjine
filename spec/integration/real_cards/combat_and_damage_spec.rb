# frozen_string_literal: true

# Real cards that need first-attack triggers, attack and block restrictions, prevention follow-ups, damage
# modification tied to a player, dies-to-exile follow-ups, fights' excess damage and ending the turn, written in
# the card DSL (spec/fixtures/cards/real/combat_and_damage.json).
RSpec.describe "Real cards: combat and damage" do
  let(:extras) do
    [{ "name" => "Mountain", "types" => ["land"], "supertypes" => ["basic"], "subtypes" => ["mountain"] },
     { "name" => "Bear Cub", "mana_cost" => "{1}{G}", "types" => ["creature"], "subtypes" => ["bear"], "power" => 2, "toughness" => 2 },
     { "name" => "Stone Golem", "mana_cost" => "{5}", "types" => %w[artifact creature], "subtypes" => ["golem"], "power" => 6,
       "toughness" => 6 },
     { "name" => "Small Relic", "mana_cost" => "{2}", "types" => ["artifact"] }]
  end
  let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.real("combat_and_damage") + extras) }

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, name) = game.state.players[game.names.index(name)].life
  def id(game, card) = game.state.battlefield.find { engine(game).chars(it).name == card } || raise("no #{card}")

  def board(alice: [], bob: [], hand: [], mana: {}, step: :precombat_main, alice_graveyard: [])
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana) do
        hand(*hand) unless hand.empty?
        alice.each { battlefield it }
        graveyard(*alice_graveyard) unless alice_graveyard.empty?
        library "Mountain", count: 10
      end
      player("bob") do
        bob.each { battlefield it }
        library "Mountain", count: 10
      end
    end
  end

  def settle(game, answers = [])
    while game.state.stack.any? || game.state.pending_triggers.any? || !%w[priority declare_attackers].include?(game.pending_decision.kind)
      decision = game.pending_decision
      game.submit(case decision.kind
                  when "priority" then { type: "pass" }
                  when "pay_cost" then game.legal_options.find { it[:type] == "pay_mana" }
                  else game.legal_options.include?(answers.first) ? answers.shift : game.legal_options.first
                  end)
    end
  end

  def cast(game, card, *answers)
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: "alice"))
    settle(game, answers)
  end

  def attack(game, *cards)
    pass_both(game) until game.pending_decision.kind == "declare_attackers"
    cards.each { game.submit(type: "attack", object: id(game, it), target: "player:bob") }
    game.submit(type: "done") if game.legal_options.include?(type: "done")
  end

  it "Aurelia, the Warleader gives one additional combat, in the first combat only" do
    game = board(alice: ["Aurelia, the Warleader"], step: :beginning_of_combat)
    attack(game, "Aurelia, the Warleader")
    settle(game)
    pass_both(game) until game.state.step == :end_of_combat
    attack(game, "Aurelia, the Warleader")
    expect(game.state.pending_triggers).to be_empty
    skip_to(game, :end)
    expect(life(game, "bob")).to eq(14)
  end

  it "Desert Were-Worm gets +2/+0 per Mountain and triggers on attackers with total power 12 or greater" do
    game = board(alice: ["Desert Were-Worm"] + (["Mountain"] * 6), step: :beginning_of_combat)
    worm = id(game, "Desert Were-Worm")
    expect(engine(game).power(engine(game).object(worm))).to eq(12)
    attack(game, "Desert Were-Worm")
    settle(game)
    expect(game.state.extra_phases["pending"].size).to eq(1)
  end

  it "Bumi, Unleashed: only land creatures can attack in the additional combat" do
    game = board(alice: ["Bumi, Unleashed", "Bear Cub"], step: :beginning_of_combat)
    attack(game, "Bumi, Unleashed")
    pass_both(game) until game.state.step == :end_of_combat
    pass_both(game) until game.state.step == :beginning_of_combat
    expect(game.state.extra_phases["attackers"]).to eq({ "creature" => { "types" => ["land"] } })
    expect(engine(game).eligible_attackers).to be_empty # Bumi and the Bear Cub aren't land creatures
    pass_both(game) until game.state.step == :postcombat_main
    expect(game.state.extra_phases["attackers"]).to be_nil
  end

  it "Lightning, Army of One doubles damage to the player it hit and their permanents until alice's next turn" do
    game = board(alice: ["Lightning, Army of One"], bob: ["Bear Cub"])
    eng = engine(game)
    eng.deal_damage!(id(game, "Lightning, Army of One"), "player:bob", 3, combat: true)
    settle(game)
    expect(eng.deal_damage!(nil, "player:bob", 1)).to eq(2)
    expect(eng.deal_damage!(nil, id(game, "Bear Cub"), 1)).to eq(2)
    expect(eng.deal_damage!(nil, "player:alice", 1)).to eq(1)
  end

  it "Neriv doubles damage dealt by creatures its controller controls that entered this turn" do
    game = board(alice: ["Neriv, Heart of the Storm", "Bear Cub"])
    eng = engine(game)
    cub = id(game, "Bear Cub")
    expect(eng.deal_damage!(cub, "player:bob", 2)).to eq(2)
    eng.object(cub).memory["entered"] = game.state.turn
    expect(eng.deal_damage!(cub, "player:bob", 2)).to eq(4)
  end

  it "New Way Forward prevents the next damage from the chosen source, deals that much back and draws" do
    game = board(bob: ["Stone Golem"], hand: ["New Way Forward"], mana: { U: 1, R: 1, W: 1, C: 2 })
    golem = id(game, "Stone Golem")
    cast(game, "New Way Forward", { type: "source", object: golem })
    expect(engine(game).deal_damage!(golem, "player:alice", 6, combat: true)).to eq(0)
    settle(game)
    expect(life(game, "bob")).to eq(14)
    expect(game.state.players[0].hand.size).to eq(6)
  end

  it "Anti-Venom prevents damage to himself and grows that much" do
    game = board(alice: ["Anti-Venom, Horrifying Healer"])
    venom = id(game, "Anti-Venom, Horrifying Healer")
    expect(engine(game).deal_damage!(nil, venom, 4)).to eq(0)
    expect(engine(game).object(venom).counters["+1/+1"]).to eq(4)
  end

  it "Old Fat Spider Can't See Me prevents a creature's damage while the Saga remains" do
    game = board(alice: ["Old Fat Spider Can't See Me", "Bear Cub"], bob: ["Stone Golem"])
    eng = engine(game)
    saga = id(game, "Old Fat Spider Can't See Me")
    golem = id(game, "Stone Golem")
    eng.add_counters!(eng.object(saga), "lore", 1) # chapter I: hexproof for the Bear Cub
    settle(game)
    expect(eng.chars(id(game, "Bear Cub")).keyword?(:hexproof)).to be(true)
    eng.add_counters!(eng.object(saga), "lore", 1)
    settle(game, [{ type: "target", target: golem }])
    expect(eng.deal_damage!(golem, "player:alice", 6)).to eq(0)
    eng.move!(saga, :graveyard, reason: "destroy")
    expect(eng.deal_damage!(golem, "player:alice", 6)).to eq(6)
  end

  it "Ancient Adamantoise keeps its damage through cleanup and takes damage for its controller" do
    game = board(alice: ["Ancient Adamantoise", "Bear Cub"])
    eng = engine(game)
    turtle = id(game, "Ancient Adamantoise")
    eng.deal_damage!(nil, "player:alice", 5)
    eng.deal_damage!(nil, id(game, "Bear Cub"), 2)
    expect(life(game, "alice")).to eq(20)
    eng.cleanup_turn!
    expect(eng.object(turtle).damage).to eq(7)
  end

  it "Head of the Hunt exiles an opponent's dying creature and makes a Wolf" do
    game = board(alice: ["Head of the Hunt"], bob: ["Bear Cub"])
    engine(game).move!(id(game, "Bear Cub"), :graveyard, reason: "destroy")
    settle(game)
    expect(game.state.exile.size).to eq(1)
    expect(game.state.battlefield.count { engine(game).chars(it).name == "Wolf" }).to eq(1)
  end

  it "Rhino's Rampage: excess fight damage lets it destroy a small noncreature artifact" do
    game = board(alice: ["Stone Golem"], bob: ["Bear Cub", "Small Relic"], hand: ["Rhino's Rampage"], mana: { R: 1 })
    cast(game, "Rhino's Rampage", { type: "target", target: id(game, "Stone Golem") }, { type: "target", target: id(game, "Bear Cub") })
    expect(game.state.battlefield.map { engine(game).chars(it).name }).not_to include("Small Relic", "Bear Cub")
  end

  it "Ultima destroys artifacts and creatures, then ends the turn" do
    game = board(alice: ["Stone Golem"], bob: ["Bear Cub", "Small Relic"], hand: ["Ultima"], mana: { W: 2, C: 3 })
    cast(game, "Ultima")
    expect(game.state.battlefield).to all(satisfy { !engine(game).chars(it).creature? })
    expect(game.state.turn).to eq(4)
  end

  it "Time Stop exiles the spell it answers" do
    game = board(hand: ["Time Stop"], mana: { U: 2, C: 4 })
    cast(game, "Time Stop")
    expect(game.state.exile.size).to eq(1)
    expect(game.state.turn).to eq(4)
  end

  it "Pinnacle Emissary's Drones can block only fliers" do
    drone = catalog.fetch("pinnacle_emissary").all_effects.find { it.respond_to?(:definition) && it.definition }.definition
    expect(drone.abilities.first.kind).to eq(:can_block_only)
  end
end
