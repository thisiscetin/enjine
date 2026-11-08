# frozen_string_literal: true

RSpec.describe "Combat (CR 506-511)" do
  let(:game) do
    build_game do
      turn 3, active: "alice", step: :beginning_of_combat
      player("alice") do
        battlefield "Grizzly Bears", "Hill Giant"
        battlefield "Raging Goblin", controlled_since: 3 # entered this turn, has haste
        battlefield "Grizzly Bears", controlled_since: 3 # entered this turn: summoning sick
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Grizzly Bears"
        battlefield "Grizzly Bears", tapped: true
        library "Forest", count: 5
      end
    end
  end

  let(:bears) { game.state.battlefield[0] }
  let(:giant) { game.state.battlefield[1] }
  let(:goblin) { game.state.battlefield[2] }
  let(:sick_bears) { game.state.battlefield[3] }
  let(:bob_bears) { game.state.battlefield[4] }

  def life(name) = game.view_for(:observer)["players"].find { it["name"] == name }["life"]

  it "lets untapped, non-sick creatures (or haste) attack the defending player (CR 302.6, 508.1a)" do
    pass_both(game)
    decision = game.pending_decision
    expect(decision).to have_attributes(kind: "declare_attackers", player: "alice")
    attackers = decision.options.filter_map { it[:object] }.uniq
    expect(attackers).to eq([bears, giant, goblin])
    expect(view_of(game, sick_bears)["summoning_sick"]).to be(true)
  end

  it "taps attackers, lets the defender block, and deals damage simultaneously (CR 508.1f, 509, 510.2)" do
    pass_both(game)
    game.submit(type: "attack", object: bears, target: "player:bob")
    game.submit(type: "attack", object: giant, target: "player:bob")
    game.submit(type: "done")
    expect([bears, giant].map { game.state.object(it).tapped }).to eq([true, true])
    expect(view_of(game, bears)["attacking"]).to eq("player:bob")

    pass_both(game) # -> declare blockers
    expect(game.pending_decision).to have_attributes(kind: "declare_blockers", player: "bob")
    expect(game.legal_options).to eq([{ type: "done" }, { type: "block", object: bob_bears, attacker: bears },
                                      { type: "block", object: bob_bears, attacker: giant }])
    game.submit(type: "block", object: bob_bears, attacker: giant)
    expect(view_of(game, bob_bears)["blocking"]).to eq(giant)

    entry = nil
    2.times { entry = game.submit(type: "pass") } # -> combat damage
    damage = entry.events.grep(Enjine::Events::DamageDealt).map { [it.source, it.target, it.amount] }
    expect(damage).to contain_exactly([bears, "player:bob", 2], [giant, bob_bears, 3], [bob_bears, giant, 2])
    expect(life("bob")).to eq(18)
    expect(game.state.battlefield).not_to include(bob_bears) # lethal damage (CR 704.5g)
    expect(view_of(game, giant)).to include("damage" => 2)
    expect(game.step).to eq(:combat_damage)
  end

  it "skips declare blockers and combat damage when nobody attacks (CR 508.8)" do
    pass_both(game)
    game.submit(type: "done")
    expect(game.step).to eq(:declare_attackers)
    pass_both(game)
    expect(game.step).to eq(:end_of_combat)
  end

  it "lets an attacker blocked by several creatures divide its damage (CR 510.1c)" do
    g = build_game do
      turn 3, active: "alice", step: :declare_blockers
      player("alice") do
        battlefield "Hill Giant", tapped: true
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Grizzly Bears", "Raging Goblin"
        library "Forest", count: 5
      end
    end
    giant, bears, goblin = g.state.battlefield
    state = g.to_h
    state["state"]["attackers"] = { giant => { "target" => "player:bob", "blocked" => true } }
    state["state"]["blockers"] = { bears => giant, goblin => giant }
    state["state"]["attacks_declared"] = 1
    g = Enjine::Game.import(state, catalog: core_catalog)

    pass_both(g)
    expect(g.pending_decision).to have_attributes(kind: "assign_damage", player: "alice",
                                                  details: { "attacker" => giant, "remaining" => 3 })
    g.submit(type: "assign", object: goblin)
    g.submit(type: "assign", object: bears)
    g.submit(type: "assign", object: bears)
    # 1 to the Goblin, 2 to the Bears: both die; they deal 1 + 2 = 3 back, lethal for the 3/3 Giant.
    expect(g.state.battlefield).to be_empty
    expect(g.view_for(:observer)["players"].map { it["graveyard"].size }).to eq([1, 2])
  end

  it "removes a creature that leaves the battlefield from combat, but blocks still happen (CR 506.4, 508.8)" do
    g = build_game do
      turn 3, active: "alice", step: :beginning_of_combat
      player("alice") do
        battlefield "Grizzly Bears"
        library "Forest", count: 5
      end
      player("bob") do
        hand "Lightning Bolt"
        battlefield "Mountain", "Grizzly Bears"
        library "Forest", count: 5
      end
    end
    attacker = g.state.battlefield[0]
    pass_both(g)
    g.submit(type: "attack", object: attacker, target: "player:bob")
    g.submit(type: "pass")
    g.submit(type: "cast", object: ids_in(g, "bob", :hand).first)
    g.submit(type: "target", target: attacker)
    g.submit(type: "activate_mana", object: g.state.battlefield[1], ability: mana_ref(g, g.state.battlefield[1]))
    g.submit(type: "pay_mana", mana: "R")
    pass_both(g)
    expect(g.state.battlefield).not_to include(attacker)
    expect(g.view_for(:observer)["battlefield"].none? { it.key?("attacking") }).to be(true)
    pass_both(g)
    expect(g.step).to eq(:declare_blockers) # still happens: an attacker was declared
    skip_to(g, :end_of_combat)
    expect(g.view_for(:observer)["players"][1]["life"]).to eq(20)
  end

  it "clears attacking and blocking status at end of combat (CR 511.3)" do
    pass_both(game)
    game.submit(type: "attack", object: goblin, target: "player:bob")
    game.submit(type: "done")
    skip_to(game, :postcombat_main)
    expect(view_of(game, goblin)).not_to have_key("attacking")
    expect(life("bob")).to eq(19)
  end
end
