# frozen_string_literal: true

require "enjine/sets"

# Converted Star Trek cards that use hybrid mana, chosen costs, kicker, activation limits, modes,
# payments and ward, played from lib/enjine/sets/trk.json.
RSpec.describe "Star Trek cards: costs, kicker, modes, payments and ward" do
  let(:catalog) { Enjine::Catalog.from_definitions(Enjine::CardPool::Core.cards + Enjine::Sets.load("trk").cards.map(&:to_h)) }

  def board(alice: {}, bob: {}, active: "alice")
    build_game(catalog) do
      turn 3, active: active, step: :precombat_main
      %w[alice bob].zip([alice, bob]).each do |name, spec|
        player(name, life: spec.fetch(:life, 20)) do
          hand(*spec[:hand]) if spec[:hand]
          battlefield(*spec[:field]) if spec[:field]
          graveyard(*spec[:graveyard]) if spec[:graveyard]
          library "Forest", count: 5
        end
      end
    end
  end

  def pay_all(game)
    while game.pending_decision&.kind == "pay_cost"
      pay = game.legal_options.find { it[:type] == "pay_mana" }
      game.submit(pay || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def card_id(game, name, player: "alice", zone: :hand)
    slug = Enjine::CardDefinition.slug(name)
    ids_in(game, player, zone).find { game.state.object(it).card == slug } or raise "no #{name}"
  end

  it "Cleveland Booker, Empath: castable with red or green for its hybrid symbols" do
    game = board(alice: { hand: ["Cleveland Booker, Empath"], field: %w[Forest Forest Forest Forest] })
    game.submit(type: "cast", object: card_id(game, "Cleveland Booker, Empath"))
    expect(game.pending_decision.details["remaining"]).to eq("{2}{R/G}{R/G}")
    pay_all(game)
    pass_both(game)
    expect(game.state.battlefield.map { game.state.object(it).card }).to include("cleveland_booker_empath")
  end

  it "Highly Illogical: kicked, it counters a spell of any mana value" do
    game = board(alice: { hand: ["Hill Giant"], field: %w[Mountain Mountain Mountain Mountain] },
                 bob: { hand: ["Highly Illogical"], field: %w[Island Island Island Island] })
    game.submit(type: "cast", object: card_id(game, "Hill Giant"))
    pay_all(game)
    game.submit(type: "pass")
    giant = game.state.stack.first
    game.submit(type: "cast", object: card_id(game, "Highly Illogical", player: "bob"))
    expect(game.legal_options).to eq([{ type: "kick" }, { type: "cancel" }])
    game.submit(type: "kick")
    game.submit(type: "target", target: giant)
    pay_all(game)
    pass_both(game)
    expect(game.state.players[0].graveyard.size).to eq(1)
  end

  it "Gowron, Eager for Battle: sacrificing a Klingon draws a card" do
    game = board(alice: { field: ["Gowron, Eager for Battle", "The Duras Sisters"] })
    game.submit(type: "activate", object: obj_id(game, "Gowron, Eager for Battle"), ability: "printed:1")
    game.submit(type: "cost", object: obj_id(game, "The Duras Sisters"))
    expect(game.state.pending_triggers.size).to eq(2) # Gowron's counter and the Sisters' token
    hand = ids_in(game, "alice", :hand).size
    game.submit(game.legal_options.first) # order the two triggers
    pass_both(game, 3)
    expect(ids_in(game, "alice", :hand).size).to eq(hand + 1)
    expect(game.state.players[0].life).to eq(19)
    expect(game.state.object(obj_id(game, "Gowron, Eager for Battle")).counters).to eq("+1/+1" => 1)
  end

  it "Collation Trimatrix taps three artifact creatures; Relentless Drednok activates from the graveyard" do
    game = board(alice: { field: ["Collation Trimatrix", "Lieutenant Commander Data", "Bastion Golem", "Swamp", "Swamp", "Swamp"],
                          graveyard: ["Relentless Drednok"] })
    game.submit(type: "activate", object: obj_id(game, "Collation Trimatrix"), ability: "printed:0")
    3.times { game.submit(game.legal_options.find { it[:type] == "cost" }) }
    pass_both(game)
    drednok = card_id(game, "Relentless Drednok", zone: :graveyard)
    game.submit(type: "activate", object: drednok, ability: "printed:0")
    pay_all(game)
    expect(game.state.exile.size).to eq(1)
    pass_both(game)
    expect(game.state.players[0].life).to eq(18)
  end

  it "DOT-7 Repair Squad untaps once each turn, only as a sorcery" do
    game = board(alice: { field: ["DOT-7 Repair Squad", "Plains", "Plains", "Plains", "Plains"] })
    squad = obj_id(game, "DOT-7 Repair Squad")
    game.state.object(squad).tapped = true
    game = Enjine::Game.import({ "state" => game.state.to_h }, catalog: catalog)
    game.submit(type: "activate", object: squad, ability: "printed:0")
    game.submit(type: "target", target: squad)
    pay_all(game)
    pass_both(game)
    expect(game.state.object(squad).tapped).to be(false)
    expect(game.legal_options.none? { it[:type] == "activate" }).to be(true)
  end

  it "Cetacean Ops has ward {1}; Wesley Crusher chooses two modes" do
    game = board(alice: { hand: ["Lightning Bolt"], field: ["Mountain"] }, bob: { field: ["Cetacean Ops"] })
    game.submit(type: "cast", object: card_id(game, "Lightning Bolt"))
    game.submit(type: "target", target: obj_id(game, "Cetacean Ops"))
    pay_all(game)
    pass_both(game)
    expect(game.legal_options).to eq([{ type: "decline" }])
    game.submit(type: "decline")
    expect(game.state.stack).to be_empty

    wes = board(alice: { hand: ["Wesley Crusher, Starfleet Cadet"], field: %w[Island Island Island Island] },
                bob: { field: ["Grizzly Bears"] })
    wes.submit(type: "cast", object: card_id(wes, "Wesley Crusher, Starfleet Cadet"))
    pay_all(wes)
    pass_both(wes)
    expect(wes.pending_decision).to have_attributes(kind: "choose_mode", details: { "choose" => 2, "chosen" => 0 })
    wes.submit(type: "mode", mode: 1)
    wes.submit(type: "mode", mode: 3)
    wes.submit(type: "target", target: obj_id(wes, "Grizzly Bears"))
    wes.submit(type: "target", target: "player:alice")
    pass_both(wes)
    expect(ids_in(wes, "bob", :hand).size).to eq(1)
    expect(wes.pending_decision.kind).to eq("effect_choice") # alice discards two
  end

  it "Captain James T. Kirk may choose more modes with an empty hand" do
    game = board(alice: { hand: ["Captain James T. Kirk"], field: %w[Mountain Mountain Mountain] })
    game.submit(type: "cast", object: card_id(game, "Captain James T. Kirk"))
    pay_all(game)
    pass_both(game)
    expect(game.pending_decision.details).to eq("choose" => 3, "min" => 1, "chosen" => 0)
    game.submit(type: "mode", mode: 1)
    game.submit(type: "mode", mode: 2)
    game.submit(type: "done")
    pass_both(game)
    expect(game.state.battlefield.count { game.state.object(it).card.include?("officer") }).to eq(1)
  end
end
