# frozen_string_literal: true

# "Planeswalkers you control have '[-2]: Draw a card.'" (CR 613.1f, 606): a static grants a loyalty ability. It
# is activated like the planeswalker's own: its cost removes loyalty counters, and only one loyalty ability of
# each planeswalker each turn (CR 606.3).
RSpec.describe "Statics that grant loyalty abilities (CR 606, 613.1f)" do
  let(:shrine) do
    { "name" => "Spec Oath Shrine", "mana_cost" => "{2}{U}", "types" => ["enchantment"],
      "abilities" => [{ "static" => { "affects" => { "each" => "planeswalker", "controller" => "you" },
                                      "abilities" => [{ "loyalty" => { "cost" => -2,
                                                                       "effects" => [{ "draw" => { "amount" => 2 } }] } }] } }] }
  end
  let(:walker) do
    { "name" => "Spec Tide Sage", "mana_cost" => "{2}{U}", "types" => ["planeswalker"], "subtypes" => ["sage"], "loyalty" => 4,
      "abilities" => [{ "loyalty" => { "cost" => 1, "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
  end
  let(:warden) do
    { "name" => "Spec Oath Warden", "mana_cost" => "{1}{W}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "abilities" => [{ "triggered" => { "when" => { "activates_ability" => { "controller" => "opponent", "loyalty" => true } },
                                         "effects" => [{ "gain_life" => { "amount" => 2 } }] } }] }
  end
  let(:lantern) do
    { "name" => "Spec Signal Lantern", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{0}" }], "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
  end
  let(:catalog) { catalog_with(shrine, walker, warden, lantern) }

  let(:game) do
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Spec Oath Shrine"
        battlefield "Spec Tide Sage", counters: { "loyalty" => 4 }
        battlefield "Spec Signal Lantern"
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Spec Oath Warden"
        library "Forest", count: 5
      end
    end
  end

  def activations(game, id) = game.legal_options.select { it[:type] == "activate" && it[:object] == id }

  it "offers the granted loyalty ability, pays it with loyalty counters, and keeps one loyalty ability a turn" do
    sage = obj_id(game, "Spec Tide Sage")
    granted = activations(game, sage).find { it[:ability].start_with?("granted") }
    expect(granted).not_to be_nil
    expect(activations(game, sage).size).to eq(2)
    game.submit(granted)
    game.submit(type: "pass") until game.state.stack.empty? && game.pending_decision.kind == "priority"
    expect(game.state.object(sage).counters["loyalty"]).to eq(2)
    expect(game.state.players[0].hand.size).to eq(2)
    expect(activations(game, sage)).to be_empty # CR 606.3: one loyalty ability per planeswalker per turn
  end

  it "doesn't let a non-planeswalker use the grant (only matching permanents get it)" do
    shrine_id = obj_id(game, "Spec Oath Shrine")
    expect(activations(game, shrine_id)).to be_empty
  end

  it "triggers on an opponent's loyalty abilities only (activates_ability loyalty: true)" do
    resolve = -> { game.submit(type: "pass") until game.state.stack.empty? && game.pending_decision.kind == "priority" }
    game.submit(type: "activate", object: obj_id(game, "Spec Signal Lantern"), ability: "printed:0")
    resolve.call
    expect(game.state.players[1].life).to eq(20)
    game.submit(type: "activate", object: obj_id(game, "Spec Tide Sage"), ability: "printed:0")
    resolve.call
    expect(game.state.players[1].life).to eq(22)
    trigger = Enjine::CardDefinition.from_h(warden).abilities.first
    expect(trigger.to_s).to start_with("Whenever an opponent activates a loyalty ability")
  end

  describe "a -X loyalty ability (CR 606.4, 107.3)" do
    let(:storm) do
      { "name" => "Spec Storm Sage", "mana_cost" => "{3}{R}", "types" => ["planeswalker"], "subtypes" => ["sage"], "loyalty" => 5,
        "abilities" => [{ "loyalty" => { "cost" => "-X",
                                         "effects" => [{ "lose_life" => { "amount" => "x", "to" => "each_opponent" } }] } }] }
    end
    let(:storm_game) do
      build_game(catalog_with(storm)) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          battlefield "Spec Storm Sage", counters: { "loyalty" => 5 }
          library "Forest", count: 5
        end
        player("bob") { library "Forest", count: 5 }
      end
    end

    it "announces X up to its loyalty, removes X loyalty counters and uses X" do
      sage = obj_id(storm_game, "Spec Storm Sage")
      storm_game.submit(type: "activate", object: sage, ability: "printed:0")
      expect(storm_game.pending_decision.kind).to eq("choose_x")
      expect(storm_game.pending_decision.details["max"]).to eq(5)
      storm_game.submit(type: "x", value: 3)
      storm_game.submit(type: "pass") until storm_game.state.stack.empty? && storm_game.pending_decision.kind == "priority"
      expect(storm_game.state.object(sage).counters["loyalty"]).to eq(2)
      expect(storm_game.state.players[1].life).to eq(17)
    end

    it "is written -X and only as -X" do
      expect(Enjine::CardDefinition.from_h(storm).abilities.first.to_s).to start_with("-X: ")
      bad = storm.merge("abilities" => [{ "loyalty" => { "cost" => "+X", "effects" => [] } }])
      expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition, /loyalty change or "-X"/)
    end
  end
end
