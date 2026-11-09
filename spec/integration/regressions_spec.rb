# frozen_string_literal: true

RSpec.describe "Regressions found by the design reviews" do
  it "E1: apply with an illegal option on a freshly imported game raises IllegalDecision and rolls back" do
    game = basics_setup.new_game(seed: 1)
    copy = Enjine::Game.import(game.export, catalog: game.catalog)
    before = copy.export
    expect { copy.apply([{ type: "nonsense" }]) }.to raise_error(Enjine::IllegalDecision, /decision #0/)
    expect(copy.export).to eq(before)
  end

  it "E2: the opponent can read history after a concession" do
    game = basics_setup.new_game(seed: 1)
    game.concede("alice")
    expect(game.history_for("bob").last).to include("kind" => "concede", "option" => { "type" => "concede" })
    expect(game.history_for("alice").last["player"]).to eq("alice")
  end

  it "E13: engine errors while checking an imported position propagate instead of looking like bad input" do
    game = basics_setup.new_game(seed: 1)
    allow(Enjine::Decisions::PlayOrDraw).to receive(:options).and_raise(NoMethodError, "engine bug")
    expect { Enjine::Game.import(game.export, catalog: game.catalog) }.to raise_error(NoMethodError, "engine bug")
  end

  it "\"self\" in a graveyard card's own triggered ability is that card: it returns itself (CR 113.6k, 400.7)" do
    phoenix = { "name" => "Ember Phoenix", "mana_cost" => "{R}", "types" => ["creature"], "power" => 1, "toughness" => 1,
                "abilities" => [{ "triggered" => { "zone" => "graveyard", "when" => { "gains_life" => {} },
                                                   "effects" => [{ "return_to_battlefield" => { "to" => "self" } }] } }] }
    tonic = { "name" => "Small Tonic", "mana_cost" => "{G}", "types" => ["instant"],
              "abilities" => [{ "spell" => { "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
    game = build_game(catalog_with(phoenix, tonic)) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: { G: 1 }) do
        hand "Small Tonic"
        graveyard "Ember Phoenix"
        library "Forest", count: 3
      end
      player("bob") { library "Forest", count: 3 }
    end
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "pay_mana", mana: "G")
    pass_both(game, 2)
    expect(game.state.battlefield.map { game.state.object(it).card }).to eq(["ember_phoenix"])
  end

  describe "State#fork and Game#fork (P3)" do
    it "copies everything: the fork serializes identically and diverges independently" do
      setup = basics_setup
      game = setup.new_game(seed: 9)
      agent = Enjine::Agents::Random.new(seed: 9)
      300.times { game.submit(agent.choose(game.pending_decision)) unless game.over? }
      copy = game.fork
      expect(copy.state.to_h).to eq(game.state.to_h)
      expect(copy.pending_decision).to eq(game.pending_decision)
      copy.submit(copy.legal_options.first)
      expect(copy.state.to_h).not_to eq(game.state.to_h)
      expect(game.history.size).to eq(copy.history.size - 1)
    end

    it "deep-copies mid-cast context, combat and effects" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand "Grizzly Bears"
          battlefield "Forest", "Forest"
        end
        player("bob")
      end
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      copy = game.state.fork
      copy.frames.last["remaining"]["generic"] = 99
      copy.players[0].mana_pool[:G] = 5
      copy.objects.each_value { it.tapped = true }
      expect(game.state.frames.last["remaining"]["generic"]).to eq(1)
      expect(game.state.players[0].mana_pool[:G]).to eq(0)
      expect(game.state.objects.values.none?(&:tapped)).to be(true)
    end
  end

  describe "The frame stack (F1)" do
    it "exports and resumes mid-cast and mid-resolution identically" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand "Lightning Bolt"
          battlefield "Mountain"
          library "Forest", count: 3
        end
        player("bob") { library "Forest", count: 3 }
      end
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      expect(game.state.frames.map { it["type"] }).to eq(["cast"])
      copy = Enjine::Game.import(game.export, catalog: game.catalog)
      expect(copy.pending_decision).to eq(game.pending_decision)
      [game, copy].each do |g|
        g.submit(type: "target", target: "player:bob")
        g.submit(type: "activate_mana", object: g.state.battlefield.first, ability: mana_ref(g, g.state.battlefield.first))
        g.submit(type: "pay_mana", mana: "R")
        pass_both(g)
      end
      expect(copy.state.to_h).to eq(game.state.to_h)
      expect(game.state.frames).to be_empty
      expect(game.view_for(:observer)["players"][1]["life"]).to eq(17)
    end

    it "rejects snapshots whose pending decision doesn't belong to the top frame" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand "Lightning Bolt"
          battlefield "Mountain"
        end
        player("bob")
      end
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      data = game.to_h
      data["state"]["pending"] = { "kind" => "discard", "player" => 0, "count" => 1 }
      expect { Enjine::Game.import(data, catalog: game.catalog) }.to raise_error(Enjine::InvalidSnapshot, /cast frame/)
      data["state"]["frames"] = [{ "type" => "warp" }]
      expect { Enjine::Game.import(data, catalog: game.catalog) }.to raise_error(Enjine::InvalidSnapshot, /unknown frame/)
    end
  end
end
