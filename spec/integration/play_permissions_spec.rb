# frozen_string_literal: true

# Casting and playing cards from zones other than the hand (CR 601.3, 601.2a, 305.1, 113.6e-f, 401.5).
RSpec.describe "Play permissions from other zones (CR 601.3, 305.1)" do
  let(:recruit) do # "you may cast this card from your graveyard; it enters with a finality counter"
    { "name" => "Gravecaller Recruit", "mana_cost" => "{B}", "types" => ["creature"], "power" => 2, "toughness" => 1,
      "abilities" => [{ "play_from" => { "zone" => "graveyard", "enters_with" => { "finality" => 1 } } }] }
  end
  let(:wanderer) do
    { "name" => "Exile Wanderer", "mana_cost" => "{1}{B}", "types" => ["creature"], "power" => 3, "toughness" => 3,
      "abilities" => [{ "play_from" => { "zone" => "exile" } }] }
  end
  let(:recycler) do
    { "name" => "Scrap Recycler", "mana_cost" => "{2}{B}", "types" => %w[artifact creature], "power" => 2, "toughness" => 2,
      "abilities" => [{ "play_from" => { "zone" => "graveyard", "cards" => { "types" => %w[artifact creature] },
                                         "once_each_turn" => true, "enters_with" => { "finality" => 1 } } }] }
  end
  let(:mite) { { "name" => "Clockwork Mite", "mana_cost" => "{1}", "types" => %w[artifact creature], "power" => 1, "toughness" => 1 } }
  let(:scout) do
    { "name" => "Horizon Scout", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => ["look_at_top", { "play_from" => { "zone" => "library_top", "cards" => { "types" => ["land"] },
                                                        "play" => "play" } }] }
  end
  let(:tinker) do
    { "name" => "Warp Tinker", "mana_cost" => "{2}{U}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "abilities" => [{ "play_from" => { "zone" => "library_top", "cards" => { "types" => ["artifact"] },
                                         "once_each_turn" => true } }] }
  end
  let(:catalog) { catalog_with(recruit, wanderer, recycler, mite, scout, tinker) }

  def board(step: :precombat_main, active: "alice", &alice)
    build_game(catalog) do
      turn 3, active: active, step: step
      player("alice") do
        instance_eval(&alice)
        library "Forest", count: 5 if @current.zones[:library].empty?
      end
      player("bob") { library "Forest", count: 5 }
    end
  end

  def pay!(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def cast_options(game) = game.legal_options.select { it[:type] == "cast" }

  it "casts a card from its owner's graveyard with its own permission; it enters with a finality counter (CR 113.6e)" do
    game = board do
      graveyard "Gravecaller Recruit"
      battlefield "Swamp"
    end
    card = ids_in(game, "alice", :graveyard).first
    option = { type: "cast", object: card, via: "self:printed:0" }
    expect(cast_options(game)).to eq([option])
    game.submit(option)
    pay!(game)
    expect(game.state.stack.size).to eq(1)
    pass_both(game)
    recruit = obj_id(game, "Gravecaller Recruit")
    expect(game.state.object(recruit).counters).to eq("finality" => 1)
  end

  it "cancelling puts the card back where it was cast from, as the same object (CR 734.1)" do
    game = board do
      graveyard "Grizzly Bears", "Gravecaller Recruit", "Hill Giant"
      battlefield "Swamp"
    end
    before = ids_in(game, "alice", :graveyard).dup
    game.submit(type: "cast", object: before[1], via: "self:printed:0")
    expect(ids_in(game, "alice", :graveyard)).to eq(before - [before[1]])
    game.submit(type: "cancel")
    expect(ids_in(game, "alice", :graveyard)).to eq(before)
    expect(game.state.object(before[1]).zone).to eq(:graveyard)
    expect(game.pending_decision.kind).to eq("priority")
  end

  it "casts a card from exile with its own permission, but not from the graveyard (CR 113.6b)" do
    game = board do
      exile "Exile Wanderer"
      graveyard "Exile Wanderer"
      battlefield "Swamp", count: 2
    end
    exiled = game.state.exile.first
    expect(cast_options(game)).to eq([{ type: "cast", object: exiled, via: "self:printed:0" }])
    game.submit(cast_options(game).first)
    pay!(game)
    pass_both(game)
    expect(game.state.battlefield.map { game.state.object(it).card }).to include("exile_wanderer")
    expect(game.state.exile).to be_empty
  end

  it "follows timing: a creature from the graveyard only at sorcery speed (CR 307.1, 601.3)" do
    game = board(step: :beginning_of_combat) do
      graveyard "Gravecaller Recruit"
      battlefield "Swamp"
    end
    expect(cast_options(game)).to be_empty
  end

  it "lets a permanent's controller cast one matching card from their graveyard each of their turns" do
    game = board do
      battlefield "Scrap Recycler", "Swamp", "Swamp"
      graveyard "Clockwork Mite", "Clockwork Mite", "Grizzly Bears"
    end
    recycler = obj_id(game, "Scrap Recycler")
    mites = ids_in(game, "alice", :graveyard).first(2)
    via = "static:#{recycler}:printed:0"
    expect(cast_options(game)).to eq(mites.map { { type: "cast", object: it, via: via } })
    game.submit(type: "cast", object: mites[0], via: via)
    game.submit(type: "cancel") # cancelling doesn't use the once-each-turn permission
    expect(cast_options(game).size).to eq(2)
    game.submit(type: "cast", object: mites[0], via: via)
    pay!(game)
    expect(cast_options(game)).to be_empty # once each turn
    pass_both(game)
    mite = game.state.battlefield.find { game.state.object(it).card == "clockwork_mite" }
    expect(game.state.object(mite).counters).to eq("finality" => 1)
  end

  it "doesn't offer a once-each-turn permission on another player's turn" do
    game = board(active: "bob") do
      battlefield "Scrap Recycler"
      graveyard "Clockwork Mite"
    end
    expect(game.state.priority).to eq(1)
    game.submit(type: "pass")
    expect(game.pending_decision.player).to eq("alice")
    expect(cast_options(game)).to be_empty
  end

  it "plays a land from the top of the library and shows that card to its owner only (CR 305.1, 401.5)" do
    game = board do
      battlefield "Horizon Scout"
      library "Mountain", "Forest"
    end
    top = ids_in(game, "alice", :library).first
    expect(game.view_for("alice")["players"][0]["library_top"]["id"]).to eq(top)
    expect(game.view_for("bob")["players"][0]).not_to have_key("library_top")
    option = { type: "play_land", object: top, via: "static:#{obj_id(game, "Horizon Scout")}:printed:1" }
    expect(game.legal_options).to include(option)
    game.submit(option)
    expect(game.state.battlefield.map { game.state.object(it).card }).to include("mountain")
    expect(game.legal_options).not_to include(a_hash_including(type: "play_land")) # one land per turn (CR 305.2)
  end

  it "casts an artifact spell from the top of the library once each turn" do
    game = board do
      battlefield "Warp Tinker", "Island", "Island"
      library "Clockwork Mite", "Clockwork Mite", "Forest"
    end
    top = ids_in(game, "alice", :library).first
    option = { type: "cast", object: top, via: "static:#{obj_id(game, "Warp Tinker")}:printed:0" }
    expect(cast_options(game)).to eq([option])
    game.submit(option)
    game.submit(type: "cancel")
    expect(ids_in(game, "alice", :library).first).to eq(top) # back on top
    game.submit(option)
    pay!(game)
    expect(cast_options(game)).to be_empty
  end
end
