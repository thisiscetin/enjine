# frozen_string_literal: true

# Impending N—[cost] (CR 702.176a): alternative cost, time counters, not a creature while it has one.
RSpec.describe "Impending" do
  let(:overlord) do
    { "name" => "Spec Overlord", "mana_cost" => "{3}{G}{G}", "types" => %w[enchantment creature],
      "subtypes" => %w[avatar horror], "power" => 6, "toughness" => 6,
      "abilities" => [{ "impending" => { "amount" => 2, "cost" => "{G}" } },
                      { "triggered" => { "when" => { "enters" => {} }, "effects" => [{ "gain_life" => { "amount" => 2 } }] } }] }
  end
  let(:catalog) { catalog_with(overlord) }

  def board(lands: 1)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Forest", count: lands
        hand "Spec Overlord"
        library "Forest", count: 20
      end
      player("bob") { library "Forest", count: 20 }
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)

  def pay!(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def resolve!(game)
    50.times do
      break if game.pending_decision.kind == "priority" && game.state.stack.empty? && game.state.pending_triggers.empty?

      game.submit(game.legal_options.find { it[:type] == "pass" } || game.legal_options.first)
    end
  end

  def overlord_on(game) = game.state.battlefield.map { game.state.object(it) }.find { it.card == "spec_overlord" }

  def cast_impending!(game)
    hand = obj_id(game, "spec_overlord", zone: :hand, player: "alice")
    option = game.legal_options.find { it[:type] == "cast" && it[:object] == hand && it[:via] }
    game.submit(option)
    pay!(game)
    resolve!(game)
  end

  it "casts for the impending cost, enters with time counters and isn't a creature (CR 702.176a)" do
    game = board
    cast_impending!(game)
    perm = overlord_on(game)
    chars = engine(game).chars(perm)
    expect(perm.counters).to eq("time" => 2)
    expect(chars.types).to eq([:enchantment])
    expect(chars.subtypes).to be_empty
    expect(chars.power).to be_nil
    expect(perm.memory["cast_with"]).to eq("impending")
    expect(game.view_for(:observer)["players"][0]["life"]).to eq(22) # its enters trigger still triggers
  end

  it "removes a time counter at each of its controller's end steps, then is a creature (CR 702.176a, 122.6)" do
    game = board
    cast_impending!(game)
    skip_to(game, :end)
    resolve!(game)
    expect(overlord_on(game).counters).to eq("time" => 1)
    skip_to(game, :end, turn: game.turn + 2)
    resolve!(game)
    perm = overlord_on(game)
    expect(perm.counters.fetch("time", 0)).to eq(0)
    expect(engine(game).chars(perm).creature?).to be(true)
    expect(engine(game).chars(perm).power).to eq(6)
  end

  it "cast for its mana cost, it's a creature with no counters (CR 702.176a)" do
    game = board(lands: 5)
    hand = obj_id(game, "spec_overlord", zone: :hand, player: "alice")
    game.submit(type: "cast", object: hand)
    pay!(game)
    resolve!(game)
    perm = overlord_on(game)
    expect(perm.counters).to be_empty
    expect(engine(game).chars(perm).creature?).to be(true)
  end

  it "validates its amount and describes itself (CR 702.176a)" do
    bad = overlord.merge("name" => "Spec Bad Overlord", "abilities" => [{ "impending" => { "amount" => 0, "cost" => "{G}" } }])
    expect { catalog_with(bad) }.to raise_error(Enjine::InvalidCardDefinition, /impending.amount/)
    ability = Enjine::CardDefinition.from_h(overlord).ability_instances.first.ability
    expect(ability.to_s).to eq("Impending 2—{G}")
    cond = Enjine::Mechanics::Condition.build({ "cast_with" => "impending" }, errors = [], "c")
    expect(errors).to be_empty
    expect(cond.to_s).to include("impending")
  end
end
