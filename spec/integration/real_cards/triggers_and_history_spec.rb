# frozen_string_literal: true

# Real cards whose mechanics are triggers, turn history and the stack (spec/fixtures/cards/real/triggers_and_history.json):
# what happened last turn, playing lands from other zones, entering from exile, amounts "this way" through a "may",
# tapping for a teamwork cost, choosing new targets for a spell, and copying the ability that triggered or was
# activated. Test cards stand in for the spells they interact with.
RSpec.describe "Real cards: triggers, turn history and the stack" do
  let(:test_cards) do
    [{ "name" => "Test Shock", "mana_cost" => "{R}", "types" => ["instant"],
       "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                      "effects" => [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }] } }] },
     { "name" => "Test Lesson", "mana_cost" => "{U}", "types" => ["sorcery"], "subtypes" => ["lesson"],
       "abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 1 } }] } }] },
     { "name" => "Test Recollection", "mana_cost" => "{U}", "types" => ["sorcery"],
       "abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 1 } }] } }, { "flashback" => { "cost" => "{U}" } }] },
     { "name" => "Test Coin", "mana_cost" => "{U}", "types" => ["instant"],
       "abilities" => [{ "spell" => { "effects" => [{ "flip_coins" => {} },
                                                    { "draw" => { "amount" => 1,
                                                                  "if" => { "amount" => { "this_way" => 0 }, "at_least" => 1 } } }] } }] },
     { "name" => "Test Crucible", "mana_cost" => "{1}", "types" => ["artifact"],
       "abilities" => [{ "play_from" => { "zone" => "graveyard", "cards" => { "types" => ["land"] }, "play" => "play" } }] },
     { "name" => "Test Flicker", "mana_cost" => "{W}", "types" => ["instant"],
       "abilities" => [{ "spell" => { "targets" => [{ "creature" => { "controller" => "you" } }],
                                      "effects" => [{ "exile" => { "to" => { "target" => 0 } } },
                                                    { "return_to_battlefield" => { "to" => { "result" => 0 } } }] } }] }]
  end
  let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.real_cards + test_cards) }

  def board(hand: [], battlefield: [], graveyard: [], exile: [], theirs: [], their_hand: [], mana: {}, life: 20, their_life: 20,
            step: :precombat_main, library: ["Island"] * 10)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana, life: life) do
        hand(*hand)
        graveyard(*graveyard)
        exile(*exile)
        library(*library)
        battlefield.each { |card, opts| battlefield card, **(opts || {}) }
      end
      player("bob", life: their_life) do
        hand(*their_hand)
        library "Swamp", count: 10
        theirs.each { |card, opts| battlefield card, **(opts || {}) }
      end
    end
  end

  # Submits `action`, answers further decisions with `answers` (options or blocks taking the game), pays from the
  # pool and passes until the stack is empty.
  def play(game, action, *answers)
    game.submit(action) if action
    until game.over? || ((decision = game.pending_decision).kind == "priority" && game.state.stack.empty?)
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { it[:type] == "pay_mana" } || raise("can't pay"))
      else
        answer = answers.shift or raise "no answer for #{decision.kind}: #{game.legal_options}"
        game.submit(answer.respond_to?(:call) ? answer.call(game) : answer)
      end
    end
    expect(answers).to be_empty
    game
  end

  def cast(game, card, *, zone: :hand) = play(game, { type: "cast", object: obj_id(game, card, zone: zone, player: "alice") }, *)
  def activate(game, card, *, ability: "printed:1") = play(game, { type: "activate", object: obj_id(game, card), ability: ability }, *)
  def target(ref) = { type: "target", target: ref }
  def life(game, name) = game.state.players[game.names.index(name)].life
  def counters(game, card, kind = "+1/+1") = game.state.object(obj_id(game, card)).counters[kind].to_i
  def events(game) = game.history_for(:observer).flat_map { it["events"] }
  def yes = { type: "yes" }

  describe "Command the Stage: what happened last turn (CR 500.1, 120.2b)" do
    it "returns to its owner's hand at the next upkeep after an opponent was dealt noncombat damage" do
      game = board(hand: ["Test Shock"], graveyard: ["Command the Stage"], mana: { R: 1 })
      cast(game, "Test Shock", target("player:bob"))
      skip_to(game, :upkeep, turn: 4)
      play(game, nil)
      expect(ids_in(game, "alice", :hand).map { game.state.object(it).card }).to include("command_the_stage")
    end

    it "stays in the graveyard when nobody was dealt noncombat damage last turn, even if they were earlier" do
      game = board(hand: ["Test Shock"], graveyard: ["Command the Stage"], mana: { R: 1 }, step: :end)
      engine = game.instance_variable_get(:@engine)
      engine.last_turn_log(1)["noncombat_damage"] = 3 # turn 2's damage: two turns ago once turn 4 begins
      skip_to(game, :upkeep, turn: 4)
      play(game, nil)
      expect(ids_in(game, "alice", :graveyard).size).to eq(1)
    end

    it "keeps the previous turn's log through export and import" do
      game = board(hand: ["Test Shock"], mana: { R: 1 })
      cast(game, "Test Shock", target("player:bob"))
      skip_to(game, :upkeep, turn: 4)
      copy = Enjine::Game.import(game.export, catalog: catalog)
      expect(copy.state.players[1].last_turn_log).to include("noncombat_damage" => 2)
    end

    it "puts a counter on each Wizard token, then creates a Cadet" do
      game = board(hand: ["Command the Stage", "Command the Stage"], mana: { R: 6 })
      2.times { cast(game, "Command the Stage") }
      cadets = game.state.battlefield.map { game.state.object(it) }
      expect(cadets.map { it.counters["+1/+1"].to_i }.sort).to eq([0, 1])
    end
  end

  describe "playing lands (CR 305.1)" do
    it "The Endstone draws for each land played and spell cast, and sets your life to 10 at your end step" do
      game = board(hand: ["Island", "Test Lesson"], battlefield: ["The Endstone"], mana: { U: 1 })
      play(game, { type: "play_land", object: obj_id(game, "Island", zone: :hand, player: "alice") })
      cast(game, "Test Lesson")
      expect(ids_in(game, "alice", :hand).size).to eq(3) # two drawn by the Endstone, one by the Lesson
      skip_to(game, :end)
      play(game, nil)
      expect(life(game, "alice")).to eq(10)
    end

    it "Shadow of the Goblin deals 1 damage for a land played or a spell cast from anywhere other than the hand" do
      game = board(hand: ["Island"], battlefield: ["Shadow of the Goblin"])
      play(game, { type: "play_land", object: obj_id(game, "Island", zone: :hand, player: "alice") })
      expect(life(game, "bob")).to eq(20)
      game = board(graveyard: ["Island", "Test Recollection"], battlefield: ["Shadow of the Goblin", "Test Crucible"], mana: { U: 1 })
      land = obj_id(game, "Island", zone: :graveyard, player: "alice")
      play(game, game.legal_options.find { it[:type] == "play_land" && it[:object] == land })
      expect(life(game, "bob")).to eq(19)
      play(game, game.legal_options.find do
        it[:type] == "cast" && it[:object] == obj_id(game, "Test Recollection", zone: :graveyard, player: "alice")
      end)
      expect(life(game, "bob")).to eq(18)
    end

    it "Shadow of the Goblin loots at the beginning of your first main phase" do
      game = board(hand: ["Island"], battlefield: ["Shadow of the Goblin"], step: :draw)
      skip_to(game, :precombat_main)
      play(game, nil, ->(g) { g.legal_options.first })
      expect(ids_in(game, "alice", :graveyard).size).to eq(1)
      expect(ids_in(game, "alice", :hand).size).to eq(1)
    end
  end

  it "Fire Lord Zuko puts counters on your creatures when a permanent you control enters from exile (CR 603.6a)" do
    game = board(hand: ["Test Flicker"], battlefield: ["Fire Lord Zuko"], mana: { W: 1 })
    cast(game, "Test Flicker", target(obj_id(game, "Fire Lord Zuko")))
    zuko = game.state.battlefield.find { game.state.object(it).card == "fire_lord_zuko" }
    expect(game.state.object(zuko).counters["+1/+1"]).to eq(1)
  end

  describe "Mister Negative: life lost this way, read through a may (CR 608.2c, 701.12c)" do
    it "draws as many cards as the life you lost in the exchange" do
      game = board(hand: ["Mister Negative"], mana: { W: 1, B: 1, C: 5 }, life: 15, their_life: 12)
      cast(game, "Mister Negative", target("player:bob"), yes)
      expect([life(game, "alice"), life(game, "bob")]).to eq([12, 15])
      expect(ids_in(game, "alice", :hand).size).to eq(3)
    end

    it "draws nothing when you decline the exchange" do
      game = board(hand: ["Mister Negative"], mana: { W: 1, B: 1, C: 5 }, life: 15, their_life: 12)
      cast(game, "Mister Negative", target("player:bob"), { type: "no" })
      expect(ids_in(game, "alice", :hand)).to be_empty
    end
  end

  it "Agent Maria Hill gets a counter and draws when she's tapped to pay a teamwork cost (CR 702.194a)" do
    game = board(hand: ["Cruel Alliance"], battlefield: ["Agent Maria Hill"], theirs: ["Shimmercreep"], mana: { B: 1, C: 2 })
    hill = obj_id(game, "Agent Maria Hill")
    cast(game, "Cruel Alliance", { type: "kick" }, target(obj_id(game, "Shimmercreep")), { type: "cost", object: hill })
    expect(game.state.object(hill).counters["+1/+1"]).to eq(1)
    expect(ids_in(game, "alice", :hand).size).to eq(1)
    expect(events(game).map { it["type"] }).to include("tapped_for_cost")
  end

  it "Speedball: a spell that targets him pumps him, and you may choose new targets for it (CR 115.7d)" do
    game = board(battlefield: ["Speedball, New Warrior"], their_hand: ["Test Shock"], step: :upkeep)
    game.state.players[1].mana_pool[:R] = 1
    speedball = obj_id(game, "Speedball, New Warrior")
    game.submit(type: "pass")
    game.submit(type: "cast", object: ids_in(game, "bob", :hand).first)
    game.submit(target(speedball))
    game.submit(game.legal_options.find { it[:type] == "pay_mana" })
    play(game, nil, ->(g) { g.legal_options.find { it[:target] == "player:bob" } })
    expect(life(game, "bob")).to eq(18)
    expect(game.state.object(speedball).damage).to eq(0)
  end

  describe "copying the ability that was activated or triggered (CR 707.10)" do
    it "Pit Automaton copies the next exhaust ability you activate this turn" do
      game = board(battlefield: ["Pit Automaton", "Jeong Jeong, the Deserter"], mana: { C: 5 })
      activate(game, "Pit Automaton")
      play(game, { type: "activate", object: obj_id(game, "Jeong Jeong, the Deserter"), ability: "printed:1" })
      expect(counters(game, "Jeong Jeong, the Deserter")).to eq(2)
    end

    it "Jeong Jeong copies the next Lesson spell you cast this turn" do
      game = board(hand: ["Test Lesson", "Test Lesson"], battlefield: ["Jeong Jeong, the Deserter"], mana: { U: 5 })
      activate(game, "Jeong Jeong, the Deserter")
      cast(game, "Test Lesson")
      expect(ids_in(game, "alice", :hand).size).to eq(3) # one Lesson left, two cards drawn
      cast(game, "Test Lesson")
      expect(ids_in(game, "alice", :hand).size).to eq(3) # only the next one was copied
    end

    it "Firebender Ascension copies an attack trigger once it has four quest counters" do
      game = board(battlefield: [["Firebender Ascension", { counters: { "quest" => 3 } }], "Jeong Jeong, the Deserter"],
                   step: :beginning_of_combat)
      jeong = obj_id(game, "Jeong Jeong, the Deserter")
      pass_both(game)
      game.submit(type: "attack", object: jeong, target: "player:bob")
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
      firebending = game.state.pending_triggers.find { it["card"] == "jeong_jeong_the_deserter" }
      game.submit(type: "trigger", trigger: firebending["id"]) # it goes on the stack first: the Ascension's resolves first
      game.submit(type: "pass")
      game.submit(type: "pass")
      game.submit(yes) # copy it (no targets to change)
      2.times { game.submit(type: "pass") while game.state.stack.any? && game.pending_decision.kind == "priority" }
      expect(events(game).count { it["type"] == "mana_added" && it["mana"] == "{R}" }).to eq(2) # the original and its copy
      expect(counters(game, "Firebender Ascension", "quest")).to eq(4)
    end
  end

  describe "Burglar's Plot: two targets that share a card type (CR 701.12b, 205.2a)" do
    it "offers only a second target sharing a card type, then exchanges control" do
      game = board(hand: ["Bilbo, Luckwearer // Burglar's Plot"], battlefield: ["Agent Maria Hill", "The Endstone"],
                   theirs: ["Fire Lord Zuko"], mana: { U: 5 })
      hill = obj_id(game, "Agent Maria Hill")
      zuko = obj_id(game, "Fire Lord Zuko")
      plot = obj_id(game, "Bilbo, Luckwearer // Burglar's Plot", zone: :hand, player: "alice")
      game.submit(game.legal_options.find { it[:type] == "cast" && it[:object] == plot && it[:face] == 1 })
      game.submit(target(hill))
      expect(game.legal_options.select { it[:type] == "target" }.map { it[:target] }).to contain_exactly(zuko)
      play(game, target(zuko))
      expect([game.state.object(hill).controller, game.state.object(zuko).controller]).to eq([1, 0])
    end
  end

  it "Fblthp finds up to X basic lands with different names (CR 701.23)" do
    game = board(hand: ["Fblthp, Knows the Way"], library: %w[Forest Forest Island Swamp], mana: { G: 4 })
    play(game, { type: "cast", object: obj_id(game, "Fblthp, Knows the Way", zone: :hand, player: "alice") },
         { type: "x", value: 2 }, ->(g) { g.legal_options.find { g.state.object(it[:object]).card == "forest" } },
         lambda { |g|
           found = g.legal_options.select { it[:object] }
           expect(found.map { g.state.object(it[:object]).card }).to contain_exactly("island", "swamp")
           found.first
         })
    expect(ids_in(game, "alice", :hand).map { game.state.object(it).card }.uniq.size).to eq(2)
  end

  it "Edgar, King of Figaro: the first coin flips each turn come up heads and win (CR 705.3)" do
    game = board(hand: ["Test Coin", "Test Coin"], battlefield: ["Edgar, King of Figaro"], mana: { U: 2 })
    cast(game, "Test Coin") # no call: the flip is won
    expect(ids_in(game, "alice", :hand).size).to eq(2)
    cast(game, "Test Coin", { type: "call", call: "heads" }) # the second flip this turn is called as usual
    flips = events(game).select { it["type"] == "coin_flipped" }
    expect(flips.first).to include("heads" => true, "won" => true)
    expect(flips.size).to eq(2)
  end

  it "Spinerock Tyrant copies a single-target spell; both spells gain wither (CR 707.10, 702.80a)" do
    game = board(hand: ["Test Shock"], battlefield: ["Spinerock Tyrant"], theirs: ["Fire Lord Zuko", "Agent Maria Hill"],
                 mana: { R: 1 })
    zuko = obj_id(game, "Fire Lord Zuko")
    hill = obj_id(game, "Agent Maria Hill")
    cast(game, "Test Shock", target(zuko), yes, target(hill))
    expect(game.state.object(zuko).counters["-1/-1"]).to eq(2) # the original, with wither
    expect(game.state.object(zuko).damage).to eq(0)
    expect(game.state.battlefield).not_to include(hill) # the copy, with wither: two -1/-1 counters on a 2/1
  end

  it "Quandrix gives instants and sorceries you cast from your hand cascade (CR 702.85a)" do
    game = board(hand: ["Command the Stage", "Fire Lord Zuko"], battlefield: ["Quandrix, the Proof"],
                 library: ["Test Shock"] + (["Island"] * 5), mana: { R: 4, W: 1, B: 1 })
    cast(game, "Fire Lord Zuko") # a creature spell: no cascade
    expect(events(game).count { it["type"] == "spell_cast" }).to eq(1)
    cast(game, "Command the Stage", ->(g) { g.legal_options.find { it[:type] == "cast" } }, target("player:bob"))
    expect(life(game, "bob")).to eq(18) # Test Shock, cast without paying its mana cost
  end

  it "Cool but Rude: becoming level 3 tutors, then discards at random, which deals 2 to each opponent" do
    game = board(battlefield: [["Cool but Rude", {}]], hand: ["Island"], library: %w[Swamp Forest], mana: { R: 4 })
    rude = obj_id(game, "Cool but Rude")
    play(game, { type: "activate", object: rude, ability: game.legal_options.find { it[:type] == "activate" }[:ability] })
    play(game, { type: "activate", object: rude, ability: game.legal_options.find { it[:type] == "activate" }[:ability] },
         ->(g) { g.legal_options.first })
    expect(ids_in(game, "alice", :hand).size).to eq(1)
    expect(life(game, "bob")).to eq(18)
  end
end
