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

  it "Luminollusk and Shimmercreep: X is the number of colors among permanents you control" do
    game = board(hand: ["Shimmercreep"], battlefield: ["The Kingpin of Crime", "Luminollusk"], mana: { B: 1, C: 4 })
    cast(game, "Shimmercreep", { type: "decline" }) # Kingpin's extort
    expect([life(game, "alice"), life(game, "bob")]).to eq([23, 17]) # white, black, green
  end
end
