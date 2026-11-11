# frozen_string_literal: true

# Real cards that fill set × card type cells of the README's set support table
# (spec/fixtures/cards/real/set_type_coverage.json), written by hand in the card DSL.
RSpec.describe "Real cards: set and card type coverage" do
  let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.cards + CardFixtures.real("set_type_coverage")) }

  def board(hand: [], mine: [], theirs: [], library: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand(*hand)
        mine.each { |card, opts| battlefield card, **(opts || {}) }
        library(*library) unless library.empty?
        library "Island", count: 10
      end
      player("bob") do
        theirs.each { |card, opts| battlefield card, **(opts || {}) }
        library "Island", count: 10
      end
    end
  end

  # Submits `action`, answers later decisions with `answers` in order, and passes until the stack is empty.
  def play(game, action, *answers)
    game.submit(action)
    until game.over? || ((decision = game.pending_decision).kind == "priority" && game.state.stack.empty?)
      next game.submit(type: "pass") if decision.kind == "priority"

      game.submit(answers.shift || raise("no answer for #{decision.kind}: #{game.legal_options}"))
    end
    expect(answers).to be_empty
    game
  end

  def loyalty(game, card, index, *) = play(game, { type: "activate", object: obj_id(game, card), ability: "printed:#{index}" }, *)
  def chars(game, id) = game.instance_variable_get(:@engine).chars(id)
  def life(game, player) = game.state.players[game.names.index(player)].life
  def counters(game, card) = game.state.object(obj_id(game, card)).counters
  def hand(game) = game.state.players[0].hand.map { game.state.object(it).card }

  it "every card validates and keeps its rarity and printing" do
    CardFixtures.real("set_type_coverage").each { expect(Enjine::CardDefinition.from_h(it).to_h).to include("printing", "rarity") }
  end

  it "A.I.M. Labs (msh) enters tapped, gains 1 life, and taps for {U} or {B}" do
    game = board(hand: ["A.I.M. Labs"])
    play(game, type: "play_land", object: obj_id(game, "A.I.M. Labs", zone: :hand, player: "alice"))
    expect([game.state.object(obj_id(game, "A.I.M. Labs")).tapped, life(game, "alice")]).to eq([true, 21])
  end

  it "Sandsteppe Citadel (tdm) enters tapped and makes one of three colors" do
    game = board(hand: ["Sandsteppe Citadel"])
    play(game, type: "play_land", object: obj_id(game, "Sandsteppe Citadel", zone: :hand, player: "alice"))
    expect(game.state.object(obj_id(game, "Sandsteppe Citadel")).tapped).to be(true)
  end

  it "Professor Dellian Fel (sos): +2 gains 3 life; -3 destroys target creature" do
    game = board(mine: ["Professor Dellian Fel"], theirs: ["Grizzly Bears"])
    loyalty(game, "Professor Dellian Fel", 0)
    expect([life(game, "alice"), counters(game, "Professor Dellian Fel")["loyalty"]]).to eq([23, 7])
    game = board(mine: ["Professor Dellian Fel"], theirs: ["Grizzly Bears"])
    loyalty(game, "Professor Dellian Fel", 2, { type: "target", target: obj_id(game, "Grizzly Bears") })
    expect(game.state.battlefield.map { game.state.object(it).card }).to eq(["professor_dellian_fel"])
  end

  it "Tezzeret, Cruel Captain (eoe): 0 untaps an artifact creature and gives it a +1/+1 counter" do
    golem = { "name" => "Test Golem", "mana_cost" => "{2}", "types" => %w[artifact creature], "power" => 2, "toughness" => 2 }
    cat = Enjine::Catalog.from_definitions(CardFixtures.cards + CardFixtures.real("set_type_coverage") + [golem])
    game = build_game(cat) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Tezzeret, Cruel Captain"
        battlefield "Test Golem", tapped: true
      end
      player("bob")
    end
    loyalty(game, "Tezzeret, Cruel Captain", 1, { type: "target", target: obj_id(game, "Test Golem") })
    golem_obj = game.state.object(obj_id(game, "Test Golem"))
    expect([golem_obj.tapped, golem_obj.counters["+1/+1"]]).to eq([false, 1])
  end

  it "Chandra, Spark Hunter (dft): 0 creates a 3/2 Vehicle artifact token with crew 1" do
    game = board(mine: ["Chandra, Spark Hunter"])
    loyalty(game, "Chandra, Spark Hunter", 2)
    engine = game.instance_variable_get(:@engine)
    token = game.state.battlefield.find { engine.token?(game.state.object(it)) }
    expect([chars(game, token).subtypes, chars(game, token).creature?]).to eq([[:vehicle], false])
  end
end
