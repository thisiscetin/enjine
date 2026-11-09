# frozen_string_literal: true

# Vehicles and crew (CR 301.7, 702.122) and type-changing effects (CR 205.1b, 613.1d-e, 208.3).
RSpec.describe "Vehicles, crew and type-changing effects" do
  let(:wagon) do
    { "name" => "Clanktrap Hauler", "mana_cost" => "{2}", "types" => ["artifact"], "subtypes" => ["vehicle"],
      "power" => 4, "toughness" => 3, "keywords" => ["trample"],
      "abilities" => [{ "crew" => { "power" => 3 } },
                      { "triggered" => { "when" => { "becomes_crewed" => {} },
                                         "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
  end
  let(:hand) do
    { "name" => "Hauler Hand", "mana_cost" => "{G}", "types" => ["creature"], "subtypes" => ["human"], "power" => 1,
      "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "crews_vehicle" => {} },
                                         "effects" => [{ "pump" => { "power" => 2, "toughness" => 0,
                                                                     "to" => { "triggering" => "object" } } }] } }] }
  end
  let(:lurker) do
    { "name" => "Brasswork Prowler", "mana_cost" => "{3}", "types" => ["artifact"], "subtypes" => ["vehicle"],
      "power" => 3, "toughness" => 3,
      "abilities" => [{ "static" => { "affects" => "self", "if" => { "not" => { "your_turn" => true } },
                                      "types" => %w[artifact creature] } },
                      { "crew" => { "power" => 1 } }] }
  end
  let(:ridge) do
    { "name" => "Ashvault Ridge", "types" => ["land"],
      "abilities" => [{ "mana" => { "cost" => ["tap"], "produce" => "{R}" } },
                      { "activated" => { "cost" => [{ "mana" => "{1}" }],
                                         "effects" => [{ "become" => { "types" => ["creature"], "creature_types" => ["elemental"],
                                                                       "colors" => ["R"], "keywords" => ["haste"],
                                                                       "base_power_toughness" => { "power" => 3, "toughness" => 1 },
                                                                       "to" => "self" } }] } }] }
  end
  let(:catalog) { catalog_with(wagon, hand, lurker, ridge) }

  def engine(game) = game.instance_variable_get(:@engine)
  def crew(id) = { type: "activate", object: id, ability: "printed:0" }
  def life(game, name) = game.view_for(:observer)["players"].find { it["name"] == name }["life"]

  def board(alice:, step: :precombat_main, active: "alice")
    build_game(catalog) do
      turn 3, active: active, step: step
      player("alice") do
        alice.each { |card, opts| battlefield card, **(opts || {}) }
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
  end

  it "an uncrewed Vehicle is a noncreature artifact without power and toughness (CR 301.7a, 208.3)" do
    game = board(alice: [["Clanktrap Hauler"]])
    wagon = obj_id(game, "Clanktrap Hauler")
    expect(engine(game).chars(wagon)).to have_attributes(types: [:artifact], power: nil, toughness: nil)
    expect(view_of(game, wagon)).not_to have_key("power")
    expect(game.catalog.fetch("clanktrap_hauler").power).to eq(4) # printed, and the card keeps it off the battlefield
  end

  it "crew taps other creatures with total power N or more, one at a time, then it's an artifact creature (CR 702.122a)" do
    game = board(alice: [["Clanktrap Hauler"], ["Grizzly Bears"], ["Hauler Hand", { controlled_since: 3 }], ["Hill Giant"]])
    wagon = obj_id(game, "Clanktrap Hauler")
    bears = obj_id(game, "Grizzly Bears")
    hand = obj_id(game, "Hauler Hand")
    giant = obj_id(game, "Hill Giant")
    game.submit(crew(wagon))
    expect(game.pending_decision).to have_attributes(kind: "choose_cost")
    expect(game.legal_options).to eq([{ type: "cost", object: bears }, { type: "cost", object: hand },
                                      { type: "cost", object: giant }, { type: "cancel" }])
    game.submit(type: "cost", object: bears)
    expect(game.legal_options).not_to include(type: "done") # 2 power isn't enough
    game.submit(type: "cost", object: hand) # summoning sick, but crewing isn't its {T} ability (CR 302.6)
    expect(game.legal_options).to include({ type: "done" }, { type: "cost", object: giant }) # may tap more than needed
    game.submit(type: "done")
    expect(game.state.stack.size).to eq(2) # the crew ability and Hauler Hand's "crews a Vehicle" trigger
    pass_both(game) # the trigger: the Vehicle gets +2/+0, though it isn't a creature yet (CR 611.2c)
    expect(engine(game).chars(wagon).power).to be_nil
    pass_both(game) # the crew ability resolves
    expect(engine(game).chars(wagon)).to have_attributes(types: %i[artifact creature], power: 6, toughness: 3) # 4/3 +2/+0
    expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Clanktrap Hauler ability"]) # becomes crewed
    pass_both(game)
    expect(life(game, "alice")).to eq(21)
    expect(game.state.object(giant).tapped).to be(false)
  end

  it "a pump from before it was a creature applies once it is one (CR 613.4c, 301.7b)" do
    game = board(alice: [["Clanktrap Hauler"], ["Hauler Hand"], ["Hill Giant"]])
    wagon = obj_id(game, "Clanktrap Hauler")
    game.submit(crew(wagon))
    game.submit(type: "cost", object: obj_id(game, "Hauler Hand"))
    game.submit(type: "cost", object: obj_id(game, "Hill Giant")) # nothing left to tap: done by itself
    pass_both(game, 3)
    expect(engine(game).power_toughness(engine(game).object(wagon))).to eq([6, 3])
  end

  it "cancelling untaps the creatures and nothing crews (CR 734.1, 702.122b)" do
    game = board(alice: [["Clanktrap Hauler"], ["Hauler Hand"], ["Hill Giant"]])
    hand = obj_id(game, "Hauler Hand")
    game.submit(crew(obj_id(game, "Clanktrap Hauler")))
    game.submit(type: "cost", object: hand)
    game.submit(type: "cancel")
    expect(game.state.object(hand).tapped).to be(false)
    expect(game.state.stack).to be_empty
    expect(game.state.pending_triggers).to be_empty
  end

  it "isn't offered without enough untapped power, and a Vehicle can't crew itself (CR 702.122a)" do
    game = board(alice: [["Clanktrap Hauler"], ["Grizzly Bears"], ["Hill Giant", { tapped: true }]])
    expect(game.legal_options).not_to include(crew(obj_id(game, "Clanktrap Hauler")))
  end

  it "becomes a creature until end of turn only (CR 514.2)" do
    game = board(alice: [["Clanktrap Hauler"], ["Hill Giant"]], step: :end)
    wagon = obj_id(game, "Clanktrap Hauler")
    game.submit(crew(wagon))
    game.submit(type: "cost", object: obj_id(game, "Hill Giant"))
    pass_both(game, 2)
    expect(engine(game).chars(wagon).creature?).to be(true)
    skip_to(game, :upkeep, turn: 4)
    expect(engine(game).chars(wagon).creature?).to be(false)
  end

  it "a static ability can make it an artifact creature (\"during turns other than yours\", CR 205.1b)" do
    mine = board(alice: [["Brasswork Prowler"]])
    expect(engine(mine).chars(obj_id(mine, "Brasswork Prowler")).creature?).to be(false)
    theirs = board(alice: [["Brasswork Prowler"]], active: "bob")
    expect(engine(theirs).chars(obj_id(theirs, "Brasswork Prowler")))
      .to have_attributes(types: %i[artifact creature], power: 3, toughness: 3)
  end

  it "a manland becomes a red Elemental creature with haste and stays a land (CR 205.1b, 613.1d-e)" do
    game = board(alice: [["Ashvault Ridge"], ["Forest"]])
    ridge = obj_id(game, "Ashvault Ridge")
    game.submit(type: "activate", object: ridge, ability: "printed:1")
    game.submit(type: "activate_mana", object: obj_id(game, "Forest"), ability: "intrinsic:forest")
    game.submit(type: "pay_mana", mana: "G")
    pass_both(game)
    expect(engine(game).chars(ridge)).to have_attributes(types: %i[land creature], subtypes: [:elemental], colors: [:R],
                                                         power: 3, toughness: 1)
    expect(engine(game).chars(ridge).keyword?(:haste)).to be(true)
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.instance_variable_get(:@engine).chars(ridge).creature?).to be(true)
  end
end
