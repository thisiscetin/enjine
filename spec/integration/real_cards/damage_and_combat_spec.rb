# frozen_string_literal: true

# Real cards that need damage replacement, prevention, excess damage and block triggers (fdn, fra), written in
# the card DSL (spec/fixtures/cards/real/creatures_combat_keywords.json and newest_sets.json).
RSpec.describe "Real cards: damage and combat" do
  let(:catalog) { Enjine::Catalog.from_definitions((CardFixtures.real("creatures_combat_keywords") + CardFixtures.real("newest_sets")).uniq { it["name"] }) }

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, name) = game.state.players[game.names.index(name)].life
  def id(game, card) = game.state.battlefield.find { engine(game).chars(it).name == card } || raise("no #{card}")

  def board(alice: [], bob: [], hand: [], mana: {}, step: :precombat_main)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana) do
        hand(*hand) unless hand.empty?
        alice.each { battlefield it }
        library "Forest", count: 10
      end
      player("bob") do
        bob.each { battlefield it }
        library "Forest", count: 10
      end
    end
  end

  # Casts a card from alice's hand with the given answers (targets, X), paying from her mana pool, and resolves it.
  def cast(game, card, *answers)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).find { engine(game).chars(it).name == card })
    until game.pending_decision.kind == "priority" && game.state.stack.empty? && game.state.pending_triggers.empty?
      decision = game.pending_decision
      game.submit(case decision.kind
                  when "priority" then { type: "pass" }
                  when "pay_cost" then game.legal_options.find { it[:type] == "pay_mana" }
                  else answers.shift || game.legal_options.first
                  end)
    end
  end

  it "Twinflame Tyrant doubles damage its controller's sources deal to an opponent and their permanents" do
    game = board(alice: ["Twinflame Tyrant"], bob: ["Crystal Barricade"])
    tyrant = id(game, "Twinflame Tyrant")
    expect(engine(game).deal_damage!(tyrant, "player:bob", 3, combat: true)).to eq(6)
    expect(engine(game).deal_damage!(tyrant, id(game, "Crystal Barricade"), 1)).to eq(2)
    expect(life(game, "bob")).to eq(14)
  end

  it "Fleeting Flight: +1/+1 counter, flying, and combat damage to it is prevented this turn" do
    game = board(alice: ["Tomik, Izzet Sparkmage"], hand: ["Fleeting Flight"], mana: { W: 1 })
    tomik = id(game, "Tomik, Izzet Sparkmage")
    cast(game, "Fleeting Flight", { type: "target", target: tomik })
    expect(engine(game).chars(tomik).keyword?(:flying)).to be(true)
    expect(engine(game).deal_damage!(nil, tomik, 5, combat: true)).to eq(0)
    expect(engine(game).deal_damage!(nil, tomik, 1)).to eq(1)
  end

  it "Goblin Negotiation makes a Goblin for each excess damage" do
    game = board(bob: ["Crystal Barricade"], hand: ["Goblin Negotiation"], mana: { R: 8 })
    cast(game, "Goblin Negotiation", { type: "x", value: 6 }, { type: "target", target: id(game, "Crystal Barricade") })
    goblins = game.state.battlefield.count { engine(game).chars(it).name == "Goblin" }
    expect(goblins).to eq(2) # 6 damage to a 0/4
  end

  it "Crystal Barricade prevents noncombat damage to other creatures its controller controls" do
    game = board(alice: ["Crystal Barricade", "Twinflame Tyrant"])
    tyrant = id(game, "Twinflame Tyrant")
    expect(engine(game).deal_damage!(nil, tyrant, 3)).to eq(0)
    expect(engine(game).deal_damage!(nil, tyrant, 3, combat: true)).to eq(3)
  end

  it "Tomik adds 1 to noncombat damage its controller's sources deal to an opponent" do
    game = board(alice: ["Tomik, Izzet Sparkmage"])
    tomik = id(game, "Tomik, Izzet Sparkmage")
    expect(engine(game).deal_damage!(tomik, "player:bob", 2)).to eq(3)
    expect(engine(game).deal_damage!(tomik, "player:bob", 2, combat: true)).to eq(2)
  end

  it "Tetsuko Umezawa punishes a small blocker's controller" do
    game = board(alice: ["Tetsuko Umezawa, Pursuer"], bob: ["Crystal Barricade", "Twinflame Tyrant"], step: :beginning_of_combat)
    tetsuko = id(game, "Tetsuko Umezawa, Pursuer")
    pass_both(game)
    game.submit(type: "attack", object: tetsuko, target: "player:bob")
    pass_both(game)
    game.submit(type: "block", object: id(game, "Crystal Barricade"), attacker: tetsuko) # a 0/4: power 1 or less
    game.submit(type: "done") if game.legal_options.include?(type: "done")
    pass_both(game) until game.state.stack.empty? && game.state.pending_triggers.empty?
    expect(life(game, "bob")).to eq(19)
  end

  it "Tetsuko Umezawa ignores a big blocker" do
    game = board(alice: ["Tetsuko Umezawa, Pursuer"], bob: ["Twinflame Tyrant"], step: :beginning_of_combat)
    tetsuko = id(game, "Tetsuko Umezawa, Pursuer")
    pass_both(game)
    game.submit(type: "attack", object: tetsuko, target: "player:bob")
    pass_both(game)
    game.submit(type: "block", object: id(game, "Twinflame Tyrant"), attacker: tetsuko)
    expect(game.state.pending_triggers + game.state.stack).to be_empty
  end
end
