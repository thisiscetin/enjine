# frozen_string_literal: true

# Real cards that need the set mechanics of current Standard (spec/fixtures/cards/real/set_mechanics.json):
# power-up (Marvel Super Heroes), teamwork, extort, increment (Secrets of Strixhaven) and colors among
# permanents (Lorwyn Eclipsed). Basic lands come from the other real-card files.
RSpec.describe "Real cards: set mechanics" do
  let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.real_cards) }

  def board(hand: [], battlefield: [], theirs: [], mana: {})
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: mana) do
        hand(*hand)
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
      when "pay_cost" then game.submit(pay_option(game))
      else game.submit(answers.shift || raise("no answer for #{decision.kind}: #{game.legal_options}"))
      end
    end
    expect(answers).to be_empty
    game
  end

  # Pays from the pool, keeping black mana for extort while other mana can pay.
  def pay_option(game)
    pays = game.legal_options.select { it[:type] == "pay_mana" }
    pays.find { it[:mana] != "B" } || pays.first || raise("can't pay")
  end

  def hand_id(game, card) = ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) }
  def cast(game, card, *) = play(game, { type: "cast", object: hand_id(game, card) }, *)
  def life(game, name) = game.state.players[game.names.index(name)].life

  it "Aerial Doombot: power-up costs {5} the turn it entered, and only once" do
    game = board(hand: ["Aerial Doombot"], mana: { U: 1, C: 5 })
    cast(game, "Aerial Doombot")
    bot = obj_id(game, "Aerial Doombot")
    option = { type: "activate", object: bot, ability: "printed:0" }
    play(game, option)
    expect(game.state.object(bot).counters["+1/+1"]).to eq(3)
    expect(game.legal_options).not_to include(option)
  end

  it "Brave Brawler: power-up costs its full {4}{W} on a later turn" do
    game = board(battlefield: ["Brave Brawler"], mana: { W: 1, C: 3 })
    expect(game.legal_options).not_to include(type: "activate", object: obj_id(game, "Brave Brawler"), ability: "printed:0")
  end

  it "Cruel Alliance: with teamwork, any creature can be exiled and you gain 3 life" do
    game = board(hand: ["Cruel Alliance"], battlefield: ["Hungry Graffalon"], theirs: ["Shimmercreep"], mana: { B: 1, C: 2 })
    creep = obj_id(game, "Shimmercreep")
    play(game, { type: "cast", object: hand_id(game, "Cruel Alliance") }, { type: "kick" }, { type: "target", target: creep },
         { type: "cost", object: obj_id(game, "Hungry Graffalon") })
    expect(game.state.exile).to eq([game.state.exile.first])
    expect(life(game, "alice")).to eq(23)
  end

  it "The Kingpin of Crime: extort drains 1 when you pay {W/B}" do
    game = board(hand: ["Pensive Professor"], battlefield: ["The Kingpin of Crime"], mana: { U: 2, C: 1, B: 1 })
    cast(game, "Pensive Professor", { type: "pay" })
    expect([life(game, "alice"), life(game, "bob")]).to eq([21, 19])
  end

  it "Pensive Professor: increment puts a counter on it, which draws a card" do
    game = board(hand: ["Hungry Graffalon"], battlefield: ["Pensive Professor"], mana: { G: 1, C: 3 })
    cast(game, "Hungry Graffalon")
    expect(game.state.object(obj_id(game, "Pensive Professor")).counters["+1/+1"]).to eq(1)
    expect(game.state.players[0].hand.size).to eq(1)
  end

  it "Fíli the Pathfinder: a third legendary or artifact gives you an enduring story (storied), so creatures get +1/+1" do
    game = board(hand: ["Fíli the Pathfinder"], battlefield: ["Ori, Keeper of Songs", "Skateboard"], mana: { W: 1, C: 3 })
    ori = obj_id(game, "Ori, Keeper of Songs")
    engine = game.instance_variable_get(:@engine)
    expect(engine.power(engine.object(ori))).to eq(3)
    cast(game, "Fíli the Pathfinder")
    expect(game.view_for(:observer)["players"][0]["designations"]).to eq(["enduring_story"])
    expect([engine.power(engine.object(ori)), engine.toughness(engine.object(ori))]).to eq([5, 4])
    expect(engine.chars(engine.object(ori)).keyword?(:vigilance)).to be(true)
    dwarf = game.state.battlefield.find { game.state.object(it).card.start_with?("dwarf") }
    expect(engine.power(engine.object(dwarf))).to eq(3)
  end

  it "Bombur, Gentle Dreamer: doesn't untap unless you have an enduring story" do
    game = build_game(catalog) do
      turn 2, active: "bob", step: :end
      player("alice") do
        battlefield "Bombur, Gentle Dreamer", tapped: true
        library "Island", count: 5
      end
      player("bob") { library "Swamp", count: 5 }
    end
    skip_to(game, :upkeep, turn: 3)
    expect(game.state.object(obj_id(game, "Bombur, Gentle Dreamer")).tapped).to be(true)
    engine = game.instance_variable_get(:@engine)
    engine.gain_designation!(0, "enduring_story")
    skip_to(game, :upkeep, turn: 5)
    expect(game.state.object(obj_id(game, "Bombur, Gentle Dreamer")).tapped).to be(false)
  end

  it "Thunder Magic: tiered, the chosen mode's cost is paid in addition (CR 702.183a)" do
    game = board(hand: ["Thunder Magic"], theirs: ["Luminollusk"], mana: { R: 1, C: 3 })
    creep = obj_id(game, "Luminollusk")
    game.submit(type: "cast", object: hand_id(game, "Thunder Magic"))
    expect(game.legal_options.select { it[:type] == "mode" }).to eq([{ type: "mode", mode: 0 }, { type: "mode", mode: 1 }])
    play(game, nil, { type: "mode", mode: 1 }, { type: "target", target: creep })
    expect(game.state.players[1].graveyard.size).to eq(1)
    expect(game.state.players[0].mana_pool.values.sum).to eq(0)
  end

  it "Fire Magic: the {0} tier costs only its mana cost" do
    game = board(hand: ["Fire Magic"], battlefield: ["Hungry Graffalon"], mana: { R: 1, C: 2 })
    play(game, { type: "cast", object: hand_id(game, "Fire Magic") }, { type: "mode", mode: 0 })
    expect(game.state.object(obj_id(game, "Hungry Graffalon")).damage).to eq(1)
    expect(game.state.players[0].mana_pool[:C]).to eq(2)
  end

  it "Leader's Talent: class levels are gained in order, as a sorcery, and add their abilities (CR 717.2a)" do
    game = board(battlefield: ["Leader's Talent", "Hungry Graffalon"], hand: ["Brave Brawler"], mana: { W: 9 })
    talent = obj_id(game, "Leader's Talent")
    level2 = { type: "activate", object: talent, ability: "printed:1" }
    level3 = { type: "activate", object: talent, ability: "printed:2" }
    expect(game.legal_options).to include(level2)
    expect(game.legal_options).not_to include(level3)
    play(game, level2)
    engine = game.instance_variable_get(:@engine)
    expect(engine.class_level(engine.object(talent))).to eq(2)
    expect(game.legal_options).not_to include(level2)
    play(game, level3)
    cast(game, "Brave Brawler") # level 3: whenever you cast a spell, a +1/+1 counter on each creature you control
    expect(game.state.object(obj_id(game, "Hungry Graffalon")).counters["+1/+1"]).to eq(1)
    expect(game.history.flat_map(&:events).map(&:type)).to include("class_level_changed")
  end

  it "Luminollusk and Shimmercreep: X is the number of colors among permanents you control" do
    game = board(hand: ["Shimmercreep"], battlefield: ["The Kingpin of Crime", "Luminollusk"], mana: { B: 1, C: 4 })
    cast(game, "Shimmercreep", { type: "decline" }) # Kingpin's extort
    expect([life(game, "alice"), life(game, "bob")]).to eq([23, 17]) # white, black, green
  end
end
