# frozen_string_literal: true

RSpec.describe "The legend rule (CR 704.5j)" do
  let(:hero) do
    { "name" => "Captain Example", "mana_cost" => "{1}{W}", "types" => ["creature"], "supertypes" => ["legendary"],
      "power" => 2, "toughness" => 2 }
  end
  let(:catalog) { catalog_with(hero) }

  def game_with(alice_cards, bob_cards, hand: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        alice_cards.each { battlefield it }
        hand.each { hand it }
        battlefield "Plains", "Plains"
      end
      player("bob") { bob_cards.each { battlefield it } }
    end
  end

  it "makes the controller choose one when a second copy enters; the other goes to the graveyard" do
    game = game_with(["Captain Example"], [], hand: ["Captain Example"])
    first = obj_id(game, "Captain Example")
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.state.battlefield.select { game.state.object(it).card == "plains" }.each do |land|
      game.submit(type: "activate_mana", object: land, ability: "intrinsic:plains")
      game.submit(game.legal_options.find { it[:type] == "pay_mana" })
    end
    pass_both(game)
    expect(game.pending_decision).to have_attributes(kind: "legend_rule", player: "alice",
                                                     details: { "name" => "Captain Example" })
    second = game.state.battlefield.find { game.state.object(it).card == "captain_example" && it != first }
    expect(game.legal_options).to contain_exactly({ type: "keep", object: first }, { type: "keep", object: second })
    entry = game.submit(type: "keep", object: second)
    expect(entry.events.grep(Enjine::Events::ZoneChanged).map(&:reason)).to eq(["sba_legend_rule"])
    expect(game.state.battlefield).to include(second)
    expect(game.state.battlefield).not_to include(first)
    expect(game.pending_decision.kind).to eq("priority")
  end

  it "doesn't apply across players or to non-legendary permanents" do
    game = game_with(["Captain Example", "Grizzly Bears", "Grizzly Bears"], ["Captain Example"])
    game.submit(type: "pass")
    expect(game.pending_decision.kind).to eq("priority")
    expect(game.state.battlefield.size).to eq(6)
  end

  it "survives export/import while waiting for the choice" do
    game = game_with(["Captain Example", "Captain Example"], [])
    game.submit(type: "pass")
    expect(game.pending_decision.kind).to eq("legend_rule")
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.pending_decision).to eq(game.pending_decision)
    copy.submit(copy.legal_options.first)
    expect(copy.state.battlefield.count { copy.state.object(it).card == "captain_example" }).to eq(1)
  end
end
