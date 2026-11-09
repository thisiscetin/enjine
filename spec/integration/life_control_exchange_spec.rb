# frozen_string_literal: true

RSpec.describe "Setting and exchanging life totals and control, player counters (CR 119.5, 701.12, 122.1)" do
  def board(alice: [], alice_hand: [], bob: [], mana: {}, alice_life: 20, bob_life: 20, step: :precombat_main)
    build_game do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana, life: alice_life) do
        hand(*alice_hand)
        alice.each { battlefield it }
        library "Forest", count: 10
      end
      player("bob", life: bob_life) do
        bob.each { battlefield it }
        library "Forest", count: 10
      end
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, who) = game.state.players[game.names.index(who)].life

  def cast(game, card, *targets)
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: "alice"))
    targets.each { game.submit(type: "target", target: it) }
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
    game.submit(type: "pass") until game.state.stack.empty? || game.over?
  end

  it "'your life total becomes 10': the player gains or loses the difference (CR 119.5)" do
    [[20, 10], [4, 10]].each do |start, finish|
      game = board(alice: ["Hourglass of Balance"], alice_life: start, step: :postcombat_main)
      game.submit(type: "pass") until game.step == :end && game.state.stack.empty? && game.state.pending_triggers.empty?
      expect(life(game, "alice")).to eq(finish)
    end
  end

  it "exchanges life totals; 'if you lost life this way, draw that many cards' (CR 701.12c)" do
    game = board(alice_hand: ["Fortune Inversion"], mana: { W: 2, B: 2 }, alice_life: 12, bob_life: 9)
    cast(game, "Fortune Inversion", "player:bob")
    expect([life(game, "alice"), life(game, "bob")]).to eq([9, 12])
    expect(ids_in(game, "alice", :hand).size).to eq(3)
    game = board(alice_hand: ["Fortune Inversion"], mana: { W: 2, B: 2 }, alice_life: 5, bob_life: 15)
    cast(game, "Fortune Inversion", "player:bob")
    expect([life(game, "alice"), life(game, "bob")]).to eq([15, 5])
    expect(ids_in(game, "alice", :hand)).to be_empty
  end

  it "no part of the exchange happens if a player can't gain life (CR 701.12a, 119.7)" do
    game = board(alice_hand: ["Fortune Inversion"], alice: ["Cindermaw Brute"], mana: { W: 2, B: 2 }, alice_life: 5,
                 bob_life: 15)
    cast(game, "Fortune Inversion", "player:bob")
    expect([life(game, "alice"), life(game, "bob")]).to eq([5, 15])
  end

  it "exchanges control of two permanents controlled by different players (CR 701.12b)" do
    game = board(alice_hand: ["Swap Gambit"], alice: ["Grizzly Bears"], bob: ["Prodigal Pyromancer"], mana: { U: 4 })
    bears = obj_id(game, "Grizzly Bears")
    pyro = obj_id(game, "Prodigal Pyromancer")
    cast(game, "Swap Gambit", bears, pyro)
    expect([game.state.object(bears).controller, game.state.object(pyro).controller]).to eq([1, 0])
    expect(game.state.object(pyro).controlled_since).to eq(3) # summoning sick for its new controller (CR 302.6)
  end

  it "control for as long as the source remains on the battlefield, handed back as it leaves (CR 611.2b)" do
    game = board(alice_hand: ["Mindbinder Siren", "Lightning Bolt"], bob: ["Grizzly Bears"], mana: { U: 5, R: 1 })
    bears = obj_id(game, "Grizzly Bears")
    game.submit(type: "cast", object: obj_id(game, "Mindbinder Siren", zone: :hand, player: "alice"))
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
    game.submit(type: "pass") until game.pending_decision.kind == "choose_target"
    game.submit(type: "target", target: bears)
    game.submit(type: "pass") until game.state.stack.empty?
    expect(game.state.object(bears).controller).to eq(0)
    skip_to(game, :upkeep, turn: 4)
    expect(game.state.object(bears).controller).to eq(0) # not just until end of turn
    engine(game).move!(obj_id(game, "Mindbinder Siren"), :graveyard, reason: "test")
    expect(game.state.object(bears).controller).to eq(1)
    expect(game.state.effects).to be_empty
  end

  it "poison counters on a player; ten or more lose the game (CR 122.1f, 704.5c)" do
    game = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Venomfang Adder"
        library "Forest", count: 10
      end
      player("bob", poison: 8) { library "Forest", count: 10 }
    end
    game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
    game.submit(type: "attack", object: obj_id(game, "Venomfang Adder"), target: "player:bob")
    game.submit(type: "done") if game.pending_decision&.kind == "declare_attackers"
    game.submit(game.legal_options.first) until game.over? || game.turn > 3
    expect(game.state.players[1].poison).to eq(10)
    expect(game.state.result).to include("winner" => "alice")
  end

  it "other counters on a player (experience) are counted, shown and exported (CR 122.1)" do
    game = board
    engine(game).add_player_counters!(0, "experience", 2)
    engine(game).add_player_counters!(0, "experience", 1)
    engine(game).add_player_counters!(0, "experience", 0)
    expect(engine(game).player_counters(0)).to eq("experience" => 3)
    ctx = Enjine::Mechanics::EffectContext.new(0, nil, nil, [], [])
    amount = Enjine::Mechanics::Amount.build({ "counters" => { "of" => "you", "kind" => "experience" } }, [], "a", targets_count: 0)
    expect(amount.value(engine(game), ctx)).to eq(3)
    expect(game.view_for(:observer)["players"].first["counters"]).to eq("experience" => 3)
    copy = Enjine::Game.import(game.export, catalog: game.catalog)
    expect(copy.state.to_h).to eq(game.state.to_h)
    data = game.state.to_h
    data["players"][0]["counters"] = { "poison" => 1 }
    expect(Enjine::Snapshot.validate(data, game.catalog)).to include(a_string_matching(/players\[0\]\.counters: must map/))
  end

  it "validates exchanges with paths" do
    errors = lambda do |effect|
      Enjine::CardDefinition.from_h("name" => "X", "mana_cost" => "{1}", "types" => ["sorcery"],
                                    "abilities" => [{ "spell" => { "effects" => [effect] } }])
      []
    rescue Enjine::InvalidCardDefinition => e
      e.errors
    end
    expect(errors.call("exchange_control" => { "to" => "self" }))
      .to include("abilities[0].spell.effects[0].exchange_control.with: required")
    expect(errors.call("exchange_life_totals" => {})).to include("abilities[0].spell.effects[0].exchange_life_totals.with: required")
    expect(errors.call("set_life" => {})).to include("abilities[0].spell.effects[0].set_life.amount: required")
  end
end
