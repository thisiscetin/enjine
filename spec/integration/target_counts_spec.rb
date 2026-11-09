# frozen_string_literal: true

# A variable number of targets for one "target" word (CR 601.2c, 115.3): "X target creatures",
# "any number of target creatures", "up to two target creatures".
RSpec.describe "Variable numbers of targets (CR 601.2c, 115.3)" do
  let(:mass_tap) do
    { "name" => "Spec Mass Freeze", "mana_cost" => "{X}{U}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => [{ "filter" => "creature", "count" => "x" }],
                                     "effects" => [{ "tap" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:recall) do
    { "name" => "Spec Mass Recall", "mana_cost" => "{U}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => [{ "filter" => { "creature" => { "controller" => "you" } }, "count" => "any" }],
                                     "effects" => [{ "return_to_hand" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:rally) do
    { "name" => "Spec Twin Rally", "mana_cost" => "{U}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => [{ "filter" => "creature", "count" => 2, "optional" => true }, "player"],
                                     "effects" => [{ "pump" => { "power" => 1, "toughness" => 1, "to" => { "target" => 0 } } },
                                                   { "lose_life" => { "amount" => 1, "to" => { "target" => 1 } } }] } }] }
  end
  let(:infiltration) do
    { "name" => "Spec Shapeshift Raid", "mana_cost" => "{X}{U}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => [{ "filter" => { "creature" => { "controller" => "opponent" } }, "count" => "x" }],
                                     "effects" => [
                                       { "create_token_copy" => { "of" => { "target" => 0 },
                                                                  "except" => { "keywords" => ["changeling"] } } },
                                       { "grant" => { "keywords" => ["haste"], "to" => { "result" => 0 } } },
                                       { "delayed_trigger" => { "when" => { "step_begins" => { "step" => "end", "whose" => "each" } },
                                                                "effects" => [{ "exile" => { "to" => { "result" => 0 } } }] } }
                                     ] } }] }
  end
  let(:fan) do
    { "name" => "Spec Blessing Fan", "mana_cost" => "{U}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => [{ "filter" => "creature", "count" => "any" }], "divide" => 3,
                                     "effects" => [{ "distribute_counters" => { "counter" => "+1/+1" } }] } }] }
  end
  let(:mirror) do
    { "name" => "Spec Echo Mirror", "mana_cost" => "{U}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["spell"],
                                     "effects" => [{ "copy_spell" => { "of" => { "target" => 0 }, "new_targets" => true } }] } }] }
  end
  let(:herald) do
    lands = { "count" => { "each" => "land", "controller" => "you" } }
    { "name" => "Spec Tide Herald", "mana_cost" => "{U}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} },
                                         "targets" => [{ "filter" => { "creature" => { "controller" => "you" } }, "count" => lands }],
                                         "effects" => [{ "pump" => { "power" => 1, "toughness" => 1, "to" => { "target" => 0 } } }] } }] }
  end
  let(:catalog) { catalog_with(mass_tap, recall, rally, infiltration, fan, mirror, herald) }

  it "a triggered ability without enough legal targets for its count is removed (CR 603.3d)" do
    game = game_with(hand: ["Spec Tide Herald"], board: ["Hill Giant"], lands: 3)
    cast(game, "Spec Tide Herald")
    pay(game)
    pass_both(game)
    expect(game.state.stack).to be_empty # 3 lands, but only 2 creatures
    expect(engine(game).power(game.state.object(obj_id(game, "Hill Giant")))).to eq(3)
  end

  it "a triggered ability's computed count" do
    game = game_with(hand: ["Spec Tide Herald"], board: ["Hill Giant"], lands: 2)
    cast(game, "Spec Tide Herald")
    pay(game)
    pass_both(game)
    expect(game.pending_decision.kind).to eq("choose_target") # 2 lands: exactly 2, nothing to announce
    game.submit(type: "target", target: obj_id(game, "Hill Giant"))
    game.submit(type: "target", target: obj_id(game, "Spec Tide Herald"))
    pass_both(game)
    expect(engine(game).power(game.state.object(obj_id(game, "Hill Giant")))).to eq(4)
    expect(engine(game).power(game.state.object(obj_id(game, "Spec Tide Herald")))).to eq(2)
  end

  def engine(game) = game.instance_variable_get(:@engine)

  def game_with(hand:, board: [], opponent: [], lands: 4)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand(*hand)
        battlefield "Island", count: lands
        battlefield(*board) unless board.empty?
        library "Island", count: 5
      end
      player("bob") do
        battlefield(*opponent) unless opponent.empty?
        library "Island", count: 5
      end
    end
  end

  def cast(game, name)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(name) })
  end

  def pay(game)
    while game.pending_decision.kind == "pay_cost"
      land = game.state.battlefield.find { game.state.object(it).card == "island" && !game.state.object(it).tapped }
      game.submit(type: "activate_mana", object: land, ability: "intrinsic:island")
      game.submit(type: "pay_mana", mana: "U")
    end
  end

  def ids(game, card) = game.state.battlefield.select { game.state.object(it).card == card }
  def target_cards(game) = game.legal_options.filter_map { it[:target] && game.state.object(it[:target]).card }

  it "X target creatures: X is the number, each chosen once, and {target: 0} is each of them" do
    game = game_with(hand: ["Spec Mass Freeze"], opponent: ["Hill Giant", "Gray Ogre", "Craw Wurm"])
    cast(game, "Spec Mass Freeze")
    game.submit(type: "x", value: 2)
    expect(game.pending_decision.kind).to eq("choose_target") # the number is fixed by X: nothing to announce
    giant = obj_id(game, "Hill Giant")
    game.submit(type: "target", target: giant)
    expect(target_cards(game)).to contain_exactly("gray_ogre", "craw_wurm") # CR 115.3
    game = Enjine::Game.import(game.export, catalog: catalog)
    game.submit(type: "target", target: obj_id(game, "Gray Ogre"))
    pay(game)
    expect(game.state.object(game.state.stack.first).targets).to eq([[giant, obj_id(game, "Gray Ogre")]])
    expect(game.view_for(:observer)["stack"].first["targets"]).to eq([giant, obj_id(game, "Gray Ogre")])
    pass_both(game)
    expect([giant, obj_id(game, "Gray Ogre"), obj_id(game, "Craw Wurm")].map { game.state.object(it).tapped }).to eq([true, true, false])
  end

  it "can't be cast with too few legal targets for X: only cancelling is left (CR 601.2c, 734.1)" do
    game = game_with(hand: ["Spec Mass Freeze"], opponent: ["Hill Giant"])
    cast(game, "Spec Mass Freeze")
    game.submit(type: "x", value: 2)
    game.submit(type: "target", target: obj_id(game, "Hill Giant"))
    expect(game.legal_options).to eq([{ type: "cancel" }])
  end

  it "any number of target creatures: the number is announced first, then the targets" do
    game = game_with(hand: ["Spec Mass Recall"], board: ["Hill Giant", "Gray Ogre"])
    cast(game, "Spec Mass Recall")
    expect(game.pending_decision).to have_attributes(kind: "choose_target_count")
    expect(game.legal_options.map { it[:count] }).to eq([0, 1, 2, nil])
    game.submit(type: "count", count: 2)
    game.submit(type: "target", target: obj_id(game, "Gray Ogre"))
    game.submit(type: "target", target: obj_id(game, "Hill Giant"))
    pay(game)
    pass_both(game)
    expect(ids_in(game, "alice", :hand).map { game.state.object(it).card }).to contain_exactly("hill_giant", "gray_ogre")
  end

  it "any number may be none: the spell then has no targets and still resolves" do
    game = game_with(hand: ["Spec Mass Recall"], board: ["Hill Giant"])
    cast(game, "Spec Mass Recall")
    game.submit(type: "count", count: 0)
    pay(game)
    expect(game.state.stack.size).to eq(1)
    pass_both(game)
    expect(game.state.stack).to be_empty
    expect(ids(game, "hill_giant").size).to eq(1)
  end

  it "up to two, followed by another target: slots keep their order" do
    game = game_with(hand: ["Spec Twin Rally"], board: ["Hill Giant"], opponent: ["Gray Ogre"])
    cast(game, "Spec Twin Rally")
    expect(game.legal_options.map { it[:count] }).to eq([0, 1, 2, nil])
    game.submit(type: "count", count: 1)
    game.submit(type: "target", target: obj_id(game, "Hill Giant"))
    expect(game.pending_decision.details["index"]).to eq(1)
    game.submit(type: "target", target: "player:bob")
    pay(game)
    pass_both(game)
    expect(engine(game).power(game.state.object(obj_id(game, "Hill Giant")))).to eq(4)
    expect(game.state.players[1].life).to eq(19)
  end

  it "only the still-legal ones are affected; with none left, it doesn't resolve (CR 608.2b)" do
    game = game_with(hand: ["Spec Mass Recall", "Spec Mass Freeze"], board: ["Hill Giant", "Gray Ogre"], lands: 6)
    cast(game, "Spec Mass Recall")
    game.submit(type: "count", count: 2)
    game.submit(type: "target", target: obj_id(game, "Gray Ogre"))
    game.submit(type: "target", target: obj_id(game, "Hill Giant"))
    pay(game)
    ogre = obj_id(game, "Gray Ogre")
    engine(game).move!(ogre, :graveyard, reason: "destroy")
    pass_both(game)
    expect(ids_in(game, "alice", :hand).map { game.state.object(it).card }).to include("hill_giant")
    expect(game.state.players[0].graveyard.map { game.state.object(it).card }).to include("gray_ogre", "spec_mass_recall")
  end

  it "fizzles when every chosen target is gone" do
    game = game_with(hand: ["Spec Mass Recall"], board: ["Hill Giant"])
    cast(game, "Spec Mass Recall")
    game.submit(type: "count", count: 1)
    game.submit(type: "target", target: obj_id(game, "Hill Giant"))
    pay(game)
    engine(game).move!(obj_id(game, "Hill Giant"), :graveyard, reason: "destroy")
    pass_both(game)
    expect(game.history.flat_map { it.events.map(&:type) }).to include("fizzled")
  end

  it "X target creatures an opponent controls, then a token copy of each (the Dominion Infiltration shape)" do
    game = game_with(hand: ["Spec Shapeshift Raid"], opponent: ["Hill Giant", "Gray Ogre"])
    cast(game, "Spec Shapeshift Raid")
    game.submit(type: "x", value: 2)
    game.submit(type: "target", target: obj_id(game, "Hill Giant"))
    game.submit(type: "target", target: obj_id(game, "Gray Ogre"))
    pay(game)
    pass_both(game)
    tokens = game.state.battlefield.select { game.state.object(it).controller.zero? && engine(game).token?(game.state.object(it)) }
    expect(tokens.size).to eq(2)
    expect(tokens.map { engine(game).chars(it).keywords }).to all(include(:changeling, :haste))
    skip_to(game, :end)
    pass_both(game)
    expect(game.state.battlefield.count { engine(game).token?(game.state.object(it)) }).to eq(0)
  end

  it "divides among any number of targets: at least one, at most the amount (CR 601.2d)" do
    game = game_with(hand: ["Spec Blessing Fan"], board: ["Hill Giant", "Gray Ogre", "Craw Wurm", "Moss Grower"])
    cast(game, "Spec Blessing Fan")
    expect(game.legal_options.map { it[:count] }).to eq([1, 2, 3, nil])
    game.submit(type: "count", count: 2)
    game.submit(type: "target", target: obj_id(game, "Hill Giant"))
    game.submit(type: "target", target: obj_id(game, "Gray Ogre"))
    expect(game.pending_decision.kind).to eq("distribute")
    game.submit(type: "assign", target: obj_id(game, "Gray Ogre"))
    pay(game)
    pass_both(game)
    expect(game.state.object(obj_id(game, "Gray Ogre")).counters).to eq("+1/+1" => 2)
  end

  it "a copy keeps the number of targets and may change each (CR 707.10c)" do
    game = game_with(hand: ["Spec Mass Freeze", "Spec Echo Mirror"], opponent: ["Hill Giant", "Gray Ogre", "Craw Wurm"], lands: 5)
    cast(game, "Spec Mass Freeze")
    game.submit(type: "x", value: 2)
    game.submit(type: "target", target: obj_id(game, "Hill Giant"))
    game.submit(type: "target", target: obj_id(game, "Gray Ogre"))
    pay(game)
    cast(game, "Spec Echo Mirror")
    game.submit(type: "target", target: game.state.stack.find { game.state.object(it).card == "spec_mass_freeze" })
    pay(game)
    pass_both(game)
    expect(game.legal_options.size).to be >= 2
    game.submit(type: "target", target: obj_id(game, "Hill Giant"))
    game.submit(type: "target", target: obj_id(game, "Craw Wurm"))
    copy = game.state.stack.first
    expect(game.state.object(copy).targets).to eq([[obj_id(game, "Hill Giant"), obj_id(game, "Craw Wurm")]])
  end

  describe "validation and text" do
    def errors_for(target)
      Enjine::CardDefinition.from_h({ "name" => "Spec Bad", "mana_cost" => "{1}", "types" => ["sorcery"],
                                      "abilities" => [{ "spell" => { "targets" => [target], "effects" => [] } }] })
      []
    rescue Enjine::InvalidCardDefinition => e
      e.errors
    end

    it "reports path-addressed errors" do
      expect(errors_for({ "filter" => "creature", "count" => 0 }))
        .to include(a_string_including("abilities[0].spell.targets[0].count: must be an integer >= 1"))
      expect(errors_for({ "filter" => "creature", "count" => "some" })).to include(a_string_including("targets[0].count"))
    end

    it "describes the count" do
      spec = ->(data) { Enjine::Mechanics::Abilities::TargetSpec.build(data, [], "t", 0).to_s }
      expect(spec.call({ "filter" => "creature", "count" => "any" })).to eq("any number of creature")
      expect(spec.call({ "filter" => "creature", "count" => "x" })).to eq("X creature")
      expect(spec.call({ "filter" => "creature", "count" => 2, "optional" => true })).to eq("up to 2 creature")
      expect(spec.call({ "filter" => "creature", "optional" => true })).to eq("up to one creature")
    end
  end
end
