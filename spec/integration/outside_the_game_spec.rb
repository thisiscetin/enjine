# frozen_string_literal: true

# Cards outside the game (CR 400.11, 400.11a-b, 108.3) and owner play permissions with a cost increase
# (CR 611.2a, 601.2f).
RSpec.describe "Outside the game and owner permissions (CR 400.11, 601.2f)" do
  # "Once during each of your turns, you may play a permanent card you own from outside the game or from
  # your graveyard."
  let(:forge) do
    { "name" => "Reverie Engine", "mana_cost" => "{3}", "types" => ["artifact"],
      "abilities" => [{ "play_from" => { "zones" => %w[outside graveyard], "cards" => { "permanent" => true },
                                         "play" => "play", "once_each_turn" => true } }] }
  end
  # "When this enters, look at target opponent's hand and exile a nonland card from it. For as long as it
  # stays exiled, its owner may play it. A spell cast this way costs {2} more."
  let(:thief) do
    { "name" => "Mind Lifter", "mana_cost" => "{1}{U}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} }, "targets" => ["opponent"], "effects" => [
        { "look_at_hand" => { "to" => { "target" => 0 } } },
        { "choose_cards" => { "from" => { "hand" => { "target" => 0 } }, "for" => { "not_types" => ["land"] },
                              "put" => "exile" } },
        { "play_permission" => { "to" => { "result" => 1 }, "to_player" => "owner", "duration" => "while_exiled",
                                 "cost_increase" => 2 } }
      ] } }] }
  end
  let(:gift) do # a play permission granted to a selected player
    { "name" => "Shared Visions", "mana_cost" => "{U}", "types" => ["sorcery"], "abilities" => [{ "spell" => {
      "targets" => ["opponent"], "effects" => [
        { "exile_top" => { "amount" => 1 } },
        { "play_permission" => { "to" => { "result" => 0 }, "to_player" => { "target" => 0 }, "play" => "cast" } }
      ]
    } }] }
  end
  let(:catalog) { catalog_with(forge, thief, gift) }

  def board(lands: 3, &alice)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Reverie Engine"
        battlefield "Forest", count: lands
        battlefield "Island", count: 2
        library "Forest", count: 5
        instance_eval(&alice) if alice
      end
      player("bob") do
        hand "Grizzly Bears"
        battlefield "Forest", count: 4
        library "Forest", count: 5
      end
    end
  end

  def pay!(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def forge_via(game) = "static:#{obj_id(game, "Reverie Engine")}:printed:0"

  it "offers each distinct card outside the game once, without an object id, and casts it (CR 400.11b, 601.2a)" do
    game = board { outside "Grizzly Bears", "Grizzly Bears", "Lightning Bolt" }
    via = forge_via(game)
    option = { type: "cast", object: "outside:grizzly_bears", via: via }
    expect(game.legal_options.select { it[:type] == "cast" }).to eq([option]) # a Bolt isn't a permanent card
    expect(game.view_for("alice")["players"][0]["outside"].map { it["card"] }).to eq(%w[grizzly_bears grizzly_bears lightning_bolt])
    expect(game.view_for("bob")["players"][0]).not_to have_key("outside")
    expect(game.view_for("bob")["players"][0]["outside_count"]).to eq(3)

    game.submit(option)
    pay!(game)
    stack = game.state.object(game.state.stack.first)
    expect([stack.card, stack.owner]).to eq(["grizzly_bears", 0]) # CR 108.3
    expect(game.state.players[0].outside).to eq(%w[grizzly_bears lightning_bolt])
    pass_both(game)
    expect(game.state.battlefield.map { game.state.object(it).card }).to include("grizzly_bears")
    # once each turn, shared by both zones
    expect(game.legal_options.select { it[:via] == via }).to be_empty
  end

  it "puts a cancelled cast back outside the game (CR 734.1)" do
    game = board { outside "Hill Giant", "Grizzly Bears" }
    game.submit(type: "cast", object: "outside:grizzly_bears", via: forge_via(game))
    expect(game.state.players[0].outside).to eq(["hill_giant"])
    game.submit(type: "cancel")
    expect(game.state.players[0].outside).to eq(%w[hill_giant grizzly_bears])
    expect(game.state.stack).to be_empty
  end

  it "plays a land from outside the game with the turn's land play (CR 305.1)" do
    game = board { outside "Mountain" }
    option = { type: "play_land", object: "outside:mountain", via: forge_via(game) }
    expect(game.legal_options).to include(option)
    game.submit(option)
    expect(game.state.players[0].outside).to be_empty
    expect(game.state.players[0].lands_played).to eq(1)
    mountain = game.state.battlefield.map { game.state.object(it) }.find { it.card == "mountain" }
    expect([mountain.owner, mountain.controller]).to eq([0, 0])
    expect(game.legal_options.select { it[:type] == "play_land" }).to be_empty
  end

  it "plays a permanent card from the graveyard instead, and not on an opponent's turn" do
    game = board { graveyard "Grizzly Bears" }
    card = ids_in(game, "alice", :graveyard).first
    expect(game.legal_options).to include(type: "cast", object: card, via: forge_via(game))
    other = build_game(catalog) do
      turn 4, active: "bob", step: :precombat_main
      player("alice") do
        battlefield "Reverie Engine", "Forest"
        outside "Grizzly Bears"
        library "Forest", count: 3
      end
      player("bob") { library "Forest", count: 3 }
    end
    expect(Enjine::Engine.new(catalog, other.state) { nil }.permission_cast_options(0)).to be_empty
  end

  it "round-trips the outside lists through export and import" do
    game = board { outside "Hill Giant" }
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.state.players[0].outside).to eq(["hill_giant"])
    expect(copy.state.outside_lists).to eq([["hill_giant"], []])
    bad = JSON.parse(game.export)
    bad["state"]["players"][0]["outside"] = ["black_lotus"]
    expect { Enjine::Game.import(bad, catalog: catalog) }
      .to raise_error(Enjine::InvalidSnapshot, /players\[0\]\.outside\[0\]: "black_lotus" is not in the catalog/)
  end

  it "lets the card's owner play an exiled card for {2} more (CR 108.3, 601.2f)" do
    game = board(lands: 2) { hand "Mind Lifter" }
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay!(game)
    pass_both(game) # the creature resolves; its trigger targets bob
    game.submit(type: "target", target: "player:bob") if game.pending_decision.kind == "choose_target"
    pass_both(game)
    while game.pending_decision.kind == "effect_choice"
      game.submit(game.legal_options.reject { it[:type] == "done" }.first || game.legal_options.first)
    end
    bears = game.state.exile.first
    expect(game.state.object(bears).card).to eq("grizzly_bears")
    expect(game.state.effects.find { it["kind"] == "permission" }).to include("controller" => 1, "cost_increase" => 2)
    skip_to(game, :precombat_main, turn: 4)
    option = game.legal_options.find { it[:type] == "cast" && it[:object] == bears }
    expect(option[:via]).to start_with("effect:")
    game.submit(option)
    expect(game.pending_decision.kind).to eq("pay_cost")
    expect(game.state.frames.last["remaining"]).to include("generic" => 3) # {1}{G} plus {2}
  end

  it "grants a permission to a selected player" do
    game = board(lands: 1) { hand "Shared Visions" }
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: "player:bob")
    pay!(game)
    pass_both(game)
    expect(game.state.effects.find { it["kind"] == "permission" }).to include("controller" => 1)
  end
end
