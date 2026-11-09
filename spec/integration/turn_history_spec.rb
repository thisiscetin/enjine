# frozen_string_literal: true

RSpec.describe "Turn and game history (CR 601.2i, 700.4, 119.9, 608.2h)" do
  let(:echo) do # "{R}: you gain 1 life; the second time this resolves this turn, draw a card"
    { "name" => "Echo Lantern", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{R}" }], "effects" => [
        { "gain_life" => { "amount" => 1 } },
        { "draw" => { "amount" => 1, "if" => { "nth_resolution" => 2 } } }
      ] } }] }
  end
  let(:split) do # modal: a player who chooses a mode faces a dilemma (CR 700.17)
    { "name" => "Forked Ember", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "choose" => 1, "modes" => [
        { "effects" => [{ "gain_life" => { "amount" => 1 } }] },
        { "effects" => [{ "lose_life" => { "amount" => 1, "to" => "each_opponent" } }] }
      ] } }] }
  end
  let(:catalog) { catalog_with(echo, split) }
  let(:game) do
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Lightning Bolt", "Grizzly Bears", "Forked Ember"
        battlefield "Mountain", count: 4
        battlefield "Forest", count: 2
        battlefield "Echo Lantern"
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Savannah Lions", "Hill Giant"
        library "Forest", count: 5
      end
    end
  end
  let(:engine) { game.instance_variable_get(:@engine) }

  def amount(data, controller: 0)
    errors = []
    built = Enjine::Mechanics::Amount.build(data, errors, "a", targets_count: 0)
    raise errors.join(", ") unless errors.empty?

    built.value(engine, Enjine::Mechanics::EffectContext.new(controller, nil, nil, []))
  end

  def pay(game, *lands)
    lands.each do |land|
      game.submit(type: "activate_mana", object: land, ability: mana_ref(game, land))
      game.submit(game.legal_options.find { it[:type] == "pay_mana" })
    end
  end

  def card_in_hand(card) = ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) }
  def mountains = game.state.battlefield.select { game.state.object(it).card == "mountain" }

  it "counts spells once they're cast; a cancelled cast never counts (CR 601.2i)" do
    game.submit(type: "cast", object: card_in_hand("Lightning Bolt"))
    game.submit(type: "cancel")
    noncreature = { "spells_cast_this_turn" => { "by" => "you", "matching" => { "spell" => { "not" => ["creature"] } } } }
    expect(amount(noncreature)).to eq(0)
    game.submit(type: "cast", object: card_in_hand("Lightning Bolt"))
    game.submit(type: "target", target: obj_id(game, "Savannah Lions"))
    pay(game, mountains.first)
    expect(amount(noncreature)).to eq(1)
    expect(amount({ "spells_cast_this_turn" => { "by" => "each_opponent" } })).to eq(0)
    expect(amount({ "spells_cast_this_game" => "you" })).to eq(1)
    pass_both(game) # Bolt resolves: the Lions die (CR 700.4) and bob's history records it
    expect(amount({ "died_this_turn" => { "each" => "creature" } })).to eq(1)
    expect(amount({ "died_this_turn" => { "each" => "creature", "controller" => "opponent" } })).to eq(1)
    expect(amount({ "died_this_turn" => { "each" => "creature", "controller" => "you" } })).to eq(0)
    expect(amount({ "died_this_turn" => { "each" => "land" } })).to eq(0)
  end

  it "records permanents entering, returning to hand and life changes, then forgets them next turn" do
    game.submit(type: "cast", object: card_in_hand("Grizzly Bears"))
    pay(game, *game.state.battlefield.select { game.state.object(it).card == "forest" })
    pass_both(game)
    expect(amount({ "entered_this_turn" => { "each" => "creature", "controller" => "you" } })).to eq(1)
    engine.move!(obj_id(game, "Hill Giant"), :hand, reason: "bounce")
    expect(amount({ "returned_this_turn" => "each_opponent" })).to eq(1)
    expect(amount({ "returned_this_turn" => "you" })).to eq(0)
    engine.change_life!(0, 3)
    engine.change_life!(1, -4)
    expect([amount({ "life_gained_this_turn" => "you" }), amount({ "life_lost_this_turn" => "each_opponent" })]).to eq([3, 4])
    skip_to(game, :upkeep, turn: 4)
    expect([amount({ "life_gained_this_turn" => "you" }), amount({ "entered_this_turn" => { "each" => "permanent" } })]).to eq([0, 0])
    expect(amount({ "spells_cast_this_game" => "you" })).to eq(1) # the game log stays
  end

  it "matches entered permanents by the subtypes they had as they entered" do
    catalog = CardFixtures.catalog
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Brasswork Cudgel"
        battlefield "Gearwatch Smith"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    engine = game.instance_variable_get(:@engine)
    equipment = { "entered_this_turn" => { "each" => { "artifact" => { "subtypes" => ["equipment"] } }, "controller" => "you" } }
    built = Enjine::Mechanics::Amount.build(equipment, [], "a", targets_count: 0)
    ctx = Enjine::Mechanics::EffectContext.new(0, nil, nil, [])
    expect(built.value(engine, ctx)).to eq(0)
    engine.move!(ids_in(game, "alice", :hand).first, :battlefield, reason: "test")
    expect(built.value(engine, ctx)).to eq(1)
    hand = game.state.players[0].hand.size
    skip_to(game, :end)
    pass_both(game) # Gearwatch Smith's end step trigger: an Equipment entered this turn, so draw
    expect(game.state.players[0].hand.size).to eq(hand + 1)
  end

  it "counts dilemmas faced this turn (CR 700.17)" do
    game.submit(type: "cast", object: card_in_hand("Forked Ember"))
    game.submit(type: "mode", mode: 0)
    pay(game, mountains.first)
    expect(amount({ "dilemmas_this_turn" => "you" })).to eq(1)
  end

  it "knows how many times this turn an ability has resolved (CR 608.2)" do
    lantern = obj_id(game, "Echo Lantern")
    hand = ids_in(game, "alice", :hand).size
    3.times do |i|
      game.submit(type: "activate", object: lantern, ability: "printed:0")
      pay(game, mountains[i])
      pass_both(game)
    end
    expect(engine.times_resolved(lantern, "printed:0")).to eq(3)
    expect(ids_in(game, "alice", :hand).size).to eq(hand + 1) # only the second resolution drew
    skip_to(game, :upkeep, turn: 4)
    expect(engine.times_resolved(lantern, "printed:0")).to eq(0)
  end

  it "remembers attackers for the turn and survives export/import" do
    game = build_game do
      turn 3, active: "alice", step: :beginning_of_combat
      player("alice") { battlefield "Grizzly Bears" }
      player("bob") { library "Forest", count: 3 }
    end
    engine = game.instance_variable_get(:@engine)
    bears = obj_id(game, "Grizzly Bears")
    expect(engine.attacked_this_turn?(bears)).to be(false)
    pass_both(game)
    game.submit(type: "attack", object: bears, target: "player:bob")
    expect(engine.attacked_this_turn?(bears)).to be(true)
    copy = Enjine::Game.import(game.export, catalog: game.catalog)
    expect(copy.state.to_h).to eq(game.state.to_h)
    expect(copy.state.players[0].turn_log).to eq(game.state.players[0].turn_log)
  end

  it "rejects malformed history amounts and snapshots" do
    errors = []
    Enjine::Mechanics::Amount.build({ "died_this_turn" => { "each" => "creature", "controller" => "nobody" } }, errors, "a",
                                    targets_count: 0)
    Enjine::Mechanics::Amount.build({ "spells_cast_this_turn" => { "by" => "you", "who" => 1 } }, errors, "b", targets_count: 0)
    expect(errors).to eq(["a.died_this_turn.controller: must be one of you, opponent, any",
                          "b.spells_cast_this_turn: unknown parameter \"who\""])
    data = game.state.to_h
    data["players"][0]["turn_log"] = []
    expect(Enjine::Snapshot.validate(data, game.catalog)).to include("players[0].turn_log: must be an object")
  end
end
