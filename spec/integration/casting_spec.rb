# frozen_string_literal: true

RSpec.describe "Casting spells and the stack (CR 601, 608)" do
  let(:game) do
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Grizzly Bears", "Lightning Bolt", "Lightning Bolt", "Giant Growth"
        battlefield "Forest", "Forest", "Mountain", "Mountain"
        library "Forest", count: 5
      end
      player("bob") do
        hand "Counterspell", "Hill Giant", "Watchful Sentry"
        battlefield "Island", "Island", "Plains", "Grizzly Bears"
        library "Forest", count: 5
      end
    end
  end

  let(:hand) { ids_in(game, "alice", :hand) }
  let(:bears_card) { hand[0] }
  let(:forests) { game.state.battlefield.first(2) }
  let(:mountains) { game.state.battlefield[2, 2] }
  let(:bob_bears) { game.state.battlefield.last }

  def tap_and_pay(game, *lands)
    lands.each do |land|
      game.submit(type: "activate_mana", object: land, ability: mana_ref(game, land))
      game.submit(game.legal_options.find { it[:type] == "pay_mana" })
    end
  end

  it "offers casting only for cards whose timing, targets and mana allow it" do
    expect(game.legal_options.select { it[:type] == "cast" }.map { it[:object] }).to eq(hand)
    game.submit(type: "pass")
    # Bob on Alice's turn: Hill Giant is sorcery speed; Counterspell needs a spell to target; Sentry has flash.
    expect(game.legal_options.select { it[:type] == "cast" }.map { it[:object] }).to eq([ids_in(game, "bob", :hand)[2]])
  end

  it "moves the card to the stack, then asks for mana one source and one symbol at a time (CR 601.2a, 601.2g-h)" do
    entry = game.submit(type: "cast", object: bears_card)
    stack_id = game.state.stack.first
    expect(entry.events.first).to have_attributes(from: "hand", to: "stack", reason: "cast")
    expect(game.pending_decision).to have_attributes(kind: "pay_cost", details: { "remaining" => "{1}{G}" })
    expect(game.legal_options).to eq(
      game.state.battlefield.first(4).map { { type: "activate_mana", object: it, ability: mana_ref(game, it) } } + [{ type: "cancel" }]
    )

    game.submit(type: "activate_mana", object: forests[0], ability: mana_ref(game, forests[0]))
    expect(game.legal_options.first).to eq(type: "pay_mana", mana: "G")
    game.submit(type: "pay_mana", mana: "G")
    expect(game.pending_decision.details).to eq("remaining" => "{1}")
    game.submit(type: "activate_mana", object: mountains[0], ability: mana_ref(game, mountains[0]))
    entry = game.submit(type: "pay_mana", mana: "R")

    expect(entry.events.map(&:type)).to eq(%w[mana_paid spell_cast])
    expect(game.pending_decision).to have_attributes(kind: "priority", player: "alice")
    expect(game.view_for("bob")["stack"].map { it["name"] }).to eq(["Grizzly Bears"])

    pass_both(game)
    expect(game.state.battlefield).not_to include(stack_id)
    new_bears = game.state.battlefield.find { game.state.object(it).card == "grizzly_bears" && game.state.object(it).owner.zero? }
    expect(view_of(game, new_bears)).to include("power" => 2, "toughness" => 2, "summoning_sick" => true)
    expect(game.pending_decision.player).to eq("alice") # CR 117.3b
  end

  it "pays generic costs with any color and colored costs only with that color" do
    game.submit(type: "cast", object: bears_card)
    game.submit(type: "activate_mana", object: mountains[0], ability: mana_ref(game, mountains[0]))
    game.submit(type: "pay_mana", mana: "R") # pays the generic part
    expect(game.pending_decision.details).to eq("remaining" => "{G}")
    game.submit(type: "activate_mana", object: mountains[1], ability: mana_ref(game, mountains[1]))
    expect(game.legal_options).not_to include(a_hash_including(type: "pay_mana"))
  end

  it "rewinds everything on cancel: card back in hand at the same place, lands untapped, pool restored (CR 733)" do
    game.submit(type: "activate_mana", object: mountains[1], ability: mana_ref(game, mountains[1])) # mana in pool before casting stays
    before_hand = ids_in(game, "alice", :hand).dup
    game.submit(type: "cast", object: bears_card)
    game.submit(type: "activate_mana", object: forests[0], ability: mana_ref(game, forests[0]))
    game.submit(type: "pay_mana", mana: "G")
    entry = game.submit(type: "cancel")

    expect(entry.events.map(&:type)).to eq(%w[untapped cast_cancelled])
    expect(ids_in(game, "alice", :hand)).to eq(before_hand)
    expect(game.state.object(forests[0]).tapped).to be(false)
    expect(game.state.object(mountains[1]).tapped).to be(true)
    expect(game.state.players[0].mana_pool).to include(R: 1, G: 0)
    expect(game.state.stack).to be_empty
    expect(game.pending_decision).to have_attributes(kind: "priority", player: "alice")
  end

  it "cancels during target selection too" do
    game.submit(type: "cast", object: hand[1])
    expect(game.pending_decision.kind).to eq("choose_target")
    expect(game.legal_options.last).to eq(type: "cancel")
    game.submit(type: "cancel")
    expect(ids_in(game, "alice", :hand)).to eq(hand)
  end

  it "Lightning Bolt to the face: 3 damage causes 3 life loss (CR 120.3a)" do
    game.submit(type: "cast", object: hand[1])
    expect(game.legal_options.map { it[:target] }).to eq(["player:alice", "player:bob", bob_bears, nil])
    game.submit(type: "target", target: "player:bob")
    tap_and_pay(game, mountains[0])
    bolt_on_stack = game.state.stack.first
    entry = nil
    2.times { entry = game.submit(type: "pass") }
    expect(entry.events.map(&:to_h)).to include(
      { "type" => "damage_dealt", "source" => bolt_on_stack, "target" => "player:bob", "amount" => 3, "combat" => false },
      { "type" => "life_changed", "player" => "bob", "from" => 20, "to" => 17 }
    )
    expect(game.view_for("alice")["players"][0]["graveyard"].map { it["name"] }).to eq(["Lightning Bolt"])
  end

  it "Counterspell counters a spell in response; both end up in graveyards (CR 701.6)" do
    game.submit(type: "cast", object: bears_card)
    tap_and_pay(game, forests[0], forests[1])
    bears_on_stack = game.state.stack.first
    game.submit(type: "pass")

    counterspell = ids_in(game, "bob", :hand)[0]
    expect(game.legal_options).to include(type: "cast", object: counterspell)
    game.submit(type: "cast", object: counterspell)
    expect(game.legal_options).to eq([{ type: "target", target: bears_on_stack }, { type: "cancel" }])
    game.submit(type: "target", target: bears_on_stack)
    islands = game.state.battlefield.select { game.state.object(it).card == "island" }
    tap_and_pay(game, *islands)

    pass_both(game) # Counterspell resolves
    expect(game.state.stack).to be_empty
    view = game.view_for(:observer)
    expect(view["players"][0]["graveyard"].map { it["name"] }).to eq(["Grizzly Bears"])
    expect(view["players"][1]["graveyard"].map { it["name"] }).to eq(["Counterspell"])
    expect(view["battlefield"].count { it["name"] == "Grizzly Bears" }).to eq(1)
  end

  it "a spell whose only target became illegal doesn't resolve (CR 608.2b)" do
    2.times do |i|
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).find { game.state.object(it).card == "lightning_bolt" })
      game.submit(type: "target", target: bob_bears)
      tap_and_pay(game, mountains[i])
    end
    pass_both(game) # second Bolt resolves: Bears die
    expect(game.state.battlefield).not_to include(bob_bears)
    entry = nil
    2.times { entry = game.submit(type: "pass") }
    expect(entry.events.map(&:type)).to include("fizzled")
    expect(entry.events.map(&:type)).not_to include("damage_dealt")
    expect(game.view_for(:observer)["players"][0]["graveyard"].size).to eq(2)
  end

  it "Giant Growth in response saves a creature from Lightning Bolt (instant-speed interaction)" do
    g = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Lightning Bolt"
        battlefield "Mountain"
        library "Forest", count: 5
      end
      player("bob") do
        hand "Giant Growth"
        battlefield "Grizzly Bears", "Forest"
        library "Forest", count: 5
      end
    end
    bears = obj_id(g, "Grizzly Bears")
    g.submit(type: "cast", object: ids_in(g, "alice", :hand).first)
    g.submit(type: "target", target: bears)
    tap_and_pay(g, obj_id(g, "Mountain"))
    g.submit(type: "pass")
    g.submit(type: "cast", object: ids_in(g, "bob", :hand).first)
    g.submit(type: "target", target: bears)
    tap_and_pay(g, obj_id(g, "Forest"))
    pass_both(g) # Giant Growth resolves first (last in, first out)
    expect(view_of(g, bears)).to include("power" => 5, "toughness" => 5)
    pass_both(g) # Bolt resolves
    expect(view_of(g, bears)).to include("damage" => 3, "toughness" => 5)
    skip_to(g, :upkeep, turn: 4)
    expect(view_of(g, bears)).to include("damage" => 0, "power" => 2, "toughness" => 2)
  end

  it "flash lets a creature be cast on the opponent's turn (CR 702.8a)" do
    game.submit(type: "pass")
    sentry = ids_in(game, "bob", :hand)[2]
    game.submit(type: "cast", object: sentry)
    tap_and_pay(game, game.state.battlefield[6], game.state.battlefield[4])
    pass_both(game)
    expect(game.view_for(:observer)["battlefield"].map { it["name"] }).to include("Watchful Sentry")
  end

  it "Revitalize: multiple effects resolve in order" do
    g = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice", life: 10) do
        hand "Revitalize", "Divination"
        battlefield "Plains", "Plains", "Island"
        library "Island", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    g.submit(type: "cast", object: ids_in(g, "alice", :hand).first)
    tap_and_pay(g, *g.state.battlefield.first(2))
    entry = nil
    2.times { entry = g.submit(type: "pass") }
    expect(entry.events.map(&:type).first(4)).to eq(%w[priority_passed life_changed zone_changed resolved])
    expect(g.view_for("alice")["players"][0]).to include("life" => 13, "hand_count" => 2)
    expect(g.legal_options).not_to include(a_hash_including(type: "cast")) # Divination needs 3 mana
  end
end
