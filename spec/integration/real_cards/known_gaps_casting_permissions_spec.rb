# frozen_string_literal: true

# Real cards that needed casting, cost and permission shapes: a computed ward life payment (CR 702.21a), cast
# triggers on spells you don't own (CR 108.3), casting from a graveyard while resolving (CR 608.2g), flash that
# depends on an optional cost (CR 601.3c-e), permissions lasting "for as long as you control" a source (CR 611.2b),
# granted alternative costs (CR 702.190a), costs choosing a creature type (CR 601.2b) or matching names (CR 201.2),
# a graveyard-exile cost by mana symbols (CR 107.4) and "whenever a player gives a gift" (CR 702.174c).
RSpec.describe "Real cards: casting and permissions (known gaps)" do
  let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.real_cards) }

  def board(hand: [], battlefield: [], theirs: [], graveyard: [], their_graveyard: [], their_hand: [], step: :precombat_main,
            active: "alice", library: "Island")
    build_game(catalog) do
      turn 3, active: active, step: step
      player("alice") do
        hand(*hand) unless hand.empty?
        graveyard(*graveyard) unless graveyard.empty?
        library library, count: 10
        battlefield.each { battlefield it }
      end
      player("bob") do
        hand(*their_hand) unless their_hand.empty?
        graveyard(*their_graveyard) unless their_graveyard.empty?
        library "Swamp", count: 10
        theirs.each { battlefield it }
      end
    end
  end

  def id(game, name, zone: :battlefield, player: "alice") = obj_id(game, name, zone: zone, player: player)
  def alice(game) = game.state.players[0]
  def bob(game) = game.state.players[1]
  def cards(game, ids) = ids.map { game.state.object(it).card }
  def cast(game, name, **) = game.submit(type: "cast", object: id(game, name, zone: :hand), **)

  def pay_all(game)
    game.submit(game.legal_options.find { %w[pay_mana activate_mana].include?(it[:type]) }) while game.pending_decision.kind == "pay_cost"
  end

  def attack(game, *names)
    pass_both(game) until game.pending_decision.kind == "declare_attackers"
    names.each { game.submit(type: "attack", object: id(game, it), target: "player:bob") }
    game.submit(type: "done") if game.legal_options.include?(type: "done")
  end

  it "Bilbo: attacking casts an instant from the graveyard for {1} less; it's exiled after (CR 608.2g, 614.1a)" do
    game = board(battlefield: ["Bilbo, Thief in the Night", "Mountain"], graveyard: ["Lightning Strike", "Island"],
                 step: :beginning_of_combat)
    attack(game, "Bilbo, Thief in the Night")
    pass_both(game) # the attack trigger resolves
    strike = id(game, "Lightning Strike", zone: :graveyard)
    expect(game.legal_options).to eq([{ type: "cast", object: strike }, { type: "done" }]) # not the Island
    game.submit(type: "cast", object: strike)
    game.submit(type: "target", target: "player:bob")
    expect(game.pending_decision.details["remaining"]).to eq("{R}")
    pay_all(game)
    pass_both(game)
    expect(bob(game).life).to eq(17)
    expect(cards(game, game.state.exile)).to eq(["lightning_strike"])
  end

  it "Gwen Stacy: the exiled card may be played for as long as you control her (CR 611.2b)" do
    game = board(hand: ["Gwen Stacy // Ghost-Spider", "Lightning Strike"], battlefield: %w[Mountain Mountain Mountain Mountain],
                 library: "Mountain")
    cast(game, "Gwen Stacy // Ghost-Spider")
    pay_all(game)
    pass_both(game) # Gwen resolves
    pass_both(game) # her enters trigger exiles the top card
    exiled = game.state.exile.first
    expect(game.legal_options).to include(a_hash_including(type: "play_land", object: exiled))
    cast(game, "Lightning Strike")
    game.submit(type: "target", target: id(game, "Gwen Stacy // Ghost-Spider"))
    pay_all(game)
    pass_both(game)
    expect(game.legal_options.none? { it[:object] == exiled }).to be(true)
    expect(game.state.effects.none? { it["kind"] == "permission" }).to be(true)
  end

  it "Hama: cast the exiled card during your turn by waterbending {X}, X its mana value (CR 701.67a, 118.9)" do
    game = board(hand: ["Hama, the Bloodbender"], battlefield: %w[Island Island Swamp Swamp Swamp] + ["Raubahn, Bull of Ala Mhigo"],
                 their_graveyard: ["Lightning Strike"])
    cast(game, "Hama, the Bloodbender")
    pay_all(game)
    pass_both(game) # Hama resolves
    game.submit(type: "target", target: "player:bob") if game.pending_decision.kind == "choose_target"
    pass_both(game) until game.pending_decision.kind == "effect_choice"
    strike = id(game, "Lightning Strike", zone: :graveyard, player: "bob")
    game.submit(type: "choose", object: strike) if game.legal_options.include?(type: "choose", object: strike)
    game.submit(game.legal_options.find { it[:object] == strike }) unless game.state.exile.any?
    exiled = game.state.exile.first
    expect(cards(game, [exiled])).to eq(["lightning_strike"])
    option = game.legal_options.find { it[:type] == "cast" && it[:object] == exiled }
    game.submit(option)
    game.submit(type: "target", target: "player:bob")
    expect(game.pending_decision.details["remaining"]).to eq("{2}")
    expect(game.legal_options.count { it[:type] == "waterbend" }).to eq(2) # Hama and Raubahn
    game.legal_options.select { it[:type] == "waterbend" }.each { game.submit(it) }
    pass_both(game)
    expect(bob(game).life).to eq(17)
  end

  it "Hama: the permission works only during your turn" do
    game = board(hand: ["Hama, the Bloodbender"], battlefield: %w[Island Island Island Island Swamp Swamp Swamp],
                 their_graveyard: ["Lightning Strike"])
    cast(game, "Hama, the Bloodbender")
    pay_all(game)
    pass_both(game)
    game.submit(type: "target", target: "player:bob") if game.pending_decision.kind == "choose_target"
    pass_both(game) until game.pending_decision.kind == "effect_choice"
    game.submit(game.legal_options.find { it[:object] })
    exiled = game.state.exile.first
    expect(game.legal_options.any? { it[:object] == exiled }).to be(true)
    skip_to(game, :upkeep, turn: 4)
    game.submit(type: "pass") # bob passes; alice has priority during bob's turn
    expect(game.pending_decision.player).to eq("alice")
    expect(game.legal_options.none? { it[:object] == exiled }).to be(true)
  end

  it "Molten Exhale: at instant speed only by beholding a Dragon, which then must be paid (CR 601.3c)" do
    game = board(hand: ["Molten Exhale", "Smaug, Wicked Worm"], battlefield: %w[Mountain Mountain], theirs: ["Raubahn, Bull of Ala Mhigo"],
                 step: :upkeep)
    exhale = id(game, "Molten Exhale", zone: :hand)
    monitor = Enjine::RulesMonitor.new(game)
    expect(game.legal_options).to include(type: "cast", object: exhale)
    cast(game, "Molten Exhale")
    expect(game.legal_options).to eq([{ type: "kick" }, { type: "cancel" }])
    game.submit(type: "kick")
    game.submit(type: "target", target: id(game, "Raubahn, Bull of Ala Mhigo", player: "bob"))
    monitor.check!(game.submit(type: "cost", object: id(game, "Smaug, Wicked Worm", zone: :hand)))
    while game.pending_decision.kind == "pay_cost" # the spell becomes cast with the last payment (CR 601.2i)
      monitor.check!(game.submit(game.legal_options.find { %w[pay_mana activate_mana].include?(it[:type]) }))
    end
    expect(cards(game, game.state.stack)).to include("molten_exhale") # (Raubahn's ward triggers too)
    expect(monitor.findings).to be_empty # the rules monitor knows the paid cost let it be cast at instant speed

    game = board(hand: ["Molten Exhale"], battlefield: %w[Mountain Mountain], theirs: ["Raubahn, Bull of Ala Mhigo"], step: :upkeep)
    expect(game.legal_options.none? { it[:type] == "cast" }).to be(true) # no Dragon to behold

    game = board(hand: ["Molten Exhale"], battlefield: %w[Mountain Mountain], theirs: ["Raubahn, Bull of Ala Mhigo"])
    cast(game, "Molten Exhale") # main phase: without the cost
    expect(game.legal_options).to include(type: "no_kick")
  end

  it "Celestial Reunion: choose a type, behold two of it; a found creature of that type enters (CR 601.2b, 607.2d)" do
    game = board(hand: ["Celestial Reunion", "Mudbutton Cursetosser"], battlefield: ["Forest", "Forest", "Stony-Voiced Goblins"],
                 library: "Fanatical Firebrand")
    cast(game, "Celestial Reunion")
    expect(game.legal_options).to include({ type: "kick" }, { type: "no_kick" })
    game.submit(type: "kick")
    game.submit(type: "x", value: 1)
    expect(game.legal_options).to include(type: "cost", creature_type: "goblin")
    game.submit(type: "cost", creature_type: "goblin")
    cursetosser = id(game, "Mudbutton Cursetosser", zone: :hand)
    expect(game.legal_options).to contain_exactly({ type: "cost", object: cursetosser },
                                                  { type: "cost", object: id(game, "Stony-Voiced Goblins") }, { type: "cancel" })
    game.submit(type: "cost", object: cursetosser)
    game.submit(type: "cost", object: id(game, "Stony-Voiced Goblins"))
    pay_all(game)
    pass_both(game)
    game.submit(game.legal_options.find { it[:type] == "find" })
    expect(cards(game, game.state.battlefield)).to include("fanatical_firebrand")

    game = board(hand: ["Celestial Reunion"], battlefield: %w[Forest Forest], library: "Fanatical Firebrand")
    cast(game, "Celestial Reunion")
    expect(game.legal_options).not_to include(type: "kick") # no two creatures share a type
    game.submit(type: "no_kick")
    game.submit(type: "x", value: 1)
    pay_all(game)
    pass_both(game)
    game.submit(game.legal_options.find { it[:type] == "find" })
    expect(cards(game, alice(game).hand)).to eq(["fanatical_firebrand"])
  end

  it "Key to the Side-Door: discard a legendary card named like a legendary permanent you control (CR 201.2a)" do
    game = board(hand: ["Raubahn, Bull of Ala Mhigo", "Nita, Forum Conciliator", "Lightning Strike"],
                 battlefield: ["Key to the Side-Door", "Raubahn, Bull of Ala Mhigo", "Mountain"])
    key = id(game, "Key to the Side-Door")
    abilities = game.legal_options.select { it[:type] == "activate" && it[:object] == key }
    game.submit(abilities.last)
    expect(game.legal_options).to eq([{ type: "cost", object: id(game, "Raubahn, Bull of Ala Mhigo", zone: :hand) },
                                      { type: "cancel" }])
    game.submit(game.legal_options.first)
    pay_all(game)
    pass_both(game)
    expect(cards(game, alice(game).graveyard)).to eq(["raubahn_bull_of_ala_mhigo"])
    expect(alice(game).hand.size).to eq(4)

    game = board(hand: ["Nita, Forum Conciliator"], battlefield: ["Key to the Side-Door", "Raubahn, Bull of Ala Mhigo", "Mountain"])
    expect(game.legal_options.count { it[:type] == "activate" }).to eq(0)
  end

  it "Ninja Teen level 3: creature cards in your graveyard have sneak {3}{B} (CR 611.3a, 702.190a)" do
    game = board(battlefield: ["Ninja Teen", "Stony-Voiced Goblins"] + (["Swamp"] * 7), graveyard: ["Fanatical Firebrand"],
                 step: :precombat_main)
    teen = id(game, "Ninja Teen")
    2.times do
      game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == teen })
      pay_all(game)
      pass_both(game)
    end
    firebrand = id(game, "Fanatical Firebrand", zone: :graveyard)
    expect(game.legal_options.none? { it[:object] == firebrand }).to be(true) # sneak works in declare blockers only
    attack(game, "Stony-Voiced Goblins")
    pass_both(game) # bob has no creatures to block with
    expect([game.state.step, game.pending_decision.player]).to eq([:declare_blockers, "alice"])
    option = game.legal_options.find { it[:type] == "cast" && it[:object] == firebrand }
    expect(option[:via]).to start_with("alt:cards_have:")
    game.submit(option)
    game.submit(type: "cost", object: id(game, "Stony-Voiced Goblins"))
    pay_all(game)
    pass_both(game) # Ninja Teen's trigger: the returned Goblins left the battlefield
    pass_both(game) # the Firebrand enters tapped and attacking
    brand = id(game, "Fanatical Firebrand")
    expect(game.state.object(brand).tapped).to be(true)
    expect(bob(game).life).to eq(19)
  end

  it "Baron Helmut Zemo: exile cards with 15+ black symbols, copy them, cast up to three copies (CR 107.4e, 707.12)" do
    game = board(battlefield: ["Baron Helmut Zemo"], graveyard: (["Hama, the Bloodbender"] * 6) + ["Lightning Strike"],
                 step: :beginning_of_combat)
    zemo = id(game, "Baron Helmut Zemo")
    expect(game.legal_options.none? { it[:type] == "activate" }).to be(true) # boast: only after it attacked
    attack(game, "Baron Helmut Zemo")
    game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == zemo })
    hamas = alice(game).graveyard.select { game.state.object(it).card == "hama_the_bloodbender" }
    expect(game.legal_options).to contain_exactly(*hamas.map { { type: "cost", object: it } }, { type: "cancel" }) # black cards only
    hamas.first(4).each { game.submit(type: "cost", object: it) }
    expect(game.legal_options).not_to include(type: "done") # 12 black symbols so far
    game.submit(type: "cost", object: hamas[4])
    expect(game.legal_options).to include(type: "done")
    game.submit(type: "done")
    expect(game.state.exile.size).to eq(5)
    pass_both(game)
    3.times { game.submit(game.legal_options.find { it[:type] == "cast" }) }
    copies = game.state.stack.map { game.state.object(it) }
    expect(copies.size).to eq(3)
    expect(copies.map(&:card).uniq).to eq(["hama_the_bloodbender"])
  end

  it "Raubahn: Ward—Pay life equal to Raubahn's power (CR 702.21a, 119.4)" do
    game = board(hand: ["Lightning Strike"], battlefield: %w[Mountain Mountain], theirs: ["Raubahn, Bull of Ala Mhigo"])
    cast(game, "Lightning Strike")
    game.submit(type: "target", target: id(game, "Raubahn, Bull of Ala Mhigo", player: "bob"))
    pay_all(game)
    pass_both(game) # ward resolves
    expect(game.legal_options).to eq([{ type: "pay" }, { type: "decline" }])
    game.submit(type: "pay")
    expect(alice(game).life).to eq(18)
  end

  it "Nita: a spell you cast but don't own triggers her; she lets you cast an opponent's exiled instant (CR 108.3)" do
    game = board(battlefield: ["Nita, Forum Conciliator", "Raubahn, Bull of Ala Mhigo", "Swamp", "Swamp", "Plains", "Plains",
                               "Mountain"],
                 their_graveyard: ["Lightning Strike"])
    nita = id(game, "Nita, Forum Conciliator")
    ability = game.legal_options.find { it[:type] == "activate" && it[:object] == nita }
    game.submit(ability)
    game.submit(type: "target", target: id(game, "Lightning Strike", zone: :graveyard, player: "bob"))
    game.submit(type: "cost", object: id(game, "Raubahn, Bull of Ala Mhigo"))
    pay_all(game)
    pass_both(game)
    strike = game.state.exile.first
    expect(game.legal_options).to include(a_hash_including(type: "cast", object: strike))
    game.submit(game.legal_options.find { it[:type] == "cast" && it[:object] == strike })
    game.submit(type: "target", target: "player:bob")
    pay_all(game)
    pass_both(game) # Nita's trigger resolves
    expect(game.state.object(nita).counters).to eq("+1/+1" => 1)
    pass_both(game) # the Strike resolves and is exiled instead of going to bob's graveyard
    expect(bob(game).life).to eq(17)
    expect(cards(game, game.state.exile)).to eq(["lightning_strike"])
  end
end
