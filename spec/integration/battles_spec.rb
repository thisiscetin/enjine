# frozen_string_literal: true

# Invented battle cards (CR 310): defense counters (310.4), a Siege's protector (310.9, 310.12), attacking a battle
# (310.5, 506.3), damage removing defense counters (120.3h), the 0-defense state-based action (310.7, 704.5v) and a
# Siege's defeat: exile it, then cast it transformed without paying its mana cost (310.12, 712.10).
RSpec.describe "Battles (CR 310)" do
  let(:siege) do
    { "name" => "Spec Invasion // Spec Liberator", "layout" => "transform", "faces" => [
      { "name" => "Spec Invasion", "mana_cost" => "{2}", "types" => ["battle"], "subtypes" => ["siege"], "defense" => 3,
        "abilities" => [{ "triggered" => { "when" => { "enters" => {} }, "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] },
      { "name" => "Spec Liberator", "colors" => ["R"], "types" => ["creature"], "power" => 5, "toughness" => 5 }
    ] }
  end
  let(:bolt) do
    { "name" => "Spec Spark", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                     "effects" => [{ "deal_damage" => { "amount" => 3, "to" => { "target" => 0 } } }] } }] }
  end

  def board(hand: [], battlefield: [], theirs: [], step: :precombat_main, mana: { C: 4, R: 2 })
    build_game(catalog_with(siege, bolt)) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana) do
        hand(*hand) unless hand.empty?
        library "Island", count: 10
        battlefield.each { battlefield it }
      end
      player("bob") do
        library "Swamp", count: 10
        theirs.each { battlefield it }
      end
    end
  end

  def play(game, action, *answers)
    game.submit(action) if action
    until (decision = game.pending_decision).kind == "priority" && game.state.stack.empty?
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost"
        pays = game.legal_options.select { it[:type] == "pay_mana" }
        game.submit(pays.find { it[:mana].to_s == "C" } || pays.first || raise("no mana"))
      else
        answer = answers.shift or raise "no answer for #{decision.kind}: #{game.legal_options}"
        game.submit(answer.respond_to?(:call) ? answer.call(game) : answer)
      end
    end
    game
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def cast(game, card, *) = play(game, { type: "cast", object: obj_id(game, card, zone: :hand, player: "alice") }, *)

  # The Siege, cast from hand: it enters with its defense counters and bob protecting it.
  def with_siege(extra: [], **)
    game = board(hand: ["Spec Invasion // Spec Liberator", *extra], **)
    cast(game, "Spec Invasion // Spec Liberator")
    [game, obj_id(game, "Spec Invasion // Spec Liberator")]
  end

  it "enters with defense counters equal to its printed defense; an opponent protects a Siege (CR 310.4b, 310.12)" do
    game, battle = with_siege
    obj = game.state.object(battle)
    expect([obj.counters["defense"], engine(game).protector(obj)]).to eq([3, 1])
    expect(view_of(game, battle)).to include("defense" => 3, "protector" => "bob")
    expect(game.state.players[0].life).to eq(21) # its own enters trigger
  end

  it "its controller can attack it; the protector blocks for it; combat damage removes defense counters (CR 310.5, 120.3h)" do
    game, battle = with_siege(battlefield: ["Grizzly Bears"])
    skip_to(game, :beginning_of_combat)
    game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
    bears = obj_id(game, "Grizzly Bears")
    expect(game.legal_options).to include({ type: "attack", object: bears, target: battle })
    game.submit(type: "attack", object: bears, target: battle)
    game.submit(type: "done") if option_types(game).include?("done")
    skip_to(game, :end_of_combat)
    expect(game.state.object(battle).counters["defense"]).to eq(1)
  end

  it "the protector's own battle isn't an attack target for them, and any_target includes battles (CR 115.4)" do
    game, battle = with_siege
    e = engine(game)
    e.state.active = 1
    expect(e.attack_targets).not_to include(battle)
    e.state.active = 0
    expect(Enjine::Mechanics::Filters::AnyTarget.match?(e, battle, 0)).to be(true)
    expect(Enjine::Mechanics::Filters::Battle.match?(e, battle, 0)).to be(true)
    expect(e.lethal_damage(nil, battle)).to eq(3)
  end

  it "defeated: the last counter removed exiles it, then you may cast it transformed for free (CR 310.12, 712.10)" do
    game, battle = with_siege(extra: ["Spec Spark"])
    spark = obj_id(game, "Spec Spark", zone: :hand, player: "alice")
    play(game, { type: "cast", object: spark }, { type: "target", target: battle },
         ->(g) { g.legal_options.find { it[:type] == "cast" } })
    liberator = game.state.battlefield.find { engine(game).chars(it).name == "Spec Liberator" }
    expect(liberator).not_to be_nil
    expect(engine(game).transformed?(game.state.object(liberator))).to be(true)
    expect(game.state.exile).to be_empty
  end

  it "defeated and declined: it stays in exile; it isn't put into the graveyard by the 0-defense rule first (CR 704.5v)" do
    game, battle = with_siege(extra: ["Spec Spark"])
    spark = obj_id(game, "Spec Spark", zone: :hand, player: "alice")
    play(game, { type: "cast", object: spark }, { type: "target", target: battle }, { type: "done" })
    expect(game.state.exile.map { game.state.object(it).card }).to eq(["spec_invasion"])
    expect(game.state.players[0].graveyard.map { game.state.object(it).card }).to eq(["spec_spark"])
  end

  it "defeated, but gone before the trigger resolves: nothing is exiled or cast (CR 310.12, 608.2b)" do
    game, battle = with_siege(extra: ["Spec Spark"])
    game.submit(type: "cast", object: obj_id(game, "Spec Spark", zone: :hand, player: "alice"))
    game.submit(type: "target", target: battle)
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
    game.submit(type: "pass") until game.state.stack.size == 1 && game.state.object(game.state.stack.first).ability?
    expect(game.state.battlefield).to include(battle) # 0 defense, but its trigger waits (CR 704.5v)
    engine(game).move!(battle, :graveyard, reason: "test")
    play(game, nil)
    expect(game.state.exile).to be_empty
    expect(game.state.players[0].graveyard.map { game.state.object(it).card }).to contain_exactly("spec_invasion", "spec_spark")
  end

  it "a battle with 0 defense and no defeat trigger waiting is put into its owner's graveyard (CR 704.5v)" do
    game, battle = with_siege
    e = engine(game)
    game.state.object(battle).counters["defense"] = 0
    e.touch!
    e.check_state_based_actions!
    expect(game.state.players[0].graveyard.map { game.state.object(it).card }).to eq(["spec_invasion"])
  end

  it "a Siege whose protector gains control of it gets a new protector (CR 704.5x)" do
    game, battle = with_siege
    e = engine(game)
    game.state.object(battle).memory["protector"] = 0
    e.check_state_based_actions!
    expect(e.protector(game.state.object(battle))).to eq(1)
  end

  it "validates battle data (CR 310.4, 205.3q)" do
    bad = lambda do |card|
      Enjine::CardDefinition.from_h(card)
    rescue Enjine::InvalidCardDefinition => e
      e.message
    end
    expect(bad.call({ "name" => "X", "types" => ["battle"], "subtypes" => ["siege"] })).to include("battles need an integer defense")
    expect(bad.call({ "name" => "X", "types" => ["battle"], "defense" => 2 })).to include("needs the battle type siege")
    expect(bad.call({ "name" => "X", "types" => ["artifact"], "defense" => 2 })).to include("only battles have defense")
    expect(Enjine::CardDefinition.from_h(siege).to_h["faces"].first).to include("defense" => 3)
  end
end
