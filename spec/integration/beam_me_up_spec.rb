# frozen_string_literal: true

# Beam me up: CR 702.196a-b (2026-11-06 rules).
RSpec.describe "Beam me up (CR 702.196)" do
  let(:shot) do
    { "name" => "Phase Shot", "mana_cost" => "{1}{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                     "effects" => [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }] } },
                      { "beam_me_up" => { "cost" => "{2}{R}" } }] }
  end
  let(:engineer) do
    { "name" => "Teleport Engineer", "mana_cost" => "{1}{U}{U}", "types" => ["creature"], "power" => 2, "toughness" => 3,
      "abilities" => ["grants_beam_me_up"] }
  end
  let(:anchored) do
    { "name" => "Anchored Sentinel", "mana_cost" => "{1}{W}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "keywords" => ["cant_be_beamed_up"] }
  end
  let(:catalog) { catalog_with(shot, engineer, anchored) }

  it "can't return a creature that can't be beamed up (CR 702.196b); a granting creature may pay another beam" do
    game = board(alice_board: ["Anchored Sentinel", "Mountain", "Mountain", "Mountain"])
    expect(game.legal_options).not_to include(a_hash_including(type: "cast"))
    game = board(alice_board: ["Anchored Sentinel", "Teleport Engineer", "Mountain", "Mountain", "Mountain"])
    game.submit(type: "cast", object: card_in(game, :graveyard), via: "beam:printed:1")
    game.submit(type: "target", target: bob_ref(game))
    expect(game.legal_options).to eq([{ type: "cost", object: obj_id(game, "Teleport Engineer") }, { type: "cancel" }])
  end

  def board(step: :precombat_main, alice_board: ["Grizzly Bears", "Mountain", "Mountain", "Mountain"], graveyard: ["Phase Shot"],
            bob_board: [])
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice") do
        alice_board.each { battlefield it }
        graveyard(*graveyard)
        library "Forest", count: 5
      end
      player("bob") do
        bob_board.each { battlefield it }
        hand "Counterspell"
        library "Forest", count: 5
      end
    end
  end

  def pay!(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def card_in(game, zone, player = "alice") = ids_in(game, player, zone).find { game.state.object(it).card == "phase_shot" }
  def bob_ref(game) = "player:#{game.names[1]}"

  it "casts from the graveyard for the beam cost plus returning a creature, then exiles the spell (CR 702.196a)" do
    game = board
    card = card_in(game, :graveyard)
    bears = obj_id(game, "Grizzly Bears")
    option = { type: "cast", object: card, via: "beam:printed:1" }
    expect(game.legal_options).to include(option)
    game.submit(option)
    game.submit(type: "target", target: bob_ref(game))
    expect(game.pending_decision).to have_attributes(kind: "choose_cost",
                                                     details: { "cost" => "Return a creature you control to its owner's hand" })
    expect(game.legal_options).to eq([{ type: "cost", object: bears }, { type: "cancel" }])
    game.submit(type: "cost", object: bears)
    expect(game.state.battlefield).to include(bears) # returned only as the spell becomes cast (CR 601.2h)
    expect(game.pending_decision.details["remaining"]).to eq("{2}{R}")
    pay!(game)
    expect(ids_in(game, "alice", :hand).map { game.state.object(it).card }).to eq(["grizzly_bears"])
    pass_both(game)
    expect(game.view_for(:observer)["players"][1]["life"]).to eq(18)
    expect(game.state.exile.map { game.state.object(it).card }).to eq(["phase_shot"])
    expect(ids_in(game, "alice", :graveyard)).to be_empty
  end

  it "exiles a beamed-up spell that is countered instead of putting it into the graveyard" do
    game = board(bob_board: %w[Island Island])
    game.submit(type: "cast", object: card_in(game, :graveyard), via: "beam:printed:1")
    game.submit(type: "target", target: bob_ref(game))
    game.submit(type: "cost", object: obj_id(game, "Grizzly Bears"))
    pay!(game)
    game.submit(type: "pass")
    spell = game.state.stack.first
    game.submit(type: "cast", object: ids_in(game, "bob", :hand).first)
    game.submit(type: "target", target: spell)
    pay!(game)
    pass_both(game)
    expect(game.state.exile.map { game.state.object(it).card }).to eq(["phase_shot"])
  end

  it "cancelling after choosing the creature leaves it on the battlefield and the card in the graveyard" do
    game = board
    card = card_in(game, :graveyard)
    bears = obj_id(game, "Grizzly Bears")
    game.submit(type: "cast", object: card, via: "beam:printed:1")
    game.submit(type: "target", target: bob_ref(game))
    game.submit(type: "cost", object: bears)
    game.submit(type: "cancel")
    expect(game.state.battlefield).to include(bears)
    expect(ids_in(game, "alice", :graveyard)).to eq([card])
  end

  it "isn't offered without a creature to return, or a sorcery outside sorcery timing" do
    game = board(alice_board: %w[Mountain Mountain Mountain])
    expect(game.legal_options).not_to include(a_hash_including(type: "cast"))
    combat = board(step: :beginning_of_combat)
    expect(combat.legal_options).not_to include(a_hash_including(type: "cast"))
  end

  it "a permanent can grant beam me up for the card's mana cost during its controller's main phase; it can't be returned (CR 702.196b)" do
    game = board(alice_board: ["Teleport Engineer", "Grizzly Bears", "Mountain"], graveyard: ["Lightning Bolt", "Grizzly Bears"])
    bolt = ids_in(game, "alice", :graveyard).first
    engineer = obj_id(game, "Teleport Engineer")
    option = { type: "cast", object: bolt, via: "beam_granted:#{engineer}:printed:0" }
    expect(game.legal_options.select { it[:type] == "cast" }).to eq([option]) # not the creature card
    game.submit(option)
    game.submit(type: "target", target: bob_ref(game))
    expect(game.legal_options).to eq([{ type: "cost", object: obj_id(game, "Grizzly Bears") }, { type: "cancel" }])
    game.submit(type: "cost", object: obj_id(game, "Grizzly Bears"))
    expect(game.pending_decision.details["remaining"]).to eq("{R}")
    combat = board(step: :beginning_of_combat, alice_board: ["Teleport Engineer", "Grizzly Bears", "Mountain"],
                   graveyard: ["Lightning Bolt"])
    expect(combat.legal_options).not_to include(a_hash_including(type: "cast"))
  end

  it "asks again when the chosen creature left the battlefield before the spell became cast" do
    game = board
    bears = obj_id(game, "Grizzly Bears")
    game.submit(type: "cast", object: card_in(game, :graveyard), via: "beam:printed:1")
    game.submit(type: "target", target: bob_ref(game))
    game.submit(type: "cost", object: bears)
    game.state.battlefield.delete(bears) # gone some other way (a sacrifice for mana)
    game.state.players[0].graveyard << bears
    game.state.object(bears).zone = :graveyard
    game.submit(game.legal_options.find { it[:type] == "activate_mana" })
    expect(game.pending_decision.kind).to eq("choose_cost")
  end
end
