# frozen_string_literal: true

# Effect lists nested in an effect ("may", reflexive triggers) number their own results after the enclosing
# list's earlier effects (CR 608.2c, 603.12): {"result": n} / {"this_way": n} below the nesting effect's position
# is the enclosing list's effect n, from it on the nested list's own effects.
RSpec.describe "Results of nested effect lists (CR 608.2c, 603.12)" do
  let(:offering) do # draw; you may sacrifice a creature; if you do, gain life equal to its power, else draw a card
    { "name" => "Spec Offering", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [
        { "draw" => { "amount" => 1 } },
        { "may" => { "effects" => [{ "sacrifice_choice" => { "filter" => "creature" } }],
                     "then" => [{ "gain_life" => { "amount" => { "power" => { "result" => 1 } } } },
                                { "lose_life" => { "to" => "each_opponent", "amount" => { "this_way" => 2 } } }],
                     "otherwise" => [{ "draw" => { "amount" => 1 } },
                                     { "lose_life" => { "to" => "you", "amount" => { "count" => { "result" => 1 } } } }] } }
      ] } }] }
  end
  let(:bolg) do # sacrifice a creature; when you do, it deals damage equal to its power; amass the excess
    { "name" => "Spec Bolg", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [
        { "sacrifice_choice" => { "filter" => "creature" } },
        { "reflexive_trigger" => { "targets" => ["creature"], "effects" => [
          { "deal_damage" => { "amount" => { "power" => { "result" => 0 } }, "to" => { "target" => 0 } } },
          { "gain_life" => { "amount" => { "this_way" => 1 } } }
        ] } }
      ] } }] }
  end
  let(:hydra) do
    { "name" => "Spec Cascade Hydra", "mana_cost" => "{3}", "types" => ["creature"], "power" => 3, "toughness" => 3,
      "keywords" => %w[cascade cascade] }
  end
  let(:tithe) do # you may pay 2 life; if you do, draw a card and gain life equal to the cards drawn this way
    { "name" => "Spec Tithe", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [
        { "pay" => { "life" => 2, "then" => [{ "draw" => { "amount" => 1 } },
                                             { "gain_life" => { "amount" => { "count" => { "result" => 0 } } } }] } }
      ] } }] }
  end
  let(:catalog) { catalog_with(offering, bolg, hydra, tithe) }

  def life(game, name) = game.state.players[game.names.index(name)].life

  def board(alice: [], bob: [], hand: [], mana: {})
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: mana) do
        alice.each { |card, opts| battlefield card, **(opts || {}) }
        hand(*hand)
        library "Forest", count: 5
      end
      player("bob") do
        bob.each { |card, opts| battlefield card, **(opts || {}) }
        library "Forest", count: 5
      end
    end
  end

  def cast(game, card, answers = [])
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: "alice"))
    while game.state.stack.any? || game.state.pending_triggers.any? || game.pending_decision.kind != "priority"
      decision = game.pending_decision
      game.submit(case decision.kind
                  when "priority" then { type: "pass" }
                  when "pay_cost" then game.legal_options.find { it[:type] == "pay_mana" }
                  else game.legal_options.find { answers.first.nil? || answers.first.call(it) }.tap { answers.shift }
                  end)
    end
    game
  end

  it "a may's then names what its effects did, numbered after the enclosing list's effects" do
    game = board(alice: [["Hill Giant", { counters: { "+1/+1" => 1 } }]], hand: ["Spec Offering"], mana: { B: 1 })
    cast(game, "Spec Offering", [->(o) { o[:type] == "yes" }])
    expect(life(game, "alice")).to eq(24) # the sacrificed Hill Giant's power as it last existed
    expect(life(game, "bob")).to eq(16) # the life the gain_life gave ({"this_way": 2})
  end

  it "a may's otherwise numbers its own effects from the same position" do
    game = board(alice: ["Hill Giant"], hand: ["Spec Offering"], mana: { B: 1 })
    cast(game, "Spec Offering", [->(o) { o[:type] == "no" }])
    expect(ids_in(game, "alice", :hand).size).to eq(2)
    expect(life(game, "alice")).to eq(19) # one card drawn by the otherwise's first effect
  end

  it "a reflexive trigger reads its own effects' amounts and its parent's results (CR 603.12)" do
    game = board(alice: [["Hill Giant", { counters: { "+1/+1" => 2 } }]], bob: ["Grizzly Bears"], hand: ["Spec Bolg"],
                 mana: { B: 1 })
    cast(game, "Spec Bolg")
    expect(game.state.battlefield).to be_empty
    expect(life(game, "alice")).to eq(23) # 5 damage to a 2/2: 3 excess
  end

  it "a pay's then names its own effects' results" do
    game = board(hand: ["Spec Tithe"], mana: { B: 1 })
    cast(game, "Spec Tithe", [->(o) { o[:type] != "decline" }])
    expect(ids_in(game, "alice", :hand).size).to eq(1)
    expect(life(game, "alice")).to eq(19) # paid 2, gained 1
  end

  it "a reflexive trigger in a may's then reads what the may sacrificed and its own excess damage (CR 603.12)" do
    game = board(alice: [["Hill Giant", { counters: { "+1/+1" => 2 } }]], bob: ["Grizzly Bears"], hand: ["Bonded Offering"],
                 mana: { B: 2 })
    cast(game, "Bonded Offering", [->(o) { o[:type] == "yes" }])
    expect(game.state.battlefield).to be_empty
    expect(life(game, "alice")).to eq(23) # 5 damage to a 2/2: 3 excess
  end

  it "refuses a nested reference to the nesting effect itself or a later one" do
    bad = { "name" => "Spec Bad", "mana_cost" => "{B}", "types" => ["sorcery"],
            "abilities" => [{ "spell" => { "effects" => [
              { "draw" => { "amount" => 1 } },
              { "may" => { "effects" => [{ "gain_life" => { "amount" => { "count" => { "result" => 1 } } } }],
                           "otherwise" => [{ "draw" => { "amount" => 1 } },
                                           { "lose_life" => { "to" => "you", "amount" => { "this_way" => 2 } } }] } }
            ] } }] }
    expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition) { |e|
      expect(e.message).to include("may.effects[0].gain_life.amount.count.result: must refer to one of the 1 earlier effects")
      expect(e.message).to include("otherwise[1].lose_life.amount.this_way: must refer to one of the 2 earlier effects")
    }
  end

  it "each listed instance of cascade triggers separately (CR 702.85c)" do
    game = board(hand: ["Spec Cascade Hydra"], mana: { C: 3 })
    game.submit(type: "cast", object: obj_id(game, "Spec Cascade Hydra", zone: :hand, player: "alice"))
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
    game.submit(type: "pass") until game.pending_decision.kind == "order_triggers" || game.state.stack.size > 1
    expect(game.pending_decision.kind).to eq("order_triggers")
    expect(game.state.pending_triggers.map { it["ability"] }).to eq(%w[keyword:cascade keyword:cascade])
  end
end
