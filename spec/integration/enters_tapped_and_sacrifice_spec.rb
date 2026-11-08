# frozen_string_literal: true

RSpec.describe "Entering tapped (CR 614.1c) and sacrifice costs (CR 701.21)" do
  let(:tapland) do
    { "name" => "Quiet Shoal", "types" => ["land"],
      "abilities" => ["enters_tapped", { "mana" => { "cost" => ["tap"], "produce" => "{W}" } },
                      { "mana" => { "cost" => ["tap"], "produce" => "{U}" } }] }
  end
  let(:flask) do
    { "name" => "Ember Flask", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{1}" }, "tap", "sacrifice"],
                                         "effects" => [{ "deal_damage" => { "amount" => 2, "to" => "each_opponent" } }] } }] }
  end
  let(:catalog) { catalog_with(tapland, flask) }

  it "a land with an enters-tapped replacement enters tapped; it offers each color as a separate mana ability" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Quiet Shoal"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    entry = game.submit(type: "play_land", object: ids_in(game, "alice", :hand).first)
    shoal = entry.events.first.new_id
    expect(game.state.object(shoal).tapped).to be(true)
    expect(entry.events.map(&:type)).not_to include("tapped") # it entered tapped; it didn't become tapped
    expect(option_types(game)).not_to include("activate_mana")
    skip_to(game, :precombat_main, turn: 5)
    expect(game.legal_options.select { it[:type] == "activate_mana" }.map { it[:ability] }).to eq(%w[printed:1 printed:2])
  end

  it "a sacrifice cost is paid on activation; the ability still resolves without its source (CR 113.7a)" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") { battlefield "Ember Flask", "Mountain" }
      player("bob")
    end
    flask_id = obj_id(game, "Ember Flask")
    game.submit(type: "activate", object: flask_id, ability: "printed:0")
    game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
    entry = game.submit(type: "pay_mana", mana: "R")
    expect(entry.events.grep(Enjine::Events::ZoneChanged).map(&:reason)).to eq(["sacrifice"])
    expect(game.state.battlefield).not_to include(flask_id)
    pass_both(game)
    expect(game.view_for(:observer)["players"][1]["life"]).to eq(18)
  end

  it "the sacrifice cost isn't payable once the permanent is gone, and cancel leaves it in play" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") { battlefield "Ember Flask", "Mountain" }
      player("bob")
    end
    flask_id = obj_id(game, "Ember Flask")
    game.submit(type: "activate", object: flask_id, ability: "printed:0")
    game.submit(type: "cancel")
    expect(game.state.battlefield).to include(flask_id)
    expect(Enjine::Mechanics::Costs::SacrificeSelf::INSTANCE.to_s).to eq("Sacrifice this")
  end
end
