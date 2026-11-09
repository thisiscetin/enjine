# frozen_string_literal: true

# Assimilating a card exiled with the source, chosen as it resolves, with "if you can't" as a condition on
# the assimilate's result (CR 701.72a-c, 607.2a, 603.3d); "until your next turn" pumps (CR 611.2a-c);
# "at the beginning of the next combat this turn" delayed triggers (CR 603.7b).
RSpec.describe "Assimilating linked cards, 'until your next turn' and 'the next combat this turn'" do
  let(:lattice) do
    { "name" => "Hive Lattice", "mana_cost" => "{3}", "types" => %w[artifact creature], "power" => 3, "toughness" => 3,
      "abilities" => [{ "triggered" => {
        "when" => { "any_of" => [{ "enters" => {} }, { "attacks" => {} }] },
        "targets" => [{ "filter" => { "creature" => { "controller" => "opponent" } }, "optional" => true }],
        "effects" => [
          { "assimilate" => { "to" => "exiled_with", "for" => { "types" => ["creature"] }, "choose" => true } },
          { "exile" => { "to" => { "target" => 0 }, "link" => true,
                         "if" => { "amount" => { "count" => { "result" => 0 } }, "at_most" => 0 } } }
        ]
      } }] }
  end
  let(:hex) do
    { "name" => "Lingering Hex", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "pump" => {
        "power" => -1, "toughness" => 0, "duration" => "until_your_next_turn",
        "to" => { "each" => { "creature" => { "controller" => "opponent" } } }
      } }] } }] }
  end
  let(:ambush) do
    { "name" => "Ambush Order", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => {
        "targets" => [{ "creature" => { "controller" => "opponent" } }],
        "effects" => [{ "delayed_trigger" => {
          "when" => { "step_begins" => { "step" => "beginning_of_combat" } }, "this_turn" => "once",
          "watch" => { "target" => 0 },
          "effects" => [{ "gain_control" => { "to" => "watched", "duration" => "end_of_turn" } },
                        { "untap" => { "to" => "watched" } },
                        { "grant" => { "keywords" => ["haste"], "to" => "watched" } }]
        } }]
      } }] }
  end
  let(:probe) do
    { "name" => "Lattice Probe", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{0}" }], "targets" => ["creature"],
                                         "effects" => [{ "exile" => { "to" => { "target" => 0 }, "link" => true } }] } },
                      { "activated" => { "cost" => [{ "mana" => "{0}" }], "effects" => [
                        { "assimilate" => { "to" => "exiled_with", "for" => { "types" => ["creature"] }, "choose" => true } }
                      ] } }] }
  end
  let(:catalog) { catalog_with(lattice, hex, ambush, probe) }

  def cast(game, spell, targets: nil)
    id = ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(spell) }
    game.submit(type: "cast", object: id)
    game.submit(type: "target", target: targets) if targets
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
    pass_both(game)
  end

  def power(game, id) = game.view_for(:observer)["battlefield"].find { it["id"] == id }["power"]

  # Passes (or skips optional choices) until the block is true.
  def advance(game)
    100.times do
      return if yield

      options = game.legal_options
      game.submit(options.find { it[:type] == "pass" } || options.find { it[:type] == "done" } || options.first)
    end
    raise "never got there"
  end

  describe "assimilate a card exiled with it, or else exile a target (CR 701.72c, 607.2a)" do
    def game_with
      build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand "Hive Lattice"
          battlefield "Swamp", count: 3
          library "Swamp", count: 5
        end
        player("bob") do
          battlefield "Grizzly Bears", "Hill Giant"
          library "Forest", count: 5
        end
      end
    end

    def trigger_targeting(game, target)
      advance(game) { game.pending_decision.kind == "choose_target" }
      game.submit(type: "target", target: target)
      game.submit(type: "done") if game.pending_decision.kind == "choose_target"
      pass_both(game)
    end

    it "exiles the target when nothing is exiled with it, then assimilates that card as it attacks" do
      game = game_with
      cast(game, "Hive Lattice")
      bears = obj_id(game, "Grizzly Bears")
      trigger_targeting(game, bears)
      exiled = game.state.exile.find { game.state.object(it).card == "grizzly_bears" }
      expect(exiled).not_to be_nil

      advance(game) { game.state.active == 1 } # summoning sickness: attack on the next turn
      advance(game) { game.state.active.zero? && game.pending_decision.kind == "declare_attackers" }
      game.submit(type: "attack", object: obj_id(game, "Hive Lattice"), target: "player:bob")
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
      giant = obj_id(game, "Hill Giant")
      trigger_targeting(game, giant)
      assimilated = obj_id(game, "Grizzly Bears")
      expect(game.state.object(assimilated)).to have_attributes(controller: 0, counters: { "+1/+1" => 1 })
      expect(game.state.battlefield).to include(giant) # it could assimilate, so the target wasn't exiled
    end
  end

  it "with several linked creature cards, the controller chooses which one to assimilate (CR 701.72c)" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") { battlefield "Lattice Probe" }
      player("bob") { battlefield "Grizzly Bears", "Hill Giant" }
    end
    probe = obj_id(game, "Lattice Probe")
    [obj_id(game, "Grizzly Bears"), obj_id(game, "Hill Giant")].each do |target|
      game.submit(type: "activate", object: probe, ability: "printed:0")
      game.submit(type: "target", target: target)
      game.submit(type: "pay_mana", mana: "") if game.pending_decision.kind == "pay_cost"
      pass_both(game)
    end
    expect(game.state.exile.size).to eq(2)
    game.submit(type: "activate", object: probe, ability: "printed:1")
    game.submit(type: "pay_mana", mana: "") if game.pending_decision.kind == "pay_cost"
    pass_both(game)
    expect(game.pending_decision.kind).to eq("effect_choice")
    giant = game.state.exile.find { game.state.object(it).card == "hill_giant" }
    expect(game.legal_options).to contain_exactly(a_hash_including(type: "assimilate", object: giant),
                                                  a_hash_including(type: "assimilate"))
    game.submit(game.legal_options.find { it[:object] == giant })
    expect(game.state.object(obj_id(game, "Hill Giant"))).to have_attributes(controller: 0, counters: { "+1/+1" => 1 })
    expect(game.state.exile.map { game.state.object(it).card }).to eq(["grizzly_bears"])
  end

  it "a pump until your next turn lasts through the opponent's turn and ends as yours begins (CR 611.2a)" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Lingering Hex"
        battlefield "Swamp"
        library "Swamp", count: 5
      end
      player("bob") do
        battlefield "Grizzly Bears"
        library "Forest", count: 5
      end
    end
    bears = obj_id(game, "Grizzly Bears")
    cast(game, "Lingering Hex")
    expect(power(game, bears)).to eq(1)
    advance(game) { game.state.active == 1 }
    expect(power(game, bears)).to eq(1)
    advance(game) { game.state.active.zero? }
    expect(power(game, bears)).to eq(2)
  end

  it "a delayed trigger at the beginning of the next combat this turn fires once (CR 603.7b)" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Ambush Order"
        battlefield "Swamp"
        library "Swamp", count: 5
      end
      player("bob") do
        battlefield "Grizzly Bears", tapped: true
        library "Forest", count: 5
      end
    end
    bears = obj_id(game, "Grizzly Bears")
    cast(game, "Ambush Order", targets: bears)
    expect(game.state.delayed_triggers.size).to eq(1)
    advance(game) { game.state.step == :beginning_of_combat && game.state.stack.empty? && game.state.object(bears).controller.zero? }
    expect(game.state.object(bears).tapped).to be(false)
    expect(game.state.delayed_triggers).to be_empty
    advance(game) { game.state.active == 1 }
    expect(game.state.object(bears).controller).to eq(1)
  end
end
