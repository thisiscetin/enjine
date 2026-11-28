# frozen_string_literal: true

# Persist (CR 702.79a) and undying (CR 702.93a) as keywords: printed, granted by a static, seen by filters.
RSpec.describe "Persist and undying" do
  let(:mourner) do
    { "name" => "Spec Mourner", "mana_cost" => "{1}{B}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "keywords" => ["persist"] }
  end
  let(:revenant) do
    { "name" => "Spec Revenant", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 2, "toughness" => 1,
      "keywords" => ["undying"] }
  end
  let(:carrier) do
    { "name" => "Spec Carrier", "mana_cost" => "{3}{B}", "types" => ["creature"], "power" => 3, "toughness" => 3,
      "abilities" => [{ "static" => { "affects" => { "each" => { "creature" => { "token" => false } }, "other" => true,
                                                     "controller" => "you" },
                                      "keywords" => ["persist"] } }] }
  end
  let(:bear) do
    { "name" => "Spec Bear", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 2, "toughness" => 2 }
  end
  let(:doom) do
    { "name" => "Spec Doom", "mana_cost" => "{B}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [{ "destroy" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:catalog) { catalog_with(mourner, revenant, carrier, bear, doom) }

  def board(*creatures, counters: {})
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        creatures.each { battlefield it, counters: counters.fetch(it, {}) }
        hand "Spec Doom"
        battlefield "Swamp"
        library "Forest", count: 10
      end
      player("bob") { library "Forest", count: 10 }
    end
  end

  def kill!(game, name)
    target = obj_id(game, Enjine::CardDefinition.slug(name))
    game.submit(type: "cast", object: obj_id(game, "spec_doom", zone: :hand, player: "alice"))
    game.submit(game.legal_options.find { it[:target] == target }) while game.pending_decision.kind == "choose_target"
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
    resolve!(game)
  end

  def resolve!(game)
    100.times do
      break if game.pending_decision.kind == "priority" && game.state.stack.empty? && game.state.pending_triggers.empty?

      options = game.legal_options
      game.submit(options.find { it[:type] == "pass" } || options.first)
    end
  end

  def on_battlefield(game, name)
    game.state.battlefield.map { game.state.object(it) }.find { it.card == Enjine::CardDefinition.slug(name) }
  end

  it "returns a persist creature with a -1/-1 counter, and not again once it has one (CR 702.79a)" do
    game = board("Spec Mourner")
    kill!(game, "Spec Mourner")
    back = on_battlefield(game, "Spec Mourner")
    expect(back.counters).to eq("-1/-1" => 1)
    expect(back.controller).to eq(0)
  end

  it "doesn't return a persist creature that died with a -1/-1 counter (CR 702.79a, 603.10a)" do
    game = board("Spec Mourner", counters: { "Spec Mourner" => { "-1/-1" => 1 } })
    kill!(game, "Spec Mourner")
    expect(on_battlefield(game, "Spec Mourner")).to be_nil
  end

  it "returns an undying creature with a +1/+1 counter (CR 702.93a)" do
    game = board("Spec Revenant")
    kill!(game, "Spec Revenant")
    expect(on_battlefield(game, "Spec Revenant").counters).to eq("+1/+1" => 1)
  end

  it "doesn't return an undying creature that had a +1/+1 counter (CR 702.93a)" do
    game = board("Spec Revenant", counters: { "Spec Revenant" => { "+1/+1" => 1 } })
    kill!(game, "Spec Revenant")
    expect(on_battlefield(game, "Spec Revenant")).to be_nil
  end

  it "a static granting persist gives the keyword and its dies trigger (CR 702.79a, 613.1f, 603.10a)" do
    game = board("Spec Carrier", "Spec Bear")
    bear_id = obj_id(game, "spec_bear")
    expect(game.instance_variable_get(:@engine).chars(bear_id).keyword?(:persist)).to be(true)
    kill!(game, "Spec Bear")
    expect(on_battlefield(game, "Spec Bear").counters).to eq("-1/-1" => 1)
  end
end
