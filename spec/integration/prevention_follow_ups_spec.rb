# frozen_string_literal: true

# Prevention with a follow-up, a chosen source, "the next time" and "for as long as" durations; recipients
# decided as damage is dealt; damage modification tied to a player; dies-to-exile with a follow-up; ending
# the turn (CR 609.7a, 611.2b-c, 614.1a, 615.5, 615.8, 603.12, 725.1).
RSpec.describe "Prevention follow-ups, damage effects tied to players, ending the turn" do
  def creature(name, power, toughness, *abilities, keywords: [])
    { "name" => name, "mana_cost" => "{1}", "types" => ["creature"], "subtypes" => ["bear"], "power" => power,
      "toughness" => toughness, "keywords" => keywords, "abilities" => abilities }
  end

  def spell(name, *effects, targets: [], types: ["instant"])
    { "name" => name, "mana_cost" => "{R}", "types" => types,
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects } }] }
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, who) = game.state.players[game.names.index(who)].life
  def id(game, name) = obj_id(game, name)
  def counters(game, name) = engine(game).object(id(game, name)).counters.fetch("+1/+1", 0)

  let(:healer) do
    creature("Pale Healer", 5, 5, { "prevent_damage" => { "to" => "self", "then" => [{ "add_counters" => {
               "counter" => "+1/+1", "amount" => { "triggering" => "amount" }, "to" => "self"
             } }] } })
  end
  let(:new_way) do
    spell("Other Way", { "prevent_damage" => { "to" => "you", "by" => "chosen_source", "next_time" => true,
                                               "then" => [{ "reflexive_trigger" => { "effects" => [
                                                 { "deal_damage" => { "amount" => { "triggering" => "amount" },
                                                                      "to" => { "triggering" => "player" } } },
                                                 { "draw" => { "amount" => { "triggering" => "amount" }, "to" => "you" } }
                                               ] } }] } })
  end
  let(:spider_saga) do
    prevent = { "prevent_damage" => { "by" => { "target" => 0 }, "duration" => "while_source_on_battlefield" } }
    theirs = { "creature" => { "controller" => "opponent" } }
    creature("Hiding Spider", 1, 1, { "triggered" => { "when" => { "enters" => {} }, "targets" => [theirs], "effects" => [prevent] } })
  end
  let(:fragments) { spell("Crystal Ward", { "prevent_damage" => { "to_each" => { "each" => "creature", "controller" => "you" } } }) }
  let(:lightning) do
    double = { "damage_replacement" => { "to" => { "triggering" => "player" }, "permanents" => true, "multiply" => 2,
                                         "duration" => "until_your_next_turn" } }
    creature("Bolt Soldier", 3, 2, { "triggered" => { "when" => { "deals_damage" => { "combat" => true, "to" => "player" } },
                                                      "effects" => [double] } })
  end
  let(:hunter) do
    wolf = { "name" => "Wolf", "types" => ["creature"], "subtypes" => ["wolf"], "colors" => ["G"], "power" => 2, "toughness" => 2 }
    creature("Pack Head", 4, 3, { "exile_if_dies" => { "affects" => { "each" => "creature", "controller" => "opponent" },
                                                       "then" => [{ "reflexive_trigger" => { "effects" => [{ "create_token" => {
                                                         "token" => wolf
                                                       } }] } }] } })
  end
  let(:crystal) do
    { "name" => "Dark Crystal", "mana_cost" => "{2}", "types" => ["artifact"],
      "abilities" => [{ "exile_if_dies" => { "affects" => { "each" => { "creature" => { "token" => false } }, "controller" => "opponent" },
                                             "then" => [{ "gain_life" => { "amount" => 2, "to" => "you" } }] } }] }
  end
  let(:stop) { spell("Stop Time", "end_the_turn", { "gain_life" => { "amount" => 5, "to" => "you" } }) }
  let(:shock) { spell("Small Shock", { "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }, targets: ["any_target"]) }
  let(:big) { creature("Big Brute", 6, 6) }
  let(:small) { creature("Small Fry", 2, 2) }
  let(:catalog) { catalog_with(healer, new_way, spider_saga, fragments, lightning, hunter, crystal, stop, shock, big, small) }

  def board(alice: [], bob: [], hand: [], step: :precombat_main, mana: { R: 3 })
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana) do
        battlefield(*alice) unless alice.empty?
        hand(*hand) unless hand.empty?
        library "Forest", count: 8
      end
      player("bob") do
        battlefield(*bob) unless bob.empty?
        library "Forest", count: 8
      end
    end
  end

  def resolve_all(game, answers = [])
    while game.state.stack.any? || game.state.pending_triggers.any? || game.pending_decision.kind != "priority"
      decision = game.pending_decision
      game.submit(case decision.kind
                  when "priority" then { type: "pass" }
                  when "pay_cost" then game.legal_options.find { it[:type] == "pay_mana" }
                  else answers.shift || game.legal_options.first
                  end)
    end
  end

  def cast(game, card, *answers)
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: "alice"))
    resolve_all(game, answers)
  end

  it "prevents damage and puts that many counters on the creature (CR 615.5)" do
    game = board(alice: ["Pale Healer"])
    expect(engine(game).deal_damage!(nil, id(game, "Pale Healer"), 3)).to eq(0)
    expect(counters(game, "Pale Healer")).to eq(3)
  end

  it "the next time a chosen source would deal damage to you, prevents it and reflexively punishes (CR 615.8, 609.7a)" do
    game = board(alice: [], bob: ["Big Brute"], hand: ["Other Way"])
    brute = id(game, "Big Brute")
    cast(game, "Other Way", { type: "source", object: brute })
    eng = engine(game)
    expect(eng.deal_damage!(brute, "player:alice", 6)).to eq(0)
    resolve_all(game)
    expect(life(game, "bob")).to eq(14)
    expect(game.state.players[0].hand.size).to eq(6)
    expect(eng.deal_damage!(brute, "player:alice", 6)).to eq(6) # used up
  end

  it "prevents damage by a creature for as long as its source remains on the battlefield (CR 611.2b)" do
    game = board(alice: ["Hiding Spider"], bob: ["Big Brute"])
    eng = engine(game)
    spider = id(game, "Hiding Spider")
    eng.move!(spider, :graveyard, reason: "destroy")
    eng.move!(obj_id(game, "Hiding Spider", zone: :graveyard, player: "alice"), :battlefield, reason: "test")
    resolve_all(game)
    brute = id(game, "Big Brute")
    expect(eng.deal_damage!(brute, "player:alice", 3)).to eq(0)
    eng.move!(id(game, "Hiding Spider"), :graveyard, reason: "destroy")
    expect(eng.deal_damage!(brute, "player:alice", 3)).to eq(3)
  end

  it "prevents damage to creatures you control, decided as the damage is dealt (CR 611.2c)" do
    game = board(alice: ["Small Fry"], bob: ["Big Brute"], hand: ["Crystal Ward"])
    cast(game, "Crystal Ward")
    eng = engine(game)
    expect(eng.deal_damage!(nil, id(game, "Small Fry"), 2)).to eq(0)
    brute = id(game, "Big Brute")
    expect(eng.deal_damage!(nil, brute, 2)).to eq(2)
    eng.gain_control!(eng.object(brute), 0) # now a creature alice controls: covered too
    expect(eng.deal_damage!(nil, brute, 2)).to eq(0)
    expect(eng.deal_damage!(nil, "player:alice", 2)).to eq(2)
  end

  it "doubles damage to the damaged player and their permanents until your next turn" do
    game = board(alice: ["Bolt Soldier"], bob: ["Small Fry"])
    eng = engine(game)
    soldier = id(game, "Bolt Soldier")
    eng.deal_damage!(soldier, "player:bob", 3, combat: true)
    resolve_all(game)
    expect(eng.deal_damage!(nil, "player:bob", 2)).to eq(4)
    expect(eng.deal_damage!(nil, id(game, "Small Fry"), 1)).to eq(2)
    expect(eng.deal_damage!(nil, soldier, 1)).to eq(1)
  end

  it "exiles a dying creature instead, and \"when you do\" creates a token (CR 614.1a, 603.12)" do
    game = board(alice: ["Pack Head"], bob: ["Small Fry"])
    engine(game).move!(id(game, "Small Fry"), :graveyard, reason: "destroy")
    resolve_all(game)
    expect(game.state.exile.size).to eq(1)
    expect(game.state.battlefield.count { engine(game).chars(it).name == "Wolf" }).to eq(1)
  end

  it "exiles a dying creature instead, you gain 2 life, and the card is exiled with it (CR 607.2a)" do
    game = board(alice: ["Dark Crystal"], bob: ["Small Fry"])
    engine(game).move!(id(game, "Small Fry"), :graveyard, reason: "destroy")
    expect(life(game, "alice")).to eq(22)
    expect(engine(game).object(id(game, "Dark Crystal")).memory["exiled_with"]).to eq(game.state.exile)
  end

  it "ends the turn: exiles the stack and the spell, skips to cleanup (CR 725.1)" do
    game = board(alice: ["Small Fry"], hand: ["Stop Time", "Small Shock"], mana: { R: 2 })
    game.submit(type: "cast", object: obj_id(game, "Small Shock", zone: :hand, player: "alice"))
    game.submit(type: "target", target: "player:bob")
    game.submit(game.legal_options.find { it[:type] == "pay_mana" })
    game.submit(type: "cast", object: obj_id(game, "Stop Time", zone: :hand, player: "alice"))
    game.submit(game.legal_options.find { it[:type] == "pay_mana" })
    pass_both(game)
    expect(game.state.stack).to be_empty
    expect(game.state.exile.size).to eq(2)
    expect(life(game, "alice")).to eq(20) # the rest of the spell doesn't happen
    expect(life(game, "bob")).to eq(20)
    expect(game.state.turn).to eq(4) # cleanup, then bob's turn
  end
end
