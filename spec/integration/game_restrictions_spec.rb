# frozen_string_literal: true

RSpec.describe "Player and game restrictions (CR 101.2, 119.7, 602.5, 604.2, 615.12)" do
  def board(alice_hand: [], alice: [], bob_hand: [], bob: [], active: "alice", alice_mana: {}, bob_mana: {})
    build_game do
      turn 3, active: active, step: :precombat_main
      player("alice", mana_pool: alice_mana) do
        hand(*alice_hand)
        alice.each { |card, opts| battlefield card, **(opts || {}) }
        library "Forest", count: 10
      end
      player("bob", mana_pool: bob_mana) do
        hand(*bob_hand)
        bob.each { |card, opts| battlefield card, **(opts || {}) }
        library "Forest", count: 10
      end
    end
  end

  def pay(game) = (game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost")

  def cast(game, card, *targets, player: "alice")
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: player))
    targets.each { game.submit(type: "target", target: it) }
    pay(game)
  end

  def resolve(game) = (game.submit(type: "pass") until game.state.stack.empty? || game.over?)
  def casts(game) = game.legal_options.select { it[:type] == "cast" }
  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, who) = game.state.players[game.names.index(who)].life

  it "'your opponents can't cast spells during your turn' (CR 101.2, 604.2)" do
    game = board(alice: ["Hushwarden Sentinel"], bob_hand: ["Lightning Bolt"], bob_mana: { R: 1 })
    game.submit(type: "pass") # bob gets priority during alice's turn
    expect(game.pending_decision.player).to eq("bob")
    expect(casts(game)).to be_empty
    game = board(alice: ["Hushwarden Sentinel"], bob_hand: ["Lightning Bolt"], bob_mana: { R: 1 }, active: "bob")
    expect(casts(game).size).to eq(1)
  end

  it "'players can't cast spells this turn' stops every cast, from any zone, until cleanup" do
    game = board(alice_hand: ["Hush Order", "Lightning Bolt"], alice_mana: { W: 2, R: 1 })
    cast(game, "Hush Order")
    resolve(game)
    expect(casts(game)).to be_empty
    bolt = obj_id(game, "Lightning Bolt", zone: :hand, player: "alice")
    expect(engine(game).cast_forbidden?(0, game.state.object(bolt))).to be(true)
    skip_to(game, :upkeep, turn: 4)
    expect(game.state.effects).to be_empty
  end

  it "'can't cast spells from anywhere other than their hands' (CR 601.3)" do
    game = board(alice_hand: ["Lightning Bolt"], alice: ["Forest"])
    ctx = Enjine::Mechanics::EffectContext.new(0, nil, nil, [], [])
    engine(game).add_continuous_effect!("player_rule", ctx, ["player:alice"], "rule" => "cant_cast_except_from_hand")
    bolt = game.state.object(obj_id(game, "Lightning Bolt", zone: :hand, player: "alice"))
    expect(engine(game).cast_forbidden?(0, bolt)).to be(false)
    engine(game).move!(bolt.id, :graveyard, reason: "test")
    expect(engine(game).cast_forbidden?(0, game.state.object(ids_in(game, "alice", :graveyard).first))).to be(true)
  end

  it "'players can't gain life': lifelink and gain-life effects do nothing (CR 119.7)" do
    game = board(alice_hand: ["Revitalize"], alice: ["Cindermaw Brute"], alice_mana: { W: 2 })
    cast(game, "Revitalize")
    resolve(game)
    expect(life(game, "alice")).to eq(20)
    expect(ids_in(game, "alice", :hand).size).to eq(1) # it still drew
    engine(game).change_life!(1, -3)
    expect(life(game, "bob")).to eq(17)
  end

  it "'creature spells you control can't be countered' (CR 101.2, 701.6a)" do
    game = board(alice_hand: ["Grizzly Bears"], alice: ["Unbroken Herald"], alice_mana: { G: 2 },
                 bob_hand: %w[Counterspell Counterspell], bob_mana: { U: 4 })
    cast(game, "Grizzly Bears")
    game.submit(type: "pass")
    cast(game, "Counterspell", game.state.stack.first, player: "bob")
    resolve(game)
    expect(game.state.battlefield.map { game.state.object(it).card }).to include("grizzly_bears")
  end

  it "'activated abilities of creatures can't be activated unless they're mana abilities' (CR 602.5)" do
    game = board(alice: ["Clamp of Stillness", "Prodigal Pyromancer", "Forest"])
    expect(game.legal_options.select { it[:type] == "activate" }).to be_empty
    game = board(alice: ["Prodigal Pyromancer"])
    expect(game.legal_options.select { it[:type] == "activate" }.size).to eq(1)
    game = board(alice: ["Clamp of Stillness", "Forest"])
    expect(game.legal_options.map { it[:type] }).to include("activate_mana")
  end

  it "'damage can't be prevented this turn': a shield counter is still removed (CR 615.12)" do
    game = board(alice_hand: ["Unshielded Blast"], alice_mana: { R: 1 },
                 bob: [["Grizzly Bears", { counters: { "shield" => 1 } }]])
    bears = obj_id(game, "Grizzly Bears")
    cast(game, "Unshielded Blast", bears)
    resolve(game)
    expect(game.state.battlefield).not_to include(bears)
    expect(engine(game).unpreventable?(false)).to be(true)
  end

  it "'combat damage can't be prevented' applies only to combat damage, whoever has the rule" do
    game = board(bob: ["Unbroken Herald"])
    expect([engine(game).unpreventable?(true), engine(game).unpreventable?(false)]).to eq([true, false])
    ctx = Enjine::Mechanics::EffectContext.new(0, nil, nil, [], [])
    engine(game).add_continuous_effect!("player_rule", ctx, ["player:alice"], "rule" => "prevent_all_damage")
    expect(engine(game).deal_damage!(nil, "player:alice", 2, combat: true)).to eq(2)
    expect(engine(game).deal_damage!(nil, "player:alice", 2)).to eq(0)
  end

  it "validates restriction data with paths" do
    errors = lambda do |ability|
      Enjine::CardDefinition.from_h("name" => "X", "mana_cost" => "{1}", "types" => ["artifact"], "abilities" => [ability])
      []
    rescue Enjine::InvalidCardDefinition => e
      e.errors
    end
    expect(errors.call("player_rule" => { "rule" => "cant_gain_life", "spells" => "card" }))
      .to include("abilities[0].player_rule.spells: only for cant_cast, spells_cant_be_countered")
    expect(errors.call("player_rule" => { "rule" => "cant_cast", "filter" => "creature" }))
      .to include("abilities[0].player_rule.filter: only for cant_sacrifice, cant_activate")
    expect(errors.call("player_rule" => { "rule" => "cant_cast", "spells" => { "colour" => ["R"] } }))
      .to include(a_string_starting_with("abilities[0].player_rule.spells: unknown parameter"))
    expect(errors.call("player_rule" => { "rule" => "cant_cast", "if" => { "sometimes" => true } }))
      .to include(a_string_starting_with("abilities[0].player_rule.if: unknown condition"))
  end
end
