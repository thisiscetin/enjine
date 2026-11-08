# frozen_string_literal: true

RSpec.describe "Tokens (CR 111, 701.7)" do
  let(:muster) do
    { "name" => "Muster the Guard", "mana_cost" => "{1}{W}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "create_token" => {
        "token" => { "name" => "Guard", "types" => ["creature"], "subtypes" => ["soldier"], "power" => 1, "toughness" => 1 },
        "amount" => 2
      } }] } }] }
  end
  let(:prospector) do
    { "name" => "Spec Prospector", "mana_cost" => "{R}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} },
                                         "effects" => [{ "create_token" => { "token" => "Treasure" } }] } }] }
  end
  let(:catalog) { catalog_with(muster, prospector) }

  def board(&)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      instance_eval(&)
    end
  end

  def tokens(game, name) = game.view_for(:observer)["battlefield"].select { it["name"] == name }

  it "creates creature tokens that enter the battlefield and can attack next turn" do
    game = board do
      player("alice") do
        hand "Muster the Guard"
        battlefield "Plains", "Plains"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.state.battlefield.select { game.state.object(it).card == "plains" }.each do |land|
      game.submit(type: "activate_mana", object: land, ability: "intrinsic:plains")
      game.submit(game.legal_options.find { it[:type] == "pay_mana" })
    end
    entry = nil
    2.times { entry = game.submit(type: "pass") }
    expect(entry.events.select { it.is_a?(Enjine::Events::ZoneChanged) && it.reason == "create_token" }.size).to eq(2)
    expect(tokens(game, "Guard").map { it.values_at("power", "toughness", "summoning_sick") }).to eq([[1, 1, true]] * 2)
  end

  it "a token that leaves the battlefield ceases to exist, after its dies event (CR 704.5d)" do
    game = board do
      player("alice") do
        hand "Lightning Bolt"
        battlefield "Mountain"
      end
      player("bob")
    end
    guard_def = Enjine::CardDefinition.from_h(muster).token_definitions.first
    engine = game.instance_variable_get(:@engine)
    guard = engine.create_token!(guard_def, 1).id
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: guard)
    game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
    game.submit(type: "pay_mana", mana: "R")
    entry = nil
    2.times { entry = game.submit(type: "pass") }
    types = entry.events.map(&:type)
    expect(types.index("zone_changed")).to be < types.index("token_ceased")
    expect(game.state.players[1].graveyard).to be_empty
    expect(Enjine::Snapshot.validate(game.state.to_h, catalog)).to eq([])
  end

  it "Treasure: tap and sacrifice for one mana of any color, usable to pay costs (CR 111.10a)" do
    game = board do
      player("alice") do
        hand "Spec Prospector", "Counterspell"
        battlefield "Mountain", "Island"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
    game.submit(type: "pay_mana", mana: "R")
    pass_both(game) # Prospector enters; its trigger goes on the stack
    pass_both(game) # the trigger resolves: a Treasure
    treasure = tokens(game, "Treasure").first["id"]
    options = game.legal_options.select { it[:type] == "activate_mana" && it[:object] == treasure }
    expect(options.map { it[:ability] }).to eq(%w[printed:0 printed:1 printed:2 printed:3 printed:4])
    game.submit(type: "activate_mana", object: treasure, ability: "printed:1") # {U}
    expect(game.state.players[0].mana_pool[:U]).to eq(1)
    expect(tokens(game, "Treasure")).to be_empty
  end

  it "counts a Treasure as a source of any color when deciding what is castable" do
    game = board do
      player("alice") do
        hand "Counterspell"
        battlefield "Island"
      end
      player("bob") { hand "Lightning Bolt" }
    end
    engine = game.instance_variable_get(:@engine)
    treasure_def = Enjine::CardDefinition.from_h(prospector).token_definitions.first
    engine.create_token!(treasure_def, 0)
    counter = ids_in(game, "alice", :hand).first
    expect(engine.affordable?(0, Enjine::Mana::Cost.parse("{U}{U}"), nil)).to be(true)
    expect(engine.affordable?(0, Enjine::Mana::Cost.parse("{U}{U}{U}"), nil)).to be(false)
    expect(engine.affordable?(0, Enjine::Mana::Cost.parse("{R}{U}"), nil)).to be(true)
    expect(counter).to be_a(String)
  end

  it "validates token data and describes the effect" do
    bad = muster.merge("abilities" => [{ "spell" => { "effects" => [{ "create_token" => { "token" => "Dragon Egg" } }] } }])
    expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition, /predefined token/)
    worse = muster.merge("abilities" => [{ "spell" => { "effects" => [{ "create_token" => { "token" => { "name" => "X" } } }] } }])
    expect { Enjine::CardDefinition.from_h(worse) }.to raise_error(Enjine::InvalidCardDefinition, /token\.types/)
    expect(Enjine::CardDefinition.from_h(muster).spell_ability.to_s).to eq("create 2 Guard tokens → you")
    expect(Enjine::CardDefinition.from_h(muster).token_definitions.first).to be_token
  end
end
