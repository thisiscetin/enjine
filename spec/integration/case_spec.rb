# frozen_string_literal: true

# Case cards: "To solve" and "Solved" (CR 720.3, 702.169). Invented test cards only.
RSpec.describe "Cases: to solve and solved (CR 720.3, 702.169)" do
  let(:case_card) do
    { "name" => "Spec Case of the Feast", "mana_cost" => "{W}", "types" => ["enchantment"], "subtypes" => ["case"],
      "abilities" => [
        { "to_solve" => { "amount" => { "life_gained_this_turn" => "you" }, "at_least" => 5 } },
        { "solved" => { "activated" => { "cost" => [{ "mana" => "{1}" }], "effects" => [{ "draw" => { "amount" => 1 } }] } } },
        { "solved" => { "static" => { "affects" => { "each" => "creature", "controller" => "you" },
                                      "pump" => { "power" => 1, "toughness" => 1 } } } },
        { "solved" => { "triggered" => { "when" => { "step_begins" => { "step" => "upkeep", "whose" => "your" } },
                                         "effects" => [{ "gain_life" => { "amount" => 1 } }] } } }
      ] }
  end
  let(:feast) do
    { "name" => "Spec Feast", "mana_cost" => "{W}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "gain_life" => { "amount" => 5 } }] } }] }
  end
  let(:catalog) { catalog_with(case_card, feast) }

  def pay_all(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, name) = game.view_for(:observer)["players"].find { it["name"] == name }["life"]
  def case_id(game) = obj_id(game, "Spec Case of the Feast")
  def solved?(game) = engine(game).designated?(game.state.object(case_id(game)), "solved")

  def board(hand: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand.each { hand it }
        battlefield "Spec Case of the Feast", "Plains", "Plains", "Grizzly Bears"
        library "Forest", count: 10
      end
      player("bob") { library "Forest", count: 10 }
    end
  end

  def cast_feast(game)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay_all(game)
    pass_both(game)
  end

  def activations(game) = game.legal_options.select { it[:type] == "activate" && it[:object] == case_id(game) }

  it "becomes solved at the beginning of your end step if its condition holds (CR 720.3a), then its Solved abilities work" do
    game = board(hand: ["Spec Feast"])
    expect(activations(game)).to be_empty # CR 702.169d: activate only if solved
    expect(engine(game).power(game.state.object(obj_id(game, "Grizzly Bears")))).to eq(2)
    cast_feast(game)
    expect(life(game, "alice")).to eq(25)
    skip_to(game, :end)
    expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Spec Case of the Feast ability"])
    pass_both(game)
    expect(solved?(game)).to be(true)
    expect(game.view_for(:observer)["battlefield"].find { it["id"] == case_id(game) }["designations"]).to eq(["solved"])
    expect(engine(game).power(game.state.object(obj_id(game, "Grizzly Bears")))).to eq(3) # CR 702.169b
    expect(activations(game)).not_to be_empty
  end

  it "doesn't become solved when its condition fails at the end step (intervening if, CR 603.4)" do
    game = board
    skip_to(game, :end)
    expect(game.state.stack).to be_empty
    expect(solved?(game)).to be(false)
  end

  it "a Solved triggered ability triggers only while solved (CR 702.169c); the designation is lost when it leaves (CR 720.3b)" do
    game = board
    engine(game).designate!(game.state.object(case_id(game)), "solved")
    expect(engine(game).designate!(game.state.object(case_id(game)), "solved")).to be(false) # already solved
    skip_to(game, :upkeep, turn: 5)
    expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Spec Case of the Feast ability"])
    pass_both(game)
    expect(life(game, "alice")).to eq(21)
    fresh = engine(game).move!(case_id(game), :hand, reason: "test")
    expect(engine(game).designated?(fresh, "solved")).to be(false)
  end

  it "survives an export/import round trip" do
    game = board
    engine(game).designate!(game.state.object(case_id(game)), "solved")
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.instance_variable_get(:@engine).designated?(copy.state.object(case_id(copy)), "solved")).to be(true)
  end
end
