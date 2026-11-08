# frozen_string_literal: true

RSpec.describe "Activated abilities (CR 602) and summoning sickness (CR 302.6)" do
  def board(controlled_since:)
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Prodigal Pyromancer", controlled_since: controlled_since
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Raging Goblin"
        library "Forest", count: 5
      end
    end
  end

  it "can't use a {T} ability the turn the creature came under your control" do
    game = board(controlled_since: 3)
    expect(game.legal_options).to eq([{ type: "pass" }])
  end

  it "taps as a cost, targets, then resolves from the stack" do
    game = board(controlled_since: 1)
    pyro, goblin = game.state.battlefield
    game.submit(type: "activate", object: pyro, ability: 0)
    expect(game.legal_options).to eq([{ type: "target", target: "player:alice" }, { type: "target", target: "player:bob" },
                                      { type: "target", target: pyro }, { type: "target", target: goblin },
                                      { type: "cancel" }])
    entry = game.submit(type: "target", target: goblin)
    expect(entry.events.map(&:type)).to eq(%w[target_chosen tapped ability_activated])
    expect(game.state.object(pyro).tapped).to be(true)
    expect(game.legal_options).to eq([{ type: "pass" }]) # tapped: can't activate again
    pass_both(game)
    expect(game.state.battlefield).to eq([pyro])
  end

  it "cancelling an activation leaves the source untapped" do
    game = board(controlled_since: 1)
    pyro = game.state.battlefield.first
    game.submit(type: "activate", object: pyro, ability: 0)
    game.submit(type: "cancel")
    expect(game.state.object(pyro).tapped).to be(false)
    expect(game.state.stack).to be_empty
  end

  it "pays mana costs of activated abilities and excludes the {T} source from paying" do
    forge = { "name" => "Ember Forge", "mana_cost" => "{1}", "types" => %w[artifact],
              "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{R}" }, "tap"],
                                                 "effects" => [{ "lose_life" => { "amount" => 2, "to" => "each_opponent" } }] } },
                              { "mana" => { "cost" => ["tap"], "produce" => "{R}" } }] }
    game = build_game(catalog_with(forge)) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Ember Forge", "Mountain"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    forge_id, mountain = game.state.battlefield
    game.submit(type: "activate", object: forge_id, ability: 0)
    expect(game.legal_options).to eq([{ type: "activate_mana", object: mountain, ability: 0 }, { type: "cancel" }])
    game.submit(type: "activate_mana", object: mountain, ability: 0)
    game.submit(type: "pay_mana", mana: "R")
    pass_both(game)
    expect(game.view_for(:observer)["players"][1]["life"]).to eq(18)
  end
end
