# frozen_string_literal: true

# Costs chosen while casting or activating (CR 601.2h, 602.2b) and activation restrictions (CR 602.5b).
RSpec.describe "Cost choices and activation restrictions (CR 601.2h, 602.2b, 602.5b)" do
  def klingons = { "creature" => { "subtypes" => ["klingon"] } }
  def draw_one = [{ "draw" => { "amount" => 1 } }]

  def card(name, extra) = { "name" => name, "types" => ["creature"], "power" => 1, "toughness" => 1, "mana_cost" => "{B}" }.merge(extra)

  let(:warlord) do
    card("Spec Klingon Warlord", "subtypes" => ["klingon"], "abilities" => [{ "activated" => {
           "cost" => [{ "mana" => "{1}" }, { "sacrifice_permanent" => { "filter" => "creature" } }],
           "effects" => [{ "add_counters" => { "counter" => "+1/+1", "amount" => 1,
                                               "to" => { "each" => klingons, "controller" => "you" } } }]
         } }])
  end
  let(:chancellor) do
    card("Spec Battle Chancellor", "abilities" => [{ "activated" => {
           "cost" => [{ "sacrifice_permanent" => { "filter" => "creature", "other" => true } }],
           "effects" => [{ "grant" => { "keywords" => ["trample"], "to" => "self" } },
                         { "draw" => { "amount" => 1, "if" => { "sacrificed" => { "subtypes" => ["klingon"] } } } }]
         } }])
  end
  let(:trimatrix) do
    card("Spec Drone Matrix", "types" => %w[artifact creature], "abilities" => [{ "activated" => {
           "cost" => [{ "tap_permanents" => { "count" => 3, "filter" => { "creature" => { "types" => ["artifact"] } } } }],
           "effects" => [{ "draw" => { "amount" => 1 } }, { "lose_life" => { "amount" => 1, "to" => "you" } }]
         } }])
  end
  let(:android) do
    card("Spec Counter Android", "abilities" => [{ "activated" => {
           "cost" => [{ "mana" => "{1}" }, { "remove_counters" => { "count" => 3 } }],
           "effects" => [{ "draw" => { "amount" => 1 } }]
         } }])
  end
  let(:drone) do
    grave_cost = [{ "mana" => "{1}" }, "exile_self_from_graveyard"]
    card("Spec Grave Drone", "keywords" => ["lifelink"],
                             "abilities" => [{ "activated" => { "cost" => grave_cost, "effects" => draw_one } }])
  end
  let(:agent) do
    card("Spec Time Agent",
         "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{1}" }, "bottom_self_from_graveyard"],
                                            "effects" => [{ "gain_life" => { "amount" => 2 } }] } }])
  end
  let(:squad) do
    card("Spec Repair Squad", "abilities" => [{ "activated" => {
           "cost" => [{ "mana" => "{1}" }], "targets" => ["creature"], "timing" => "sorcery", "limit" => "once_each_turn",
           "effects" => [{ "untap" => { "to" => { "target" => 0 } } }]
         } }])
  end
  let(:captain) do
    card("Spec Turn Captain", "abilities" => [{ "activated" => {
           "cost" => [{ "mana" => "{1}" }], "timing" => "your_turn", "only_if" => { "life" => "you", "at_most" => 10 },
           "effects" => [{ "gain_life" => { "amount" => 1 } }]
         } }])
  end
  let(:orphan) do
    card("Spec Land Eater", "abilities" => [{ "activated" => {
           "cost" => [{ "mana" => "{1}" },
                      { "sacrifice_permanent" => { "filter" => "land" } }], "effects" => [{ "draw" => { "amount" => 1 } }]
         } }])
  end
  let(:catalog) { catalog_with(warlord, chancellor, trimatrix, android, drone, agent, squad, captain, orphan) }

  def board(life: 20, &)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", life: life) { instance_eval(&) }
      player("bob") { library "Forest", count: 5 }
    end
  end

  def activate(game, name, zone: :battlefield)
    id = zone == :battlefield ? obj_id(game, name) : obj_id(game, name, zone: zone, player: "alice")
    option = game.legal_options.find { it[:type] == "activate" && it[:object] == id }
    raise "#{name} can't be activated: #{game.legal_options}" unless option

    game.submit(option)
  end

  def pay_generic(game)
    land = game.legal_options.find { it[:type] == "activate_mana" }
    game.submit(land)
    game.submit(game.legal_options.find { it[:type] == "pay_mana" })
  end

  it "sacrifices a chosen creature as the ability becomes activated, after paying mana (CR 601.2h)" do
    game = board do
      battlefield "Spec Klingon Warlord", "Grizzly Bears", "Swamp"
      library "Forest", count: 3
    end
    activate(game, "Spec Klingon Warlord")
    expect(game.pending_decision.kind).to eq("choose_cost")
    expect(game.legal_options.map { it[:object] }).to include(obj_id(game, "Grizzly Bears"), obj_id(game, "Spec Klingon Warlord"))
    bears = obj_id(game, "Grizzly Bears")
    game.submit(type: "cost", object: bears)
    expect(game.state.battlefield).to include(bears) # not yet: sacrificed as it becomes activated
    pay_generic(game)
    expect(game.state.battlefield).not_to include(bears)
    expect(game.state.object(game.state.stack.first).paid.first).to include("object" => bears, "types" => ["creature"])
    pass_both(game)
    expect(game.state.object(obj_id(game, "Spec Klingon Warlord")).counters).to eq("+1/+1" => 1)
  end

  it "may tap a land for mana and then sacrifice that land (CR 601.2g-h)" do
    game = board do
      battlefield "Spec Land Eater", "Swamp"
      library "Forest", count: 3
    end
    swamp = obj_id(game, "Swamp")
    activate(game, "Spec Land Eater")
    game.submit(type: "cost", object: swamp)
    expect(game.legal_options).to include(a_hash_including(type: "activate_mana", object: swamp))
    pay_generic(game)
    expect(game.state.battlefield).not_to include(swamp)
    expect(game.state.stack.size).to eq(1)
  end

  it "remembers what was sacrificed: 'if you sacrificed a Klingon this way' (CR 608.2h)" do
    [["Spec Klingon Warlord", 1], ["Grizzly Bears", 0]].each do |fodder, draws|
      game = board do
        battlefield "Spec Battle Chancellor", fodder
        library "Forest", count: 3
      end
      activate(game, "Spec Battle Chancellor")
      expect(game.legal_options.map { it[:object] }).not_to include(obj_id(game, "Spec Battle Chancellor")) # "another"
      game.submit(game.legal_options.find { it[:type] == "cost" })
      hand = ids_in(game, "alice", :hand).size
      pass_both(game)
      expect(ids_in(game, "alice", :hand).size - hand).to eq(draws)
      engine = game.instance_variable_get(:@engine)
      expect(engine.chars(obj_id(game, "Spec Battle Chancellor")).keyword?(:trample)).to be(true)
    end
  end

  it "taps three untapped artifact creatures, which may include the source and summoning-sick ones (CR 302.6)" do
    game = board do
      battlefield "Spec Drone Matrix", "Survey Drone", "Bastion Golem", "Grizzly Bears", controlled_since: 3
      library "Forest", count: 3
    end
    activate(game, "Spec Drone Matrix")
    choices = game.legal_options.select { it[:type] == "cost" }.map { it[:object] }
    expect(choices).not_to include(obj_id(game, "Grizzly Bears"))
    expect(choices.size).to eq(3)
    3.times { game.submit(game.legal_options.find { it[:type] == "cost" }) }
    expect(game.state.stack.size).to eq(1)
    expect(game.state.battlefield.count { game.state.object(it).tapped }).to eq(3)
  end

  it "isn't activatable without enough untapped artifact creatures, and cancelling untaps the chosen ones" do
    game = board do
      battlefield "Spec Drone Matrix", "Survey Drone"
    end
    expect(option_types(game)).not_to include("activate")
    game = board do
      battlefield "Spec Drone Matrix", "Survey Drone", "Bastion Golem"
    end
    activate(game, "Spec Drone Matrix")
    game.submit(game.legal_options.find { it[:type] == "cost" })
    game.submit(type: "cancel")
    expect(game.state.battlefield.none? { game.state.object(it).tapped }).to be(true)
  end

  it "removes counters from among creatures, one chosen counter at a time" do
    game = board do
      battlefield "Spec Counter Android", counters: { "+1/+1" => 1 }
      battlefield "Grizzly Bears", counters: { "+1/+1" => 1, "stun" => 1 }
      battlefield "Swamp"
      library "Forest", count: 3
    end
    activate(game, "Spec Counter Android")
    3.times do
      game.submit(game.legal_options.find { it[:type] == "cost" && it[:counter] != "stun" } || game.legal_options.find do
        it[:type] == "cost"
      end)
    end
    pay_generic(game)
    counters = game.state.battlefield.map { game.state.object(it).counters }
    expect(counters.flat_map(&:values).sum).to eq(0)
  end

  it "can't remove more counters than there are (CR 118.3)" do
    game = board do
      battlefield "Spec Counter Android", counters: { "+1/+1" => 2 }
      battlefield "Swamp"
    end
    expect(option_types(game)).not_to include("activate")
  end

  it "removes only counters of the named kind" do
    charger = card("Spec Charge Reader", "abilities" => [{ "activated" => {
                     "cost" => [{ "remove_counters" => { "count" => 1, "counter" => "charge", "filter" => "permanent" } }],
                     "effects" => draw_one
                   } }])
    game = build_game(catalog_with(charger)) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Spec Charge Reader", counters: { "+1/+1" => 1, "charge" => 1 }
        library "Forest", count: 2
      end
      player("bob")
    end
    game.submit(type: "activate", object: obj_id(game, "Spec Charge Reader"), ability: "printed:0")
    expect(game.legal_options.select do
      it[:type] == "cost"
    end).to eq([{ type: "cost", object: obj_id(game, "Spec Charge Reader"), counter: "charge" }])
  end

  it "activates from the graveyard by exiling the card or putting it on the bottom of the library (CR 113.6m)" do
    game = board do
      graveyard "Spec Grave Drone", "Spec Time Agent"
      battlefield "Swamp", "Swamp"
      library "Forest", count: 3
    end
    activate(game, "Spec Grave Drone", zone: :graveyard)
    pay_generic(game)
    expect(game.state.exile.size).to eq(1)
    pass_both(game)
    activate(game, "Spec Time Agent", zone: :graveyard)
    pay_generic(game)
    expect(game.state.players[0].library.last).to start_with("spec_time_agent")
    pass_both(game)
    expect(game.state.players[0].life).to eq(22)
    expect(ids_in(game, "alice", :graveyard)).to be_empty
  end

  it "activates only once each turn and only as a sorcery (CR 602.5b, 602.5d)" do
    game = board do
      battlefield "Spec Repair Squad", "Swamp", "Swamp"
      battlefield "Grizzly Bears", tapped: true
      library "Forest", count: 3
    end
    activate(game, "Spec Repair Squad")
    game.submit(type: "target", target: obj_id(game, "Grizzly Bears"))
    pay_generic(game)
    pass_both(game)
    expect(game.legal_options.none? { it[:type] == "activate" }).to be(true)
    expect(game.state.object(obj_id(game, "Spec Repair Squad")).memory["activations"]).to eq("printed:0" => { "turn" => 3, "count" => 1 })
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.legal_options.none? { it[:type] == "activate" }).to be(true)
  end

  it "the once-each-turn limit resets next turn" do
    game = board do
      battlefield "Spec Repair Squad", "Swamp", "Swamp"
    end
    game.state.object(obj_id(game, "Spec Repair Squad")).memory["activations"] = { "printed:0" => { "turn" => 2, "count" => 1 } }
    game = Enjine::Game.import({ "state" => game.state.to_h }, catalog: catalog)
    expect(game.legal_options).to include(a_hash_including(type: "activate"))
  end

  it "activates only during your turn and only if a condition holds (CR 602.5b)" do
    low = board(life: 8) { battlefield "Spec Turn Captain", "Swamp" }
    expect(option_types(low)).to include("activate")
    high = board(life: 15) { battlefield "Spec Turn Captain", "Swamp" }
    expect(option_types(high)).not_to include("activate")
    theirs = build_game(catalog) do
      turn 3, active: "bob", step: :precombat_main
      priority "alice"
      player("alice", life: 5) { battlefield "Spec Turn Captain", "Swamp" }
      player("bob")
    end
    expect(option_types(theirs)).not_to include("activate")
  end
end
