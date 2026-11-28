# frozen_string_literal: true

# Harness (CR 701.64), ∞ abilities (CR 702.186) and the "exile a permanent you control" cost (CR 601.2h).
# Invented test cards only.
RSpec.describe "Harness, ∞ abilities and exiling a permanent as a cost (CR 701.64, 702.186)" do
  let(:stone) do
    { "name" => "Spec Spirit Gem", "mana_cost" => "{1}", "types" => ["artifact"], "supertypes" => ["legendary"],
      "abilities" => [
        { "activated" => { "cost" => [{ "mana" => "{1}" }, "tap", { "exile_permanent" => { "filter" => "creature" } }],
                           "effects" => [{ "harness" => {} }, { "gain_life" => { "amount" => { "sacrificed" => "power" } } }] } },
        { "infinity" => { "triggered" => { "when" => { "step_begins" => { "step" => "upkeep", "whose" => "your" } },
                                           "effects" => [{ "gain_life" => { "amount" => 3 } }] } } },
        { "infinity" => { "static" => { "affects" => { "each" => "creature", "controller" => "you" },
                                        "keywords" => ["flying"] } } }
      ] }
  end
  let(:catalog) { catalog_with(stone) }

  def pay_all(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, name) = game.view_for(:observer)["players"].find { it["name"] == name }["life"]
  def stone_id(game) = obj_id(game, "Spec Spirit Gem")

  def board
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Spec Spirit Gem", "Plains", "Grizzly Bears", "Grizzly Bears"
        library "Forest", count: 10
      end
      player("bob") do
        battlefield "Grizzly Bears"
        library "Forest", count: 10
      end
    end
  end

  it "exiles a creature you control to pay the cost (not a sacrifice), then the permanent becomes harnessed (CR 701.64a)" do
    game = board
    bears = game.state.battlefield.select { game.state.object(it).card == "grizzly_bears" && game.state.object(it).controller.zero? }
    theirs = game.state.battlefield.find { game.state.object(it).card == "grizzly_bears" && game.state.object(it).controller == 1 }
    game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == stone_id(game) })
    expect(game.legal_options.map { it[:object] }).to include(*bears)
    expect(game.legal_options.map { it[:object] }).not_to include(theirs) # only a creature you control
    game.submit(type: "cost", object: bears.first)
    pay_all(game)
    expect(game.state.exile.map { game.state.object(it).card }).to eq(["grizzly_bears"])
    expect(engine(game).turn_log(0)["sacrificed"]).to be_nil
    pass_both(game)
    stone = game.state.object(stone_id(game))
    expect(engine(game).designated?(stone, "harnessed")).to be(true)
    expect(life(game, "alice")).to eq(22) # the exiled creature's last known power
    expect(engine(game).chars(game.state.object(bears.last)).keyword?(:flying)).to be(true) # CR 702.186b
    expect(engine(game).chars(game.state.object(theirs)).keyword?(:flying)).to be(false)
  end

  it "∞ abilities don't work while it isn't harnessed, and a triggered one works once it is (CR 702.186b)" do
    game = board
    skip_to(game, :upkeep, turn: 5)
    expect(game.state.stack).to be_empty
    expect(life(game, "alice")).to eq(20)
    engine(game).designate!(game.state.object(stone_id(game)), "harnessed")
    skip_to(game, :upkeep, turn: 7)
    expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Spec Spirit Gem ability"])
    pass_both(game)
    expect(life(game, "alice")).to eq(23)
  end

  it "a harnessed permanent stays harnessed until it leaves the battlefield (CR 701.64b)" do
    game = board
    stone = game.state.object(stone_id(game))
    engine(game).designate!(stone, "harnessed")
    expect(game.view_for("bob")["battlefield"].find { it["id"] == stone.id }["designations"]).to eq(["harnessed"])
    fresh = engine(game).move!(stone.id, :hand, reason: "test")
    expect(engine(game).designated?(fresh, "harnessed")).to be(false)
  end
end
