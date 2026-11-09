# frozen_string_literal: true

RSpec.describe "Delayed triggers, optional effects, results and \"if you cast it\" (CR 603.7, 118.12, 400.7)" do
  def next_end_step = { "step_begins" => { "step" => "end", "whose" => "each" } }

  def spell(name, effects, targets = [])
    { "name" => name, "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? } }] }
  end

  let(:exile_target) { { "exile" => { "to" => { "target" => 0 } } } }
  let(:catalog) do
    catalog_with(
      spell("Fading Refuge", [exile_target,
                              { "delayed_trigger" => { "when" => next_end_step,
                                                       "effects" => [{ "return_to_battlefield" => { "to" => { "result" => 0 } } }] } }],
            [{ "creature" => { "controller" => "you" } }]),
      spell("Shimmer Step", [exile_target, { "return_to_battlefield" => { "to" => { "result" => 0 }, "tapped" => true } }],
            ["creature"]),
      spell("Borrowed Echo", [exile_target, { "return_to_battlefield" => { "to" => { "result" => 0 }, "under" => "you" } }],
            ["creature"]),
      spell("Gamble Spark", [{ "deal_damage" => { "amount" => 1, "to" => "each_opponent" } },
                             { "may" => { "effects" => [{ "discard" => { "amount" => 1 } }],
                                          "then" => [{ "draw" => { "amount" => 2 } }],
                                          "otherwise" => [{ "gain_life" => { "amount" => 3 } }] } }]),
      { "name" => "Rally Drummer", "mana_cost" => "{R}", "types" => ["creature"], "power" => 1, "toughness" => 1,
        "abilities" => [{ "triggered" => {
          "when" => { "step_begins" => { "step" => "beginning_of_combat" } },
          "effects" => [{ "create_token" => { "token" => { "name" => "Rallied Brawler", "types" => ["creature"],
                                                           "subtypes" => ["warrior"], "power" => 2, "toughness" => 1 } } },
                        { "grant" => { "keywords" => ["haste"], "to" => { "result" => 0 } } },
                        { "delayed_trigger" => { "when" => next_end_step,
                                                 "effects" => [{ "sacrifice" => { "to" => { "result" => 0 } } }] } }]
        } }] },
      { "name" => "Herald of Arrival", "mana_cost" => "{R}", "types" => ["creature"], "power" => 2, "toughness" => 2,
        "abilities" => [{ "triggered" => { "when" => { "enters" => {} }, "if" => { "was_cast" => true },
                                           "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
    )
  end

  def game_with(*hand, alice_board: [], bob_board: [], alice_hand_extra: [], step: :precombat_main)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice") do
        hand(*hand, *alice_hand_extra)
        battlefield "Mountain", count: 2
        alice_board.each { battlefield it }
        library "Forest", count: 8
      end
      player("bob") do
        bob_board.each { battlefield it }
        library "Forest", count: 8
      end
    end
  end

  def cast(game, card, target = nil)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) })
    game.submit(type: "target", target: target) if target
    mountain = game.state.battlefield.find { game.state.object(it).card == "mountain" && !game.state.object(it).tapped }
    game.submit(type: "activate_mana", object: mountain, ability: "intrinsic:mountain")
    game.submit(type: "pay_mana", mana: "R")
  end

  def cards(game, ids) = ids.map { game.state.object(it).card }
  def life(game, index) = game.state.players[index].life

  describe "results: what an earlier effect moved or created (CR 400.7j, 608.2c)" do
    it "flickers: exile, then return that card as a new object, tapped (CR 400.7)" do
      game = game_with("Shimmer Step", bob_board: ["Grizzly Bears"])
      bears = obj_id(game, "Grizzly Bears")
      cast(game, "Shimmer Step", bears)
      pass_both(game)
      back = obj_id(game, "Grizzly Bears")
      expect(back).not_to eq(bears)
      expect(game.state.object(back)).to have_attributes(controller: 1, tapped: true)
      expect(game.state.exile).to be_empty
    end

    it "returns the card under the controller's control with under: you (CR 110.2)" do
      game = game_with("Borrowed Echo", bob_board: ["Grizzly Bears"])
      cast(game, "Borrowed Echo", obj_id(game, "Grizzly Bears"))
      pass_both(game)
      expect(game.state.object(obj_id(game, "Grizzly Bears"))).to have_attributes(controller: 0, owner: 1, tapped: false)
    end

    it "the flickered permanent was not cast, so an \"if you cast it\" trigger does not fire (CR 603.4)" do
      game = game_with("Shimmer Step", alice_board: ["Herald of Arrival"])
      cast(game, "Shimmer Step", obj_id(game, "Herald of Arrival"))
      hand = ids_in(game, "alice", :hand).size
      pass_both(game)
      expect(game.state.stack).to be_empty
      expect(ids_in(game, "alice", :hand).size).to eq(hand)
    end
  end

  describe "delayed triggered abilities (CR 603.7)" do
    it "returns the exiled card at the beginning of the next end step, once (CR 603.7a, 603.7b)" do
      game = game_with("Fading Refuge", alice_board: ["Grizzly Bears"])
      cast(game, "Fading Refuge", obj_id(game, "Grizzly Bears"))
      pass_both(game)
      expect(cards(game, game.state.exile)).to eq(["grizzly_bears"])
      expect(game.state.delayed_triggers.size).to eq(1)
      expect(game.view_for("bob")["delayed_triggers"].first).to include("controller" => "alice", "card" => "Fading Refuge")
      skip_to(game, :end)
      expect(game.state.delayed_triggers).to be_empty
      expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Fading Refuge ability"])
      pass_both(game)
      expect(game.state.object(obj_id(game, "Grizzly Bears"))).to have_attributes(controller: 0, zone: :battlefield)
      skip_to(game, :end, turn: 5)
      expect(game.state.stack).to be_empty
    end

    it "survives export/import while waiting (snapshot round trip)" do
      game = game_with("Fading Refuge", alice_board: ["Grizzly Bears"])
      cast(game, "Fading Refuge", obj_id(game, "Grizzly Bears"))
      pass_both(game)
      copy = Enjine::Game.import(game.export, catalog: catalog)
      expect(copy.state.delayed_triggers).to eq(game.state.delayed_triggers)
      skip_to(copy, :end)
      pass_both(copy)
      expect(copy.state.battlefield.map { copy.state.object(it).card }).to include("grizzly_bears")
    end

    it "does nothing to a card that left the zone it was expected in (CR 603.7c, 400.7)" do
      game = game_with("Fading Refuge", alice_board: ["Grizzly Bears"])
      cast(game, "Fading Refuge", obj_id(game, "Grizzly Bears"))
      pass_both(game)
      exiled = game.state.exile.first
      engine = game.instance_variable_get(:@engine)
      engine.move!(exiled, :graveyard, reason: "test")
      skip_to(game, :end)
      pass_both(game)
      expect(cards(game, ids_in(game, "alice", :graveyard))).to include("grizzly_bears")
      expect(game.state.battlefield.map { game.state.object(it).card }).not_to include("grizzly_bears")
    end

    it "a token made this way gains haste and is sacrificed at the next end step (CR 701.21a)" do
      game = game_with(alice_board: ["Rally Drummer"])
      skip_to(game, :beginning_of_combat)
      pass_both(game) # the trigger resolves
      token = game.state.battlefield.find { game.state.object(it).card.start_with?("rallied_brawler") }
      expect(game.instance_variable_get(:@engine).chars(token).keyword?(:haste)).to be(true)
      expect(game.state.delayed_triggers.first).to include("results" => [[token], []], "controller" => 0)
      skip_to(game, :end)
      pass_both(game)
      expect(game.state.objects).not_to have_key(token)
    end

    it "a token that left the battlefield can't be returned to it (CR 111.8)" do
      game = game_with("Shimmer Step", alice_board: ["Rally Drummer"])
      skip_to(game, :beginning_of_combat)
      pass_both(game)
      token = game.state.battlefield.find { game.state.object(it).card.start_with?("rallied_brawler") }
      cast(game, "Shimmer Step", token)
      pass_both(game)
      expect(game.state.objects.values.map(&:card).grep(/rallied_brawler/)).to be_empty # exiled, then gone (CR 704.5d)
    end

    it "the controller can't sacrifice a permanent it no longer controls (CR 701.21a)" do
      game = game_with(alice_board: ["Rally Drummer"])
      skip_to(game, :beginning_of_combat)
      pass_both(game)
      token = game.state.battlefield.find { game.state.object(it).card.start_with?("rallied_brawler") }
      game.state.object(token).controller = 1
      skip_to(game, :end)
      pass_both(game)
      expect(game.state.battlefield).to include(token)
    end
  end

  describe "\"you may ...\" (CR 118.12, 118.3)" do
    it "yes: the optional part, then \"if you do\"" do
      game = game_with("Gamble Spark", alice_hand_extra: ["Forest"])
      cast(game, "Gamble Spark")
      pass_both(game)
      expect(game.pending_decision).to have_attributes(kind: "effect_choice", player: "alice")
      expect(game.legal_options.map { it[:type] }).to eq(%w[yes no])
      game.submit(type: "yes")
      game.submit(type: "discard", object: ids_in(game, "alice", :hand).first)
      expect(ids_in(game, "alice", :hand).size).to eq(2)
      expect([life(game, 0), life(game, 1)]).to eq([20, 19])
    end

    it "no: the \"if you don't\" part instead" do
      game = game_with("Gamble Spark", alice_hand_extra: ["Forest"])
      cast(game, "Gamble Spark")
      pass_both(game)
      game.submit(type: "no")
      expect(ids_in(game, "alice", :hand).size).to eq(1)
      expect(life(game, 0)).to eq(23)
    end

    it "yes isn't offered when the optional part can't be done fully (CR 118.3)" do
      game = game_with("Gamble Spark")
      cast(game, "Gamble Spark")
      pass_both(game)
      expect(game.legal_options).to eq([{ type: "no" }])
    end

    it "a waiting nested choice survives export/import" do
      game = game_with("Gamble Spark", alice_hand_extra: ["Forest"])
      cast(game, "Gamble Spark")
      pass_both(game)
      game.submit(type: "yes")
      copy = Enjine::Game.import(game.export, catalog: catalog)
      expect(copy.pending_decision.kind).to eq("effect_choice")
      copy.submit(type: "discard", object: ids_in(copy, "alice", :hand).first)
      expect(ids_in(copy, "alice", :hand).size).to eq(2)
    end
  end

  describe "\"if you cast it\" (CR 400.7d, 603.4)" do
    it "triggers when the permanent entered by resolving as a cast spell" do
      game = game_with("Herald of Arrival")
      cast(game, "Herald of Arrival")
      pass_both(game)
      expect(game.state.object(obj_id(game, "Herald of Arrival")).memory).to eq("cast" => true, "cast_from" => "hand")
      expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Herald of Arrival ability"])
      pass_both(game)
      expect(ids_in(game, "alice", :hand).size).to eq(1)
    end

    it "still resolves after the permanent has left, from the ability's memory (CR 608.2h)" do
      game = game_with("Herald of Arrival")
      cast(game, "Herald of Arrival")
      pass_both(game)
      engine = game.instance_variable_get(:@engine)
      engine.move!(obj_id(game, "Herald of Arrival"), :hand, reason: "test")
      pass_both(game)
      expect(ids_in(game, "alice", :hand).size).to eq(2)
    end

    it "doesn't trigger for a permanent put onto the battlefield without being cast" do
      game = game_with(alice_board: ["Herald of Arrival"])
      expect(game.state.object(obj_id(game, "Herald of Arrival")).memory).to eq({})
      cond = Enjine::Mechanics::Condition.build({ "was_cast" => false }, [], "if")
      ctx = Enjine::Mechanics::EffectContext.new(0, obj_id(game, "Herald of Arrival"), nil, [])
      expect(cond.true?(game.instance_variable_get(:@engine), ctx)).to be(true)
      expect(cond.to_s).to eq("it wasn't cast")
    end
  end
end
