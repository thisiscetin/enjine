# frozen_string_literal: true

RSpec.describe "Target filters with restrictions (CR 115.1, 109.2)" do
  def instant(name, target)
    { "name" => name, "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => [target], "effects" => [{ "tap" => { "to" => { "target" => 0 } } }] } }] }
  end

  let(:herald) do
    { "name" => "Rally Herald", "mana_cost" => "{1}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} }, "targets" => [{ "creature" => { "other" => true, "controller" => "you" } }],
                                         "effects" => [{ "add_counters" => { "counter" => "+1/+1", "amount" => 1, "to" => { "target" => 0 } } }] } }] }
  end
  let(:catalog) do
    catalog_with(instant("Own Tap", { "creature" => { "controller" => "you" } }),
                 instant("Foe Tap", { "creature" => { "controller" => "opponent" } }),
                 instant("Nonland Tap", { "permanent" => { "not" => ["land"] } }),
                 instant("Either Tap", { "permanent" => { "any_of" => %w[artifact creature] } }),
                 instant("Raider Tap", { "creature" => { "attacking" => true } }), herald)
  end

  def candidates(spell)
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand spell
        battlefield "Mountain", "Grizzly Bears", "Bastion Golem"
      end
      player("bob") { battlefield "Hill Giant", "Forest" }
    end
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.legal_options.filter_map { it[:target] && game.state.object(it[:target]).card }
  end

  it "restricts by controller, card type, 'non-' types and combinations" do
    expect(candidates("Own Tap")).to contain_exactly("grizzly_bears", "bastion_golem")
    expect(candidates("Foe Tap")).to eq(["hill_giant"])
    expect(candidates("Nonland Tap")).to contain_exactly("grizzly_bears", "bastion_golem", "hill_giant")
    expect(candidates("Either Tap")).to contain_exactly("grizzly_bears", "bastion_golem", "hill_giant")
  end

  it "attacking creatures only (no legal target outside combat, so it can't be cast)" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Raider Tap"
        battlefield "Mountain"
      end
      player("bob") { battlefield "Hill Giant" }
    end
    expect(option_types(game)).not_to include("cast")
  end

  it "'another target creature you control' excludes the source (CR 109.2)" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Rally Herald"
        battlefield "Mountain", "Grizzly Bears"
      end
      player("bob") { battlefield "Hill Giant" }
    end
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
    game.submit(type: "pay_mana", mana: "R")
    pass_both(game)
    expect(game.legal_options).to eq([{ type: "target", target: obj_id(game, "Grizzly Bears") }])
  end

  it "validates restrictions" do
    expect { Enjine::CardDefinition.from_h(instant("Bad", { "creature" => { "controller" => "me", "not" => ["wizard"], "other" => "yes" } })) }
      .to raise_error(Enjine::InvalidCardDefinition, /controller: must be.*not: must be a list.*other: must be true/m)
    expect(Enjine::Mechanics.build_entry(:filter, { "permanent" => { "not" => ["land"], "controller" => "opponent" } }, [], "f").to_s)
      .to eq("nonland permanent an opponent controls")
  end
end
