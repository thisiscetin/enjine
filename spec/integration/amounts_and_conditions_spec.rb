# frozen_string_literal: true

RSpec.describe "Computed amounts and conditions (CR 608.2c, 608.2h, 603.4)" do
  def card(name, types, abilities, extra = {})
    { "name" => name, "mana_cost" => "{R}", "types" => types, "abilities" => abilities }.merge(extra)
  end

  let(:swarm_bolt) do
    card("Swarm Bolt", ["instant"], [{ "spell" => { "targets" => ["any_target"], "effects" => [
           { "deal_damage" => { "amount" => { "count" => { "each" => "creature", "controller" => "you" } }, "to" => { "target" => 0 } } }
         ] } }])
  end
  let(:fling) do
    card("Mighty Fling", ["instant"], [{ "spell" => { "targets" => [{ "creature" => { "controller" => "you" } }, "player"], "effects" => [
           { "deal_damage" => { "amount" => { "power" => { "target" => 0 } }, "to" => { "target" => 1 } } }
         ] } }])
  end
  let(:rally) do
    card("Rally Cry", ["sorcery"], [{ "spell" => { "effects" => [
           { "draw" => { "amount" => 1 } },
           { "gain_life" => { "amount" => 5, "if" => { "controls" => { "each" => "creature", "controller" => "you" }, "at_least" => 3 } } }
         ] } }])
  end
  let(:mentor) do
    card("Lonely Mentor", ["creature"], [{ "triggered" => { "when" => { "step_begins" => { "step" => "upkeep" } },
                                                            "if" => { "life" => "you", "at_most" => 10 },
                                                            "effects" => [{ "gain_life" => { "amount" => 2 } }] } }],
         "power" => 1, "toughness" => 1)
  end
  let(:catalog) { catalog_with(swarm_bolt, fling, rally, mentor) }

  def board(life: 20, creatures: [], hand: nil)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", life: life) do
        hand hand if hand
        creatures.each { battlefield it }
        battlefield "Mountain"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
  end

  def cast(game, *targets)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    targets.each { game.submit(type: "target", target: it) }
    game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
    game.submit(type: "pay_mana", mana: "R")
    pass_both(game)
  end

  def life(game, who) = game.view_for(:observer)["players"].find { it["name"] == who }["life"]

  it "counts creatures you control on resolution" do
    game = board(hand: "Swarm Bolt", creatures: ["Grizzly Bears", "Hill Giant", "Savannah Lions"])
    cast(game, "player:bob")
    expect(life(game, "bob")).to eq(17)
  end

  it "uses a target creature's current power, including pumps" do
    game = board(hand: "Mighty Fling", creatures: ["Hill Giant"])
    cast(game, obj_id(game, "Hill Giant"), "player:bob")
    expect(life(game, "bob")).to eq(17)
  end

  it "applies an effect only if its condition holds on resolution" do
    few = board(hand: "Rally Cry", creatures: ["Grizzly Bears"])
    cast(few)
    expect(life(few, "alice")).to eq(20)
    many = board(hand: "Rally Cry", creatures: ["Grizzly Bears", "Hill Giant", "Savannah Lions"])
    cast(many)
    expect(life(many, "alice")).to eq(25)
  end

  it "intervening 'if': no trigger unless the condition holds when the event happens (CR 603.4)" do
    healthy = build_game(catalog) do
      turn 3, active: "alice", step: :draw
      player("alice") do
        battlefield "Lonely Mentor"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    skip_to(healthy, :upkeep, turn: 5)
    expect(healthy.state.stack).to be_empty

    low = build_game(catalog) do
      turn 3, active: "alice", step: :draw
      player("alice", life: 8) do
        battlefield "Lonely Mentor"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    skip_to(low, :upkeep, turn: 5)
    expect(low.view_for(:observer)["stack"].map { it["name"] }).to eq(["Lonely Mentor ability"])
    low.state.players[0].life = 15 # the condition is false again before resolution
    pass_both(low)
    expect(low.state.players[0].life).to eq(15)
    expect(low.history.last.events.map(&:type)).to include("fizzled")
  end

  it "validates amounts and conditions" do
    bad = card("Bad Math", ["instant"], [{ "spell" => { "effects" => [
                 { "draw" => { "amount" => { "luck" => "you" } } },
                 { "gain_life" => { "amount" => 1, "if" => { "weather" => "sunny" } } },
                 { "gain_life" => { "amount" => 1, "if" => { "life" => "you" } } }
               ] } }])
    expect { Enjine::CardDefinition.from_h(bad) }
      .to raise_error(Enjine::InvalidCardDefinition, /amount: must be an integer.*unknown condition.*needs at_least/m)
    text = Enjine::CardDefinition.from_h(rally).spell_ability.to_s
    expect(text).to include("gain life 5")
    expect(Enjine::CardDefinition.from_h(mentor).abilities.first.to_s).to include("if the life of you is at most 10")
  end
end
