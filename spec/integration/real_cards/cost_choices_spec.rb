# frozen_string_literal: true

# Real cards that needed a choice between costs (cost `one_of`, CR 601.2b), optional additional costs
# (CR 118.8b), paying costs while resolving (CR 118.12) and ward with non-mana costs (CR 702.21a).
RSpec.describe "Real cards: cost choices" do
  let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.real_cards) }

  def board(hand: [], battlefield: [], theirs: [], graveyard: [], life: 20)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", life: life) do
        hand(*hand)
        graveyard(*graveyard) unless graveyard.empty?
        library "Island", count: 10
        battlefield.each { battlefield it }
      end
      player("bob") do
        library "Swamp", count: 10
        theirs.each { battlefield it }
      end
    end
  end

  def id(game, name, zone: :battlefield, player: "alice") = obj_id(game, name, zone: zone, player: player)
  def alice(game) = game.state.players[0]
  def cards(game, ids) = ids.map { game.state.object(it).card }
  def cast(game, name) = game.submit(type: "cast", object: id(game, name, zone: :hand))

  def pay_all(game)
    game.submit(game.legal_options.find { %w[pay_mana activate_mana].include?(it[:type]) }) while game.pending_decision.kind == "pay_cost"
  end

  it "Mudbutton Cursetosser beholds a Goblin from the hand, or costs {2} more (CR 601.2b, 701.4a)" do
    game = board(hand: ["Mudbutton Cursetosser", "Fanatical Firebrand"], battlefield: ["Swamp"])
    cast(game, "Mudbutton Cursetosser")
    expect(game.legal_options).to eq([{ type: "cost_option", option: 0 }, { type: "cancel" }])
    game.submit(type: "cost_option", option: 0)
    game.submit(type: "cost", object: id(game, "Fanatical Firebrand", zone: :hand))
    pay_all(game)
    pass_both(game)
    expect(cards(game, game.state.battlefield)).to include("mudbutton_cursetosser")
    expect(cards(game, alice(game).hand)).to eq(["fanatical_firebrand"])

    game = board(hand: ["Mudbutton Cursetosser"], battlefield: %w[Swamp Swamp])
    expect(game.legal_options.none? { it[:type] == "cast" }).to be(true) # {2}{B} unaffordable, no Goblin
  end

  it "Bogslither's Embrace blights 1 instead of paying {3} (CR 701.68a)" do
    game = board(hand: ["Bogslither's Embrace"], battlefield: ["Swamp", "Swamp", "Fanatical Firebrand"], theirs: ["Stony-Voiced Goblins"])
    cast(game, "Bogslither's Embrace")
    expect(game.legal_options).to eq([{ type: "cost_option", option: 0 }, { type: "cancel" }])
    game.submit(type: "cost_option", option: 0)
    game.submit(type: "target", target: id(game, "Stony-Voiced Goblins", player: "bob"))
    game.submit(game.legal_options.find { it[:type] == "cost" })
    pay_all(game)
    pass_both(game)
    expect(cards(game, game.state.battlefield)).not_to include("stony_voiced_goblins", "fanatical_firebrand")
  end

  it "Titania: discard a card or pay {2} to cast; Ward—Discard a card or pay {2} against Pumpkin Bombardment" do
    game = board(hand: ["Titania, Rugged Rumbler", "Island"], battlefield: %w[Swamp Swamp Swamp])
    cast(game, "Titania, Rugged Rumbler")
    expect(game.legal_options).to eq([{ type: "cost_option", option: 0 }, { type: "cancel" }])

    game = board(hand: ["Pumpkin Bombardment", "Island", "Swamp"], battlefield: %w[Swamp], theirs: ["Titania, Rugged Rumbler"])
    cast(game, "Pumpkin Bombardment")
    game.submit(type: "cost_option", option: 0)
    game.submit(type: "target", target: id(game, "Titania, Rugged Rumbler", player: "bob"))
    game.submit(type: "cost", object: id(game, "Island", zone: :hand))
    pay_all(game)
    pass_both(game) # ward resolves: alice may discard her Swamp
    expect(game.legal_options).to eq([{ type: "pay", option: 0, cost: "Discard a card" }, { type: "decline" }])
    game.submit(game.legal_options.first)
    game.submit(type: "cost", object: id(game, "Swamp", zone: :hand))
    expect(alice(game).hand).to be_empty
    expect(game.state.stack.size).to eq(1)
  end

  it "Piercing Exhale: beholding a Dragon is optional, isn't kicking, and adds surveil 2 (CR 118.8b)" do
    game = board(hand: ["Piercing Exhale", "Stormscale Scion"], battlefield: ["Forest", "Forest", "Fanatical Firebrand"],
                 theirs: ["Stony-Voiced Goblins"])
    cast(game, "Piercing Exhale")
    expect(game.pending_decision.kind).to eq("choose_kicker")
    game.submit(type: "kick")
    game.submit(type: "target", target: id(game, "Fanatical Firebrand"))
    game.submit(type: "target", target: id(game, "Stony-Voiced Goblins", player: "bob"))
    game.submit(type: "cost", object: id(game, "Stormscale Scion", zone: :hand))
    pay_all(game)
    memory = game.state.object(game.state.stack.first).memory
    expect(memory["kicked_with"]).to eq("additional_cost")
    expect(memory).not_to have_key("kicked")
    pass_both(game)
    expect(game.pending_decision.kind).to eq("effect_choice") # surveil 2
  end

  it "Vision of Love: sacrifice an artifact or discard a card, then draw two (CR 118.12)" do
    game = board(hand: ["Vision of Love", "Island"], battlefield: %w[Mountain Mountain])
    cast(game, "Vision of Love")
    pay_all(game)
    pass_both(game)
    expect(game.legal_options).to eq([{ type: "pay", option: 1, cost: "Discard a card" }, { type: "decline" }])
    game.submit(game.legal_options.first)
    game.submit(type: "cost", object: id(game, "Island", zone: :hand))
    expect(alice(game).hand.size).to eq(2)
  end

  it "Hexing Squelcher gives other creatures Ward—Pay 2 life (CR 702.21a)" do
    game = board(hand: ["Pumpkin Bombardment"], battlefield: %w[Swamp Swamp Swamp],
                 theirs: ["Hexing Squelcher", "Stony-Voiced Goblins"])
    cast(game, "Pumpkin Bombardment")
    game.submit(type: "cost_option", option: 1)
    game.submit(type: "target", target: id(game, "Stony-Voiced Goblins", player: "bob"))
    pay_all(game)
    pass_both(game)
    expect(game.legal_options).to eq([{ type: "pay" }, { type: "decline" }])
    game.submit(type: "pay")
    expect(alice(game).life).to eq(18)
  end

  it "The Serpent Society: Ward—Get five poison counters" do
    game = board(hand: ["Pumpkin Bombardment"], battlefield: %w[Swamp Swamp Swamp], theirs: ["The Serpent Society"])
    cast(game, "Pumpkin Bombardment")
    game.submit(type: "cost_option", option: 1)
    game.submit(type: "target", target: id(game, "The Serpent Society", player: "bob"))
    pay_all(game)
    pass_both(game)
    game.submit(type: "pay")
    expect(alice(game).poison).to eq(5)
  end

  it "Theorist's Sanctum enters untapped if a Jace is beheld, tapped otherwise (CR 614.12, 701.4a)" do
    game = board(hand: ["Theorist's Sanctum", "The Theorist, Jace Beleren"])
    game.submit(type: "play_land", object: id(game, "Theorist's Sanctum", zone: :hand))
    jace = id(game, "The Theorist, Jace Beleren", zone: :hand)
    expect(game.legal_options).to eq([{ type: "behold", object: jace }, { type: "enter_tapped" }])
    expect(Enjine::CLI::Text.new(game).option(game.legal_options.first)).to eq("Behold The Theorist, Jace Beleren")
    entry = game.submit(type: "behold", object: jace)
    expect(entry.events.map(&:type)).to include("card_revealed")
    expect(game.state.object(id(game, "Theorist's Sanctum")).tapped).to be(false)

    game = board(hand: ["Theorist's Sanctum"])
    game.submit(type: "play_land", object: id(game, "Theorist's Sanctum", zone: :hand))
    expect(game.legal_options).to eq([{ type: "enter_tapped" }])
    game.submit(type: "enter_tapped")
    expect(game.state.object(id(game, "Theorist's Sanctum")).tapped).to be(true)
  end

  it "Bilbo's Gambit: promising the gift gives the chosen opponent a Treasure first (CR 702.174a, 702.174j)" do
    game = board(hand: ["Vision of Love", "Bilbo's Gambit"], battlefield: %w[Mountain Mountain Plains Plains])
    cast(game, "Vision of Love")
    pay_all(game)
    vision = game.state.stack.first
    cast(game, "Bilbo's Gambit")
    expect(game.pending_decision.kind).to eq("choose_kicker")
    game.submit(type: "kick")
    game.submit(type: "target", target: vision)
    expect(game.legal_options).to eq([{ type: "cost", object: "player:bob" }, { type: "cancel" }])
    game.submit(type: "cost", object: "player:bob")
    pay_all(game)
    gambit = game.state.object(game.state.stack.first)
    expect(gambit.memory).to include("kicked_with" => "gift", "gift" => "player:bob")
    pass_both(game)
    treasure = game.state.battlefield.find { game.state.object(it).card.start_with?("treasure") }
    expect(game.state.object(treasure).controller).to eq(1)
    expect(cards(game, alice(game).hand)).to eq(["vision_of_love"])
    expect(game.legal_options.none? { it[:type] == "cast" }).to be(true) # players can't cast spells this turn
  end

  it "Ironheart gives noncreature spells you cast improvise, not creature spells (CR 702.126a)" do
    game = board(hand: ["Vision of Love", "K'un-Lun Warrior"], battlefield: ["Ironheart, Clever Champion", "Mountain"])
    expect(game.legal_options.select { it[:type] == "cast" }.map { it[:object] }).to eq([id(game, "Vision of Love", zone: :hand)])
    cast(game, "Vision of Love")
    expect(game.legal_options).to include({ type: "improvise", object: id(game, "Ironheart, Clever Champion") })
    game.submit(type: "improvise", object: id(game, "Ironheart, Clever Champion"))
    pay_all(game)
    expect(game.state.stack.size).to eq(1)
    expect(game.catalog.fetch("ironheart_clever_champion").abilities.first.to_s).to eq("Noncreature spells you cast have improvise")
  end

  it "Narset, Jeskai Waymaster: you may discard your hand; if you do, draw a card per spell cast this turn (CR 701.9a)" do
    game = board(hand: ["Vision of Love", "Island", "Swamp"], battlefield: ["Narset, Jeskai Waymaster", "Mountain", "Mountain"])
    cast(game, "Vision of Love")
    pay_all(game)
    pass_both(game)
    game.submit(type: "decline")
    game.submit(option_types(game).include?("pass") ? { type: "pass" } : { type: "done" }) until game.pending_decision.kind == "effect_choice"
    expect(game.state.step).to eq(:end)
    entry = game.submit(type: "yes")
    discarded = entry.events.count { it.type == "zone_changed" && it.to_h["reason"] == "discard" }
    expect(discarded).to eq(2)
    expect(alice(game).hand.size).to eq(1) # one spell cast this turn
  end

  it "Winter, Cursed Rider exiles X artifact cards from the graveyard: X is at most how many there are (CR 601.2b)" do
    game = board(battlefield: ["Winter, Cursed Rider", "Island", "Island", "Swamp", "Swamp"],
                 graveyard: ["Arc Reactor", "Steel Wrecking Ball", "Island"], theirs: ["Stony-Voiced Goblins"])
    game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == id(game, "Winter, Cursed Rider") })
    expect(game.pending_decision.kind).to eq("choose_x")
    expect(game.legal_options.filter_map { it[:value] }).to eq([0, 1, 2])
    game.submit(type: "x", value: 2)
    2.times { game.submit(game.legal_options.find { it[:type] == "cost" }) }
    pay_all(game)
    expect(cards(game, alice(game).graveyard)).to eq(["island"])
    pass_both(game)
    expect(cards(game, game.state.battlefield)).not_to include("stony_voiced_goblins")
  end
end
