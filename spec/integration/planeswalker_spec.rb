# frozen_string_literal: true

RSpec.describe "Planeswalkers (CR 306, 606) — Vessa, Rally Captain" do
  # Vessa: +1: creatures you control get +1/+1 until end of turn.
  #        −2: put a +1/+1 counter on each creature you control.
  #        −3: 3 damage to target creature.
  def board(loyalty: 3, bob_hand: [])
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Vessa, Rally Captain", loyalty: loyalty
        battlefield "Grizzly Bears", "Hill Giant"
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Grizzly Bears", "Mountain"
        bob_hand.each { hand it }
        library "Forest", count: 5
      end
    end
  end

  let(:game) { board }
  let(:vessa) { obj_id(game, "Vessa, Rally Captain") }
  let(:alice_bears) { game.state.battlefield[1] }
  let(:giant) { game.state.battlefield[2] }
  let(:bob_bears) { game.state.battlefield[3] }

  def pt(id) = view_of(game, id).values_at("power", "toughness")
  def loyalty = view_of(game, vessa)["loyalty"]

  it "offers each loyalty ability at sorcery speed" do
    expect(game.legal_options).to include({ type: "activate", object: vessa, ability: "printed:0" },
                                          { type: "activate", object: vessa, ability: "printed:1" },
                                          { type: "activate", object: vessa, ability: "printed:2" })
  end

  it "+1: loyalty goes up on activation; creatures get +1/+1 only when the ability resolves" do
    entry = game.submit(type: "activate", object: vessa, ability: "printed:0")

    # CR 602.2b / 606.4: the loyalty cost is paid while activating...
    expect(loyalty).to eq(4)
    expect(entry.events.map(&:type)).to include("counters_changed", "ability_activated")
    # ...but the effect waits on the stack.
    expect(game.view_for(:observer)["stack"].first).to include("name" => "Vessa, Rally Captain ability",
                                                               "loyalty_cost" => 1)
    expect(pt(alice_bears)).to eq([2, 2])
    expect(game.pending_decision.player).to eq("alice") # CR 117.3c

    pass_both(game) # CR 608: both pass -> the ability resolves
    expect(game.state.stack).to be_empty
    expect(pt(alice_bears)).to eq([3, 3])
    expect(pt(giant)).to eq([4, 4])
    expect(pt(bob_bears)).to eq([2, 2]) # only creatures Vessa's controller controls
    expect(loyalty).to eq(4)
  end

  it "allows only one loyalty ability per planeswalker per turn (CR 606.3)" do
    game.submit(type: "activate", object: vessa, ability: "printed:0")
    pass_both(game)
    expect(game.legal_options).not_to include(a_hash_including(type: "activate", object: vessa))
  end

  it "is not available while the stack is not empty or on the opponent's turn (sorcery speed)" do
    game.submit(type: "activate", object: vessa, ability: "printed:0")
    expect(game.legal_options).not_to include(a_hash_including(type: "activate"))
    pass_both(game)
    skip_to(game, :upkeep, turn: 4)
    expect(game.view_for(:observer)["active"]).to eq("bob")
    expect(game.legal_options).not_to include(a_hash_including(object: vessa))
  end

  it "+1/+1 until end of turn wears off in the cleanup step (CR 514.2)" do
    game.submit(type: "activate", object: vessa, ability: "printed:0")
    pass_both(game)
    expect(game.view_for(:observer)["effects"].size).to eq(1)
    skip_to(game, :end)
    expect(pt(alice_bears)).to eq([3, 3]) # still active in the end step
    skip_to(game, :upkeep, turn: 4) # cleanup happened
    expect(pt(alice_bears)).to eq([2, 2])
    expect(game.view_for(:observer)["effects"]).to be_empty
  end

  it "locks in the affected creatures when the effect starts (CR 611.2c)" do
    g = build_game(catalog_with) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Vessa, Rally Captain", loyalty: 3
        battlefield "Forest", "Forest"
        hand "Grizzly Bears"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    walker = obj_id(g, "Vessa, Rally Captain")
    g.submit(type: "activate", object: walker, ability: "printed:0")
    pass_both(g)
    bears = ids_in(g, "alice", :hand).first
    g.submit(type: "cast", object: bears)
    g.state.battlefield.select { g.state.object(it).card == "forest" }.each do |forest|
      g.submit(type: "activate_mana", object: forest, ability: mana_ref(g, forest))
    end
    2.times { g.submit(g.legal_options.find { it[:type] == "pay_mana" }) }
    pass_both(g)
    new_bears = obj_id(g, "Grizzly Bears")
    expect(view_of(g, new_bears).values_at("power", "toughness")).to eq([2, 2])
  end

  it "−2: puts a +1/+1 counter on each creature you control; counters last beyond the turn" do
    game.submit(type: "activate", object: vessa, ability: "printed:1")
    expect(loyalty).to eq(1)
    pass_both(game)
    expect(view_of(game, alice_bears)["counters"]).to eq("+1/+1" => 1)
    expect(pt(alice_bears)).to eq([3, 3])
    expect(pt(giant)).to eq([4, 4])
    expect(view_of(game, bob_bears)).not_to have_key("counters")
    skip_to(game, :upkeep, turn: 4)
    expect(pt(alice_bears)).to eq([3, 3])
  end

  it "stacks counters and until-end-of-turn bonuses in layer 7c (CR 613.4c)" do
    game.submit(type: "activate", object: vessa, ability: "printed:1")
    pass_both(game)
    skip_to(game, :precombat_main, turn: 5)
    game.submit(type: "activate", object: vessa, ability: "printed:0")
    pass_both(game)
    expect(pt(alice_bears)).to eq([4, 4]) # 2/2 + counter + pump
    expect(loyalty).to eq(2)
  end

  it "−3 needs a target, and can't be activated with too little loyalty" do
    weak = board(loyalty: 2)
    walker = obj_id(weak, "Vessa, Rally Captain")
    expect(weak.legal_options).to include(a_hash_including(object: walker, ability: "printed:1"))
    expect(weak.legal_options).not_to include(a_hash_including(object: walker, ability: "printed:2"))

    game.submit(type: "activate", object: vessa, ability: "printed:2")
    expect(game.pending_decision.kind).to eq("choose_target")
    expect(game.legal_options.map { it[:target] }).to eq([alice_bears, giant, bob_bears, nil])
    entry = game.submit(type: "target", target: bob_bears)
    expect(entry.events.grep(Enjine::Events::CountersChanged).last.to_h).to include("from" => 3, "to" => 0)
    # The cost is paid, then state-based actions run as the player receives priority: 0 loyalty -> graveyard (CR 704.5i)
    expect(game.state.battlefield).not_to include(vessa)
    pass_both(game)
    expect(game.state.battlefield).not_to include(bob_bears) # the ability still resolves (CR 113.7a)
    expect(game.view_for("alice")["players"][1]["graveyard"].map { it["name"] }).to eq(["Grizzly Bears"])
  end

  it "the ability resolves even if the planeswalker is killed in response (CR 113.7a)" do
    g = board(loyalty: 2, bob_hand: ["Lightning Bolt"])
    walker = obj_id(g, "Vessa, Rally Captain")
    bears = g.state.battlefield[1]
    g.submit(type: "activate", object: walker, ability: "printed:0")
    expect(view_of(g, walker)["loyalty"]).to eq(3)
    g.submit(type: "pass")

    bolt = ids_in(g, "bob", :hand).first
    g.submit(type: "cast", object: bolt)
    g.submit(type: "target", target: walker)
    g.submit(type: "activate_mana", object: obj_id(g, "Mountain"), ability: "intrinsic:mountain")
    g.submit(type: "pay_mana", mana: "R")
    expect(g.view_for(:observer)["stack"].map { it["name"] }).to eq(["Lightning Bolt", "Vessa, Rally Captain ability"])

    pass_both(g) # Bolt resolves: 3 damage removes 3 loyalty counters (CR 120.3c)
    expect(g.state.battlefield).not_to include(walker) # 0 loyalty (CR 704.5i)
    expect(g.view_for(:observer)["players"][0]["graveyard"].map { it["name"] }).to eq(["Vessa, Rally Captain"])
    expect(view_of(g, bears).values_at("power", "toughness")).to eq([2, 2])

    pass_both(g) # the +1 ability is independent of its source and still resolves
    expect(view_of(g, bears).values_at("power", "toughness")).to eq([3, 3])
  end

  it "is attacked and loses loyalty from combat damage" do
    g = build_game do
      turn 3, active: "bob", step: :beginning_of_combat
      player("alice") do
        battlefield "Vessa, Rally Captain", loyalty: 3
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Hill Giant"
        library "Forest", count: 5
      end
    end
    walker = obj_id(g, "Vessa, Rally Captain")
    giant = obj_id(g, "Hill Giant")
    pass_both(g)
    expect(g.legal_options).to eq([{ type: "done" }, { type: "attack", object: giant, target: "player:alice" },
                                   { type: "attack", object: giant, target: walker }])
    g.submit(type: "attack", object: giant, target: walker)
    skip_to(g, :combat_damage)
    expect(g.state.battlefield).not_to include(walker)
    expect(g.view_for(:observer)["players"][0]["life"]).to eq(20)
  end
end
