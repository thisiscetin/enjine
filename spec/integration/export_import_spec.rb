# frozen_string_literal: true

RSpec.describe "Export, import, replay and restart" do
  let(:setup) { basics_setup }

  def play_randomly(game, decisions, seed: 1)
    agent = Enjine::Agents::Random.new(seed: seed)
    decisions.times { game.submit(agent.choose(game.pending_decision)) unless game.over? }
    game
  end

  it "resumes an exported game exactly, including the pending decision and history" do
    game = play_randomly(setup.new_game(seed: 21), 150)
    copy = setup.import(game.export)
    expect(copy.state.to_h).to eq(game.state.to_h)
    expect(copy.pending_decision).to eq(game.pending_decision)
    expect(copy.history_for("alice")).to eq(game.history_for("alice"))
    play_randomly(game, 300, seed: 9)
    play_randomly(copy, 300, seed: 9)
    expect(copy.state.to_h).to eq(game.state.to_h)
  end

  it "imports from a parsed Hash too" do
    game = play_randomly(setup.new_game(seed: 2), 20)
    expect(Enjine::Game.import(game.to_h, catalog: setup.catalog).state.to_h).to eq(game.state.to_h)
  end

  it "replays a game from its seed and decision log" do
    game = play_randomly(setup.new_game(seed: 33), 400)
    replay = setup.new_game(seed: 33).apply(game.decision_log)
    expect(replay.state.to_h).to eq(game.state.to_h)
  end

  it "restarts with the same seed identically, or with a new seed" do
    game = setup.new_game(seed: 4)
    opening = game.state.to_h
    play_randomly(game, 50)
    expect(game.restart.state.to_h).to eq(opening)
    expect(game.history.size).to eq(1)
    game.submit(type: "play")
    hand = game.state.players[0].hand.dup
    game.restart(seed: 5)
    expect(game.state.seed).to eq(5)
    game.submit(type: "play")
    expect(game.state.players[0].hand).not_to eq(hand)
  end

  it "keeps finished games importable" do
    game = setup.new_game(seed: 1)
    game.concede("bob")
    expect(setup.import(game.export)).to be_over
  end

  describe "rejecting bad snapshots" do
    let(:good) { play_randomly(setup.new_game(seed: 8), 60).to_h }

    def import(data) = Enjine::Game.import(data, catalog: setup.catalog)

    def errors_for(data)
      import(data)
      raise "expected InvalidSnapshot"
    rescue Enjine::InvalidSnapshot => e
      e.errors.join("\n")
    end

    def mutate
      data = Marshal.load(Marshal.dump(good))
      yield data["state"]
      data
    end

    it "rejects non-JSON and missing state" do
      expect(errors_for("{nope")).to include("not valid JSON")
      expect(errors_for({})).to include('must contain "state"')
      expect(errors_for({ "state" => [] })).to include("must be an object")
      expect(errors_for(mutate { it["version"] = 99 })).to include("version")
    end

    it "rejects cards missing from the catalog" do
      expect(errors_for(mutate { |s| s["objects"][0]["card"] = "black_lotus" })).to match(/not in the catalog|malformed/)
      other = Enjine::Catalog.from_definitions([CardFixtures.cards.first])
      expect { Enjine::Game.import(good, catalog: other) }.to raise_error(Enjine::InvalidSnapshot, /not in the catalog/)
    end

    it "rejects objects in the wrong number of zones" do
      expect(errors_for(mutate { |s| s["players"][0]["hand"] << s["players"][0]["library"][0] }))
        .to match(/in 2 zones|listed in hand but its zone is library/)
      expect(errors_for(mutate { |s| s["players"][0]["library"].shift })).to include("in 0 zones")
      expect(errors_for(mutate { |s| s["battlefield"] << "forest#99999" })).to include("unknown object")
      expect(errors_for(mutate { |s| s["players"][1]["library"] << s["players"][0]["library"].shift }))
        .to include("owned by player 0")
    end

    it "rejects malformed objects and players" do
      expect(errors_for(mutate { |s| s["objects"][0]["tapped"] = "no" })).to include("tapped: must be true or false")
      expect(errors_for(mutate { |s| s["objects"][0]["zone"] = "sideboard" })).to include("unknown zone")
      expect(errors_for(mutate { |s| s["objects"][0]["owner"] = 2 })).to include("owner: must be 0 or 1")
      expect(errors_for(mutate { |s| s["objects"] << s["objects"][0] })).to include("duplicate id")
      expect(errors_for(mutate { |s| s["objects"][0]["id"] = "forest#999999" })).to include("next_id")
      expect(errors_for(mutate { |s| s["objects"] = {} })).to include("objects: must be a list")
      expect(errors_for(mutate { |s| s["objects"][0] = 1 })).to include("must be an object")
      expect(errors_for(mutate { |s| s["players"].pop })).to include("2 players")
      expect(errors_for(mutate { |s| s["players"][0] = 1 })).to include("players[0]: must be an object")
      expect(errors_for(mutate { |s| s["players"][0]["life"] = "20" })).to include("life: must be an integer")
      expect(errors_for(mutate { |s| s["players"][0].delete("poison") })).to include("poison: missing")
      expect(errors_for(mutate { |s| s["players"][0]["hand"] = nil })).to include("hand: must be a list")
      expect(errors_for(mutate { |s| s["players"][0]["mana_pool"] = { "Q" => 1 } })).to include("mana_pool")
      expect(errors_for(mutate { |s| s["players"][1]["name"] = s["players"][0]["name"] })).to include("distinct")
    end

    it "rejects off-battlefield tapped objects and controller mismatches" do
      expect(errors_for(mutate { |s| s["objects"].find { it["zone"] == "library" }["tapped"] = true }))
        .to include("only permanents on the battlefield can be tapped")
      data = mutate do |s|
        obj = s["objects"].find { it["zone"] == "library" }
        obj["controller"] = 1 - obj["owner"]
      end
      expect(errors_for(data)).to include("controller must equal owner")
    end

    it "rejects inconsistent turn and pending state" do
      expect(errors_for(mutate { it["step"] = "second_main" })).to include("unknown step")
      expect(errors_for(mutate { it["step_state"] = "x" })).to include("step_state")
      expect(errors_for(mutate { it["pending"] = nil })).to include("needs a pending decision")
      expect(errors_for(mutate { it["pending"] = { "kind" => "vote", "player" => 0 } })).to include("unknown decision")
      expect(errors_for(mutate { it["pending"] = { "kind" => "priority", "player" => 5 } })).to include("must be 0 or 1")
      expect(errors_for(mutate { it["result"] = { "winner" => nil } })).to include("must be empty once the game is over")
      expect(errors_for(mutate { it["rng"] = -1 })).to include("rng")
      expect(errors_for(mutate { it["next_id"] = 0 })).to include("next_id")
      expect(errors_for(mutate { it["decklists"] = nil })).to include("decklists")
      expect(errors_for(mutate { it["stack"] = nil })).to include("stack: must be a list")
      expect(errors_for(mutate { it["active"] = 3 })).to include("active")
      expect(errors_for(mutate { it["turn"] = 0 })).to include("turn")
      expect(errors_for(mutate { it["starting_player"] = nil })).to include("starting_player")
    end

    it "rejects a priority decision for the wrong player" do
      data = mutate do |s|
        s["pending"] = { "kind" => "priority", "player" => 1 - s["priority"].to_i }
        s["priority"] ||= 0
      end
      expect(errors_for(data)).to include("priority")
    end

    it "rejects a pending decision with no legal options" do
      data = mutate do |s|
        s["pending"] = { "kind" => "discard", "player" => 0, "count" => 1 }
        s["objects"].select { it["zone"] == "hand" && it["owner"] == 0 }.each do |o|
          o["zone"] = "library"
          s["players"][0]["library"] << o["id"]
        end
        s["players"][0]["hand"] = []
      end
      expect(errors_for(data)).to include("no legal options")
    end

    it "wraps unexpected structural garbage" do
      expect(errors_for(mutate { |s| s["history"] = 1 }.merge("history" => [{ "events" => [{ "type" => "nope" }] }])))
        .to include("malformed snapshot")
    end
  end
end
