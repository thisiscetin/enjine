# frozen_string_literal: true

# Real Standard cards that need bending (Avatar: The Last Airbender) and saddle (Aetherdrift), written by hand
# in the card DSL (spec/fixtures/cards/real/bending_and_mounts.json). Each card is played and its own effect
# checked.
RSpec.describe "Real cards: bending and mounts" do
  let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.cards + CardFixtures.real("bending_and_mounts")) }

  def board(hand: [], mine: [], theirs: [], pool: {}, step: :precombat_main)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: pool) do
        hand(*hand) unless hand.empty?
        mine.each { battlefield(it) }
        library "Island", "Forest", count: 4
      end
      player("bob") do
        battlefield(*theirs) unless theirs.empty?
        library "Island", count: 8
      end
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def find(game, card, zone = :battlefield) = game.state.public_send(zone).find { game.state.object(it).card == card }
  def hand_of(game) = ids_in(game, "alice", :hand)

  def cast(game, card, *targets)
    game.submit(type: "cast", object: hand_of(game).find { game.state.object(it).card == card })
    targets.each { game.submit(type: "target", target: it) }
  end

  def pay(game)
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
  end

  it "Earthbending Lesson: earthbend 4 on a land you control (tla 176)" do
    game = board(hand: ["Earthbending Lesson"], mine: ["Forest"], pool: { G: 4 })
    forest = find(game, "forest")
    cast(game, "earthbending_lesson", forest)
    pay(game)
    pass_both(game)
    c = engine(game).chars(game.state.object(forest))
    expect([c.creature?, c.land?, c.power, c.keyword?(:haste)]).to eq([true, true, 4, true])
  end

  it "Badgermole: earthbends 2 as it enters; creatures with +1/+1 counters have trample (tla 166)" do
    game = board(hand: ["Badgermole"], mine: ["Forest"], pool: { G: 5 })
    forest = find(game, "forest")
    cast(game, "badgermole")
    pay(game)
    pass_both(game) # Badgermole resolves; its trigger targets
    game.submit(type: "target", target: forest) if game.pending_decision.kind == "choose_target"
    pass_both(game)
    expect(engine(game).chars(game.state.object(forest)).keyword?(:trample)).to be(true)
    expect(engine(game).chars(game.state.object(find(game, "badgermole"))).keyword?(:trample)).to be(false)
  end

  it "Geyser Leaper: waterbend {4} with tapped creatures and mana, then loot (tla 52)" do
    game = board(mine: ["Geyser Leaper", "Grizzly Bears", "Hill Giant"], pool: { U: 2 })
    leaper = find(game, "geyser_leaper")
    game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == leaper })
    game.submit(type: "waterbend", object: leaper)
    game.submit(type: "waterbend", object: find(game, "grizzly_bears"))
    pay(game)
    pass_both(game)
    game.submit(game.legal_options.first) while game.pending_decision.kind == "effect_choice"
    expect(ids_in(game, "alice", :graveyard).size).to eq(1)
    expect(game.state.object(leaper).tapped).to be(true)
  end

  it "Benevolent River Spirit: waterbend {5} as an additional cost (tla 45)" do
    game = board(hand: ["Benevolent River Spirit"], mine: ["Grizzly Bears", "Hill Giant", "Forest", "Forest", "Forest"],
                 pool: { U: 2 })
    expect(game.legal_options).to include(a_hash_including(type: "cast"))
    cast(game, "benevolent_river_spirit")
    game.submit(type: "waterbend", object: find(game, "grizzly_bears"))
    game.submit(type: "waterbend", object: find(game, "hill_giant"))
    game.state.battlefield.select { game.state.object(it).card == "forest" }.each do |land|
      game.submit(type: "activate_mana", object: land, ability: mana_ref(game, land))
    end
    pay(game)
    expect(game.state.stack.size).to eq(1)
  end

  it "Airbending Lesson: the owner may recast the airbent permanent for {2} (tla 8)" do
    game = board(hand: ["Airbending Lesson"], theirs: ["Hill Giant"], pool: { W: 3 })
    cast(game, "airbending_lesson", find(game, "hill_giant"))
    pay(game)
    pass_both(game)
    giant = find(game, "hill_giant", :exile)
    expect(giant).not_to be_nil
    expect(hand_of(game).size).to eq(1)
    expect(engine(game).play_methods(1, giant).first).to include("alt" => { "cost" => "{2}" })
  end

  it "Gilded Ghoda: saddle 1, then attacking while saddled makes a Treasure (dft 130)" do
    game = board(mine: ["Gilded Ghoda", "Grizzly Bears"])
    ghoda = find(game, "gilded_ghoda")
    game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == ghoda })
    game.submit(type: "cost", object: find(game, "grizzly_bears"))
    game.submit(type: "done") if game.legal_options.include?({ type: "done" })
    pass_both(game)
    skip_to(game, :beginning_of_combat)
    pass_both(game)
    game.submit(type: "attack", object: ghoda, target: "player:bob")
    game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
    pass_both(game)
    expect(game.state.battlefield.map { engine(game).definition(game.state.object(it)).name }).to include("Treasure")
  end
end
