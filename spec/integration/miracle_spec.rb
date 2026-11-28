# frozen_string_literal: true

# Miracle [cost] (CR 702.94a-b): revealed as the first card drawn this turn, its trigger lets you cast it for the cost.
RSpec.describe "Miracle" do
  let(:wrath) do
    { "name" => "Spec Thunder Wrath", "mana_cost" => "{4}{R}{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "deal_damage" => { "amount" => 5, "to" => "each_opponent" } }] } },
                      { "miracle" => { "cost" => "{R}" } }] }
  end
  let(:bolt) do
    { "name" => "Spec Miracle Bolt", "mana_cost" => "{2}{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "effects" => [{ "deal_damage" => { "amount" => 2, "to" => "each_opponent" } }] } }] }
  end
  let(:historian) do
    { "name" => "Spec Historian", "mana_cost" => "{3}{R}{W}", "types" => ["creature"], "power" => 5, "toughness" => 5,
      "abilities" => [{ "cards_have" => { "zone" => "hand", "cards" => { "types" => %w[instant] },
                                          "ability" => { "miracle" => { "cost" => "{R}" } } } }] }
  end
  let(:catalog) { catalog_with(wrath, bolt, historian) }

  def board(top:, battlefield: [], step: :upkeep, second: "Forest")
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice") do
        battlefield "Mountain", count: 2
        battlefield.each { battlefield it }
        library top, second, "Forest", "Forest", "Forest"
      end
      player("bob") { library "Forest", count: 10 }
    end
  end

  def pay!(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def bob_life(game) = game.view_for(:observer)["players"][1]["life"]

  # Passes until the miracle trigger asks (or the draw step's priority with an empty stack).
  def to_choice(game)
    50.times do
      return game if game.pending_decision.kind == "effect_choice"
      return game if game.step == :precombat_main

      options = game.legal_options
      game.submit(options.find { it[:type] == "pass" } || options.first)
    end
  end

  def finish(game)
    50.times do
      break if game.pending_decision.kind == "priority" && game.state.stack.empty?

      options = game.legal_options
      game.submit(options.find { it[:type] == "pass" } || options.first)
    end
  end

  it "drawn as the first card this turn, its trigger casts it for the miracle cost (CR 702.94a)" do
    game = board(top: "Spec Thunder Wrath")
    to_choice(game)
    expect(game.pending_decision.kind).to eq("effect_choice")
    choice = game.legal_options.find { it[:type] == "cast" } || game.legal_options.find { it.values.include?("cast") }
    game.submit(choice)
    pay!(game)
    finish(game)
    expect(bob_life(game)).to eq(15)
    expect(game.state.battlefield.count { game.state.object(it).tapped }).to eq(1)
  end

  it "declining leaves the card in hand, and it isn't castable for the miracle cost at priority (CR 702.94a)" do
    game = board(top: "Spec Thunder Wrath")
    to_choice(game)
    game.submit(game.legal_options.find { it.values.include?("done") })
    finish(game)
    skip_to(game, :precombat_main)
    wrath = obj_id(game, "spec_thunder_wrath", zone: :hand, player: "alice")
    expect(game.legal_options.select { it[:object] == wrath }).to be_empty
  end

  it "the second card drawn this turn doesn't trigger (CR 702.94a, 121.2)" do
    draw_two = { "name" => "Spec Draw Two", "mana_cost" => "{R}", "types" => ["instant"],
                 "abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 2 } }] } }] }
    game = build_game(catalog_with(wrath, draw_two)) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Mountain", count: 2
        hand "Spec Draw Two"
        library "Forest", "Spec Thunder Wrath", "Forest"
      end
      player("bob") { library "Forest", count: 10 }
    end
    engine = game.instance_variable_get(:@engine)
    engine.turn_log(0)["drawn"] = 1 # the draw step's card was drawn already
    game.submit(type: "cast", object: obj_id(game, "spec_draw_two", zone: :hand, player: "alice"))
    pay!(game)
    finish(game)
    expect(game.state.pending_triggers).to be_empty
    expect(ids_in(game, "alice", :hand).map { game.state.object(it).card }).to include("spec_thunder_wrath")
  end

  it "a permanent gives instant cards in your hand miracle (CR 702.94a, 611.3a)" do
    game = board(top: "Spec Miracle Bolt", battlefield: ["Spec Historian"])
    to_choice(game)
    expect(game.pending_decision.kind).to eq("effect_choice")
    game.submit(game.legal_options.find { it.values.include?("cast") })
    pay!(game)
    finish(game)
    expect(bob_life(game)).to eq(18)
  end

  it "a card without miracle drawn first doesn't trigger (CR 702.94a)" do
    game = board(top: "Spec Miracle Bolt")
    to_choice(game)
    expect(game.pending_decision.kind).not_to eq("effect_choice")
  end

  it "describes itself and validates its cost (CR 702.94a)" do
    defn = Enjine::CardDefinition.from_h(wrath)
    expect(defn.ability_instances.map { it.ability.to_s }.join(" ")).to include("Miracle {R}", "first card you drew")
    bad = wrath.merge("name" => "Spec Bad Wrath", "abilities" => [{ "miracle" => {} }])
    expect { catalog_with(bad) }.to raise_error(Enjine::InvalidCardDefinition, /miracle.cost/)
  end
end
