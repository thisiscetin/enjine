# frozen_string_literal: true

# Ninjutsu (CR 702.49): an activated ability from the hand, not a cast. Invented test cards only.
RSpec.describe "Ninjutsu (CR 702.49)" do
  let(:ninja) do
    { "name" => "Spec Shadow Ninja", "mana_cost" => "{3}{B}", "types" => ["creature"], "subtypes" => ["ninja"],
      "power" => 3, "toughness" => 2, "abilities" => [{ "ninjutsu" => { "cost" => "{B}" } }] }
  end
  # Kaito-shaped: a planeswalker that is a creature only during your turn while it has loyalty counters.
  let(:walker) do
    { "name" => "Spec Night Walker", "mana_cost" => "{2}{B}", "types" => ["planeswalker"], "loyalty" => 3,
      "subtypes" => ["kaito"],
      "abilities" => [{ "ninjutsu" => { "cost" => "{B}" } },
                      { "static" => { "if" => { "all" => [{ "your_turn" => true },
                                                          { "amount" => { "counters" => { "of" => "self", "kind" => "loyalty" } },
                                                            "at_least" => 1 }] },
                                      "affects" => "self", "types" => ["creature"],
                                      "base_power_toughness" => { "power" => 3, "toughness" => 4 } } },
                      { "loyalty" => { "cost" => 1, "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
  end
  let(:caster_watch) do
    { "name" => "Spec Cast Watcher", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "triggered" => { "when" => { "cast" => {} }, "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
  end
  let(:catalog) { catalog_with(ninja, walker, caster_watch) }

  def id(game, card, zone: :battlefield, player: "alice") = obj_id(game, card, zone: zone, player: player)
  def life(game, name) = game.view_for(:observer)["players"].find { it["name"] == name }["life"]
  def engine(game) = game.instance_variable_get(:@engine)

  def board(hand:, bob_field: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand(*hand)
        battlefield "Raging Goblin", "Swamp", "Swamp", "Spec Cast Watcher"
        library "Forest", count: 10
      end
      player("bob") do
        bob_field.each { battlefield it }
        library "Swamp", count: 10
      end
    end
  end

  def ninjutsu_option(game, card)
    hand_id = id(game, card, zone: :hand)
    game.legal_options.find { it[:type] == "activate" && it[:object] == hand_id }
  end

  def to_declare_attackers(game)
    pass_both(game) # -> beginning of combat
    pass_both(game) # -> declare attackers
    game.submit(type: "attack", object: id(game, "Raging Goblin"), target: "player:bob")
    game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
  end

  def pay_all(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  it "returns an unblocked attacker and puts the card onto the battlefield tapped and attacking, not cast (CR 702.49a, 702.49c)" do
    game = board(hand: ["Spec Shadow Ninja"])
    expect(ninjutsu_option(game, "Spec Shadow Ninja")).to be_nil # no unblocked attacker in the main phase
    to_declare_attackers(game)
    expect(game.state.step).to eq(:declare_attackers)
    expect(ninjutsu_option(game, "Spec Shadow Ninja")).to be_nil # CR 509.1h: not unblocked before blockers are declared
    pass_both(game) # bob declares no blockers
    expect(game.state.step).to eq(:declare_blockers)
    goblin = id(game, "Raging Goblin")
    events = []
    game.subscribe { events << it.type }
    game.submit(ninjutsu_option(game, "Spec Shadow Ninja"))
    expect(game.legal_options).to include(type: "cost", object: goblin)
    game.submit(type: "cost", object: goblin)
    pay_all(game)
    expect(events).to include("card_revealed") # CR 702.49b
    expect(events).not_to include("spell_cast")
    expect(ids_in(game, "alice", :hand).map { game.state.object(it).card }).to include("raging_goblin")
    expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Spec Shadow Ninja ability"])
    pass_both(game)
    ninja = id(game, "Spec Shadow Ninja")
    expect(game.state.object(ninja).tapped).to be(true)
    expect(game.state.attackers[ninja]).to eq("target" => "player:bob", "blocked" => false)
    expect(life(game, "alice")).to eq(20) # it wasn't cast: no cast trigger
    pass_both(game) # combat damage
    expect(life(game, "bob")).to eq(17)
  end

  it "a blocked attacker can't be returned" do
    game = board(hand: ["Spec Shadow Ninja"], bob_field: ["Grizzly Bears"])
    to_declare_attackers(game)
    pass_both(game)
    game.submit(type: "block", object: id(game, "Grizzly Bears", player: "bob"), attacker: id(game, "Raging Goblin"))
    game.submit(type: "done") if game.pending_decision.kind == "declare_blockers"
    pass_both(game) until game.state.step == :declare_blockers && game.pending_decision.kind == "priority"
    expect(ninjutsu_option(game, "Spec Shadow Ninja")).to be_nil
  end

  it "a planeswalker that is a creature on your turn enters attacking (Kaito-shaped, CR 702.49c)" do
    game = board(hand: ["Spec Night Walker"])
    to_declare_attackers(game)
    pass_both(game)
    game.submit(ninjutsu_option(game, "Spec Night Walker"))
    game.submit(type: "cost", object: id(game, "Raging Goblin"))
    pay_all(game)
    pass_both(game)
    walker = id(game, "Spec Night Walker")
    expect(engine(game).chars(game.state.object(walker)).creature?).to be(true)
    expect(game.state.attackers[walker]).to include("target" => "player:bob")
    pass_both(game)
    expect(life(game, "bob")).to eq(17)
  end

  it "does nothing if the card left the hand before the ability resolves" do
    game = board(hand: ["Spec Shadow Ninja"])
    to_declare_attackers(game)
    pass_both(game)
    game.submit(ninjutsu_option(game, "Spec Shadow Ninja"))
    game.submit(type: "cost", object: id(game, "Raging Goblin"))
    pay_all(game)
    engine(game).move!(id(game, "Spec Shadow Ninja", zone: :hand), :graveyard, reason: "test")
    pass_both(game)
    expect(game.state.battlefield.map { game.state.object(it).card }).not_to include("spec_shadow_ninja")
  end
end
