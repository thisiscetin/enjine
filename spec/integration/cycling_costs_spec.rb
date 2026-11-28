# frozen_string_literal: true

# Cycling with {X} or non-mana costs, and "when you cycle this card" (CR 702.29a, 702.29c, 107.3).
RSpec.describe "Cycling costs and cycle-this-card triggers" do
  let(:elite) do
    { "name" => "Spec Webstrike", "mana_cost" => "{G}{G}", "types" => ["creature"], "power" => 3, "toughness" => 3,
      "abilities" => [{ "cycling" => { "cost" => "{X}{G}" } },
                      { "triggered" => { "zone" => "graveyard", "when" => { "cycles" => { "self" => true } },
                                         "targets" => [{ "filter" => { "permanent" => { "any_of" => %w[artifact enchantment],
                                                                                        "mana_value" => { "equal" => "x" } } },
                                                         "optional" => true }],
                                         "effects" => [{ "destroy" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:wraith) do
    { "name" => "Spec Wraith", "mana_cost" => "{3}{B}{B}", "types" => ["creature"], "power" => 3, "toughness" => 4,
      "abilities" => [{ "cycling" => { "cost" => [{ "pay_life" => 2 }] } }] }
  end
  let(:watcher) do
    { "name" => "Spec Cycle Watcher", "mana_cost" => "{1}{U}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "cycles" => { "controller" => "you" } },
                                         "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
  end
  let(:relic) do
    { "name" => "Spec Relic Two", "mana_cost" => "{2}", "types" => ["artifact"] }
  end
  let(:catalog) { catalog_with(elite, wraith, watcher, relic) }

  def board(hand)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Forest", count: 3
        battlefield "Spec Cycle Watcher"
        hand(*hand)
        library "Forest", count: 10
      end
      player("bob") do
        battlefield "Spec Relic Two"
        library "Forest", count: 10
      end
    end
  end

  def pay!(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def life(game, seat) = game.view_for(:observer)["players"][seat]["life"]

  def cycle!(game, card)
    id = obj_id(game, card, zone: :hand, player: "alice")
    game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == id })
  end

  def resolve!(game, target: nil)
    50.times do
      break if game.pending_decision.kind == "priority" && game.state.stack.empty? && game.state.pending_triggers.empty?

      options = game.legal_options
      pick = (target && options.find { it[:target] == target }) || options.find { it[:type] == "pass" } || options.first
      game.submit(pick)
    end
  end

  it "Cycling {X}{G}: X is announced; the cycle-this-card trigger uses that X (CR 702.29a, 702.29c, 107.3)" do
    game = board(["Spec Webstrike"])
    relic = obj_id(game, "spec_relic_two", player: "bob")
    cycle!(game, "spec_webstrike")
    expect(game.pending_decision.kind).to eq("choose_x")
    game.submit(type: "x", value: 2)
    pay!(game)
    resolve!(game, target: relic)
    expect(game.state.battlefield).not_to include(relic)
    expect(ids_in(game, "alice", :hand).size).to eq(1) # drew a card
    expect(life(game, 0)).to eq(21) # "whenever you cycle" saw it
  end

  it "the trigger's target must have mana value X (CR 107.3, 702.29c)" do
    game = board(["Spec Webstrike"])
    relic = obj_id(game, "spec_relic_two", player: "bob")
    cycle!(game, "spec_webstrike")
    game.submit(type: "x", value: 1)
    pay!(game)
    resolve!(game, target: relic)
    expect(game.state.battlefield).to include(relic)
  end

  it "Cycling—pay 2 life is cycling: it draws and other cycle triggers see it (CR 702.29a, 118.3)" do
    game = board(["Spec Wraith"])
    cycle!(game, "spec_wraith")
    pay!(game)
    resolve!(game)
    expect(life(game, 0)).to eq(19)
    expect(ids_in(game, "alice", :graveyard).map { game.state.object(it).card }).to include("spec_wraith")
  end

  it "describes and validates its costs (CR 702.29a)" do
    defn = Enjine::CardDefinition.from_h(wraith)
    expect(defn.ability_instances.first.ability.to_s).to eq("Cycling Pay 2 life")
    bad = wraith.merge("name" => "Spec Bad Wraith", "abilities" => [{ "cycling" => { "cost" => [] } }])
    expect { catalog_with(bad) }.to raise_error(Enjine::InvalidCardDefinition, /cycling.cost/)
    tap = wraith.merge("name" => "Spec Tap Wraith", "abilities" => [{ "cycling" => { "cost" => ["tap"] } }])
    expect { catalog_with(tap) }.to raise_error(Enjine::InvalidCardDefinition, /in your hand/)
    odd = wraith.merge("name" => "Spec Odd Wraith", "abilities" => [{ "cycling" => { "cost" => 3 } }])
    expect { catalog_with(odd) }.to raise_error(Enjine::InvalidCardDefinition, /cycling.cost/)
    trig = { "triggered" => { "when" => { "cycles" => { "self" => "yes" } }, "effects" => [] } }
    expect { catalog_with(wraith.merge("name" => "Spec Trig", "abilities" => [trig])) }
      .to raise_error(Enjine::InvalidCardDefinition, /self/)
    expect(Enjine::CardDefinition.from_h(elite).ability_instances[1].ability.to_s).to include("When you cycle this card")
  end
end
