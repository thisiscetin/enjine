# frozen_string_literal: true

# A kicked permanent remembers it was kicked (CR 702.33d, 400.7d), `exile` moves a spell off the stack
# (CR 701.13a), and filter ranges take `equal` and computed bounds (CR 202.3, 608.2h).
RSpec.describe "Kicked permanents, exiling spells and computed filter ranges" do
  let(:raptor) do
    { "name" => "Spec Surge Raptor", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "abilities" => [{ "kicker" => { "cost" => [{ "mana" => "{1}" }] } },
                      { "triggered" => { "when" => { "enters" => {} }, "if" => { "kicked" => true },
                                         "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
  end
  let(:rebuff) do
    { "name" => "Spec Gambit Rebuff", "mana_cost" => "{1}{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => {
        "targets" => [{ "spell" => { "not" => ["creature"], "controller" => "opponent" } }],
        "effects" => [{ "may" => { "chooser" => { "controller_of" => { "target" => 0 } },
                                   "effects" => [{ "exile" => { "to" => { "target" => 0 } } }],
                                   "otherwise" => [{ "draw" => { "amount" => 1 } }] } }]
      } }] }
  end
  let(:bomb) do
    { "name" => "Spec Charge Bomb", "mana_cost" => "{3}", "types" => ["artifact"],
      "abilities" => [{ "activated" => {
        "cost" => [{ "mana" => "{1}" }, "sacrifice"],
        "effects" => [{ "destroy" => { "to" => { "each" => { "permanent" => {
          "not" => ["land"], "mana_value" => { "equal" => { "counters" => { "of" => "self", "kind" => "charge" } } }
        } } } } }]
      } }] }
  end
  let(:strike) do
    mine = { "creature" => { "controller" => "you" } }
    { "name" => "Spec Joint Strike", "mana_cost" => "{G}", "types" => ["instant"],
      "abilities" => [{ "spell" => {
        "targets" => [mine, { "filter" => mine, "optional" => true, "distinct_from" => [0] },
                      { "creature" => { "controller" => "opponent" } }],
        "effects" => [{ "bite" => { "from" => { "target" => 0 }, "to" => { "target" => 2 } } },
                      { "bite" => { "from" => { "target" => 1 }, "to" => { "target" => 2 } } }]
      } }] }
  end
  let(:catalog) { catalog_with(raptor, rebuff, bomb, strike) }

  def board(alice_hand: [], alice_field: [], bob_hand: [], bob_field: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand(*alice_hand) unless alice_hand.empty?
        alice_field.each { |entry| entry.is_a?(Array) ? battlefield(entry[0], **entry[1]) : battlefield(entry) }
        library "Forest", count: 5
      end
      player("bob") do
        hand(*bob_hand) unless bob_hand.empty?
        battlefield(*bob_field) unless bob_field.empty?
        library "Forest", count: 5
      end
    end
  end

  def pay_all(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def settle(game)
    40.times do
      break if game.pending_decision.kind == "priority" && game.state.stack.empty?

      game.submit(game.pending_decision.kind == "priority" ? { type: "pass" } : game.legal_options.first)
    end
  end

  describe "a kicked permanent's enters trigger (CR 702.33d, 400.7d)" do
    def cast_raptor(kick)
      game = board(alice_hand: ["Spec Surge Raptor"], alice_field: %w[Forest Forest Forest])
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(type: kick ? "kick" : "no_kick")
      pay_all(game)
      settle(game)
      game
    end

    it "draws when the creature was kicked" do
      game = cast_raptor(true)
      raptor_id = obj_id(game, "Spec Surge Raptor")
      expect(game.state.object(raptor_id).memory["kicked"]).to be(true)
      expect(ids_in(game, "alice", :hand).size).to eq(1)
    end

    it "does nothing when it wasn't" do
      game = cast_raptor(false)
      expect(game.state.object(obj_id(game, "Spec Surge Raptor")).memory).not_to have_key("kicked")
      expect(ids_in(game, "alice", :hand)).to be_empty
    end
  end

  describe "exiling a spell (CR 701.13a, 608.2e)" do
    def respond(game)
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      pay_all(game)
      game.submit(type: "pass")
      game.submit(type: "cast", object: ids_in(game, "bob", :hand).first)
      game.submit(type: "target", target: game.state.stack.last)
      pay_all(game)
      game.submit(type: "pass")
      game.submit(type: "pass")
    end

    let(:game) do
      board(alice_hand: ["Divination"], alice_field: %w[Island Island Island],
            bob_hand: ["Spec Gambit Rebuff"], bob_field: %w[Mountain Mountain])
    end

    it "the targeted spell's controller chooses, and the spell is exiled" do
      respond(game)
      expect(game.pending_decision.player).to eq("alice")
      game.submit(type: "yes")
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["divination"])
      expect(game.state.stack).to be_empty
    end

    it "otherwise the Rebuff's controller draws and the spell resolves" do
      respond(game)
      game.submit(type: "no")
      settle(game)
      expect(ids_in(game, "bob", :hand).size).to eq(1)
      expect(ids_in(game, "alice", :hand).size).to eq(2)
    end

    it "validates the exile target zone list" do
      expect(Enjine::Mechanics::Effects::Exile.from_zones).to include(:stack)
    end
  end

  describe "two creatures each dealing damage equal to their power, the second optional (CR 120.3, 601.2c)" do
    def cast_strike(game, second)
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(type: "target", target: obj_id(game, "Grizzly Bears"))
      second ? game.submit(type: "target", target: obj_id(game, "Hill Giant")) : game.submit(type: "done")
      game.submit(type: "target", target: game.state.battlefield.find do
        game.state.object(it).controller == 1 && game.state.object(it).card == "craw_wurm"
      end)
      pay_all(game)
      settle(game)
    end

    it "both deal damage" do
      game = board(alice_hand: ["Spec Joint Strike"], alice_field: ["Forest", "Grizzly Bears", "Hill Giant"], bob_field: ["Craw Wurm"])
      cast_strike(game, true)
      expect(game.state.battlefield.map { game.state.object(it).card }).not_to include("craw_wurm") # 2 + 3 damage: lethal
    end

    it "without the second creature only the first does" do
      game = board(alice_hand: ["Spec Joint Strike"], alice_field: ["Forest", "Grizzly Bears", "Hill Giant"], bob_field: ["Craw Wurm"])
      cast_strike(game, false)
      expect(game.state.object(obj_id(game, "Craw Wurm")).damage).to eq(2)
    end
  end

  describe "a computed `equal` range (CR 202.3, 608.2h)" do
    it "destroys each nonland permanent whose mana value equals the sacrificed source's charge counters" do
      game = board(alice_field: [["Spec Charge Bomb", { counters: { "charge" => 2 } }], "Plains", "Grizzly Bears"],
                   bob_field: ["Hill Giant", "Island", "Grizzly Bears"])
      game.submit(type: "activate", object: obj_id(game, "Spec Charge Bomb"), ability: "printed:0")
      pay_all(game)
      settle(game)
      cards = game.state.battlefield.map { game.state.object(it).card }
      expect(cards).to contain_exactly("plains", "hill_giant", "island")
    end

    it "with no counters it destroys mana value 0 permanents (tokens)" do
      game = board(alice_field: ["Spec Charge Bomb", "Plains", "Grizzly Bears"])
      engine = Enjine::Engine.new(game.catalog, game.state) { nil }
      engine.create_token!(game.catalog.fetch("lucky_prospector").token_definitions.first, 0)
      game.submit(type: "activate", object: obj_id(game, "Spec Charge Bomb"), ability: "printed:0")
      pay_all(game)
      settle(game)
      expect(game.state.battlefield.map { game.state.object(it).card }).to contain_exactly("plains", "grizzly_bears")
    end

    it "reads `equal` and integer bounds, and rejects unknown bound keys" do
      errors = []
      Enjine::Mechanics::Filters::Permanent.build({ "mana_value" => { "equal" => 3 } }, errors, "f")
      expect(errors).to be_empty
      Enjine::Mechanics::Filters::Permanent.build({ "mana_value" => { "exactly" => 3 } }, errors, "f")
      expect(errors.first).to start_with("f.mana_value: must be")
      filter = Enjine::Mechanics::Filters::Permanent.build({ "mana_value" => { "equal" => 3 } }, [], "f")
      expect(filter.to_s).to include("equal to 3")
    end
  end
end
