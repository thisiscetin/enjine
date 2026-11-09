# frozen_string_literal: true

# CR 734.1 (Handling Illegal Actions): an unfinished cast is rewound by cancelling it. Enjine offers that
# only until something irreversible is paid: a mana ability whose cost is more than {T} (a Treasure's
# sacrifice, CR 605.3, 111.10a) can't be undone, so from then on no casting decision offers "cancel".
RSpec.describe "Cancelling a cast after paying an irreversible cost (CR 734.1, 605.3)" do
  let(:prospector) do
    { "name" => "Spec Prospector", "mana_cost" => "{R}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} },
                                         "effects" => [{ "create_token" => { "token" => "Treasure" } }] } }] }
  end
  let(:insight) do
    { "name" => "Spec Twin Insight", "mana_cost" => "{U}{U}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
  end
  let(:catalog) { catalog_with(prospector, insight) }

  def treasure_game(hand: ["Counterspell", "Lightning Bolt"], lands: ["Island"])
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand(*hand)
        battlefield(*lands)
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    engine = game.instance_variable_get(:@engine)
    engine.create_token!(Enjine::CardDefinition.from_h(prospector).token_definitions.first, 0)
    Enjine::Game.import({ "state" => game.state.to_h }, catalog: catalog)
  end

  def treasure(game) = game.state.battlefield.find { game.state.object(it).card.include?("treasure") }
  def bolt(game) = ids_in(game, "alice", :hand).find { game.state.object(it).card == "lightning_bolt" }

  it "no longer offers cancel once a Treasure was sacrificed for mana, and the cast can still finish" do
    game = treasure_game
    game.submit(type: "cast", object: bolt(game))
    expect(option_types(game)).to include("cancel")
    game.submit(type: "target", target: "player:bob")
    game.submit(type: "activate_mana", object: treasure(game), ability: "printed:3") # {R}
    expect(game.state.frames.last["irreversible"]).to be(true)
    expect(option_types(game)).not_to include("cancel")
    expect(game.legal_options).to include({ type: "pay_mana", mana: "R" })
    game.submit(type: "pay_mana", mana: "R")
    expect(game.state.stack.size).to eq(1)
    expect(game.pending_decision.kind).to eq("priority")
  end

  it "only offers mana abilities and payments that keep the rest of the cost payable once it's irreversible" do
    game = treasure_game
    game.submit(type: "cast", object: bolt(game))
    game.submit(type: "target", target: "player:bob")
    # Only the {R} Treasure ability pays a Bolt: the other colors would strand the payment.
    treasure_options = game.legal_options.select { it[:object] == treasure(game) }
    expect(treasure_options.map { it[:ability] }).to eq(["printed:3"])
  end

  it "doesn't count the ability's own {T} source when checking an irreversible mana ability keeps the cost payable" do
    cache = { "name" => "Spec Cache", "types" => ["land"],
              "abilities" => [{ "mana" => { "cost" => ["tap"], "produce" => "{B}" } },
                              { "activated" => { "cost" => [{ "mana" => "{B}" }, "tap"],
                                                 "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
    crossroads = { "name" => "Spec Crossroads", "types" => ["land"],
                   "abilities" => [{ "mana" => { "cost" => ["tap", { "pay_life" => 1 }], "color" => "any_one" } }] }
    game = build_game(catalog_with(cache, crossroads)) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Spec Cache", "Spec Crossroads"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    game.submit(type: "activate", object: obj_id(game, "Spec Cache"), ability: "printed:1")
    colors = game.legal_options.select { it[:object] == obj_id(game, "Spec Crossroads") }.map { it[:mana] }
    expect(colors).to eq(["{B}"]) # any other color would strand {B}: the Cache taps for its own cost
  end

  it "after a Treasure, a pool mana that would strand a colored symbol isn't offered" do
    game = treasure_game(hand: ["Spec Twin Insight"], lands: ["Island"])
    game.state.players[0].mana_pool[:R] = 1 # left over from earlier
    game = Enjine::Game.import({ "state" => game.state.to_h }, catalog: catalog)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    expect(game.legal_options).not_to include({ type: "pay_mana", mana: "R" }) # {U}{U}: red pays nothing
    treasure_options = game.legal_options.select { it[:object] == treasure(game) }
    expect(treasure_options.map { it[:ability] }).to eq(["printed:1"]) # only {U} keeps {U}{U} payable
    game.submit(type: "activate_mana", object: treasure(game), ability: "printed:1")
    expect(option_types(game)).not_to include("cancel")
    game.submit(type: "pay_mana", mana: "U")
    expect(game.legal_options.map { it[:type] }).to eq(["activate_mana"])
  end

  it "a tap-only payment can still be cancelled: sources untap and the pool is restored" do
    game = treasure_game(hand: ["Lightning Bolt"], lands: ["Mountain"])
    mountain = obj_id(game, "Mountain")
    game.submit(type: "cast", object: bolt(game))
    game.submit(type: "target", target: "player:bob")
    game.submit(type: "activate_mana", object: mountain, ability: "intrinsic:mountain")
    expect(game.state.frames.last["irreversible"]).to be_nil
    expect(option_types(game)).to include("cancel")
    game.submit(type: "cancel")
    expect(game.state.object(mountain).tapped).to be(false)
    expect(game.state.players[0].mana_pool[:R]).to eq(0)
    expect(ids_in(game, "alice", :hand).size).to eq(1)
    expect(treasure(game)).not_to be_nil
  end

  it "keeps the irreversible flag through export and import" do
    game = treasure_game
    game.submit(type: "cast", object: bolt(game))
    game.submit(type: "target", target: "player:bob")
    game.submit(type: "activate_mana", object: treasure(game), ability: "printed:3")
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.state.frames.last["irreversible"]).to be(true)
    expect(Enjine::Snapshot.validate(copy.state.to_h, catalog)).to eq([])
    expect(option_types(copy)).not_to include("cancel")
  end

  it "the random agent never picks a cancel that isn't offered" do
    game = treasure_game
    game.submit(type: "cast", object: bolt(game))
    game.submit(type: "target", target: "player:bob")
    game.submit(type: "activate_mana", object: treasure(game), ability: "printed:3")
    agent = Enjine::Agents::Random.new(seed: 3, cancel_rate: 1.0)
    10.times { expect(agent.choose(game.pending_decision)).not_to eq(type: "cancel") }
  end

  it "drops abilities that triggered during a cast that is cancelled (CR 734.1)" do
    game = treasure_game(hand: ["Lightning Bolt"], lands: ["Mountain"])
    engine = game.instance_variable_get(:@engine)
    game.submit(type: "cast", object: bolt(game))
    engine.state.pending_triggers << { "id" => "t999", "controller" => 1, "source" => nil, "card" => "forest",
                                       "ability" => "x", "event" => {}, "memory" => {} }
    game.submit(type: "target", target: "player:bob")
    game.submit(type: "cancel")
    expect(game.state.pending_triggers).to be_empty
  end
end
