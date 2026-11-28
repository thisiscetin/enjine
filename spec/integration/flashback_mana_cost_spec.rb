# frozen_string_literal: true

# Flashback whose cost is the card's own mana cost (CR 702.34a), printed or granted to a graveyard card.
RSpec.describe "Flashback with a cost equal to the mana cost" do
  let(:grant) do
    granted = { "flashback" => { "cost" => "mana_cost" } }
    { "name" => "Spec Flashback Grant", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => [{ "graveyard_card" => { "controller" => "you", "any_of" => %w[instant sorcery] } }],
                                     "effects" => [{ "grant_ability" => { "to" => { "target" => 0 }, "duration" => "end_of_turn",
                                                                          "ability" => granted } }] } }] }
  end
  let(:bolt) do
    { "name" => "Spec Flash Bolt", "mana_cost" => "{1}{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "deal_damage" => { "amount" => 3, "to" => "each_opponent" } }] } }] }
  end
  let(:blast) do
    { "name" => "Spec X Blast", "mana_cost" => "{X}{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "deal_damage" => { "amount" => "x", "to" => "each_opponent" } }] } },
                      { "flashback" => { "cost" => "mana_cost" } }] }
  end
  let(:catalog) { catalog_with(grant, bolt, blast) }

  def board(hand: [], graveyard: [], mountains: 4)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Mountain", count: mountains
        hand(*hand) unless hand.empty?
        graveyard(*graveyard) unless graveyard.empty?
        library "Forest", count: 10
      end
      player("bob") { library "Forest", count: 10 }
    end
  end

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

  def id_of(game, card, zone) = obj_id(game, card, zone: zone, player: "alice")
  def bob_life(game) = game.view_for(:observer)["players"][1]["life"]
  def exiled(game) = game.state.exile.map { game.state.object(it).card }

  it "a granted flashback casts the card for its mana cost, then exiles it (CR 702.34a)" do
    game = board(hand: ["Spec Flashback Grant"], graveyard: ["Spec Flash Bolt"])
    expect(game.legal_options.none? { it[:type] == "cast" && it[:object] == id_of(game, "spec_flash_bolt", :graveyard) }).to be(true)
    game.submit(type: "cast", object: id_of(game, "spec_flashback_grant", :hand))
    game.submit(game.legal_options.find { it[:type] == "target" })
    pay!(game)
    resolve!(game)
    bolt = id_of(game, "spec_flash_bolt", :graveyard)
    option = game.legal_options.find { it[:type] == "cast" && it[:object] == bolt }
    expect(option[:via]).to start_with("alt:granted")
    game.submit(option)
    pay!(game)
    expect(game.state.players[0].mana_pool.values.sum).to eq(0)
    expect(game.state.battlefield.count { game.state.object(it).tapped }).to eq(3)
    resolve!(game)
    expect(bob_life(game)).to eq(17)
    expect(exiled(game)).to include("spec_flash_bolt")
  end

  it "the granted flashback ends with the turn (CR 702.34a, 514.2)" do
    game = board(hand: ["Spec Flashback Grant"], graveyard: ["Spec Flash Bolt"])
    game.submit(type: "cast", object: id_of(game, "spec_flashback_grant", :hand))
    game.submit(game.legal_options.find { it[:type] == "target" })
    pay!(game)
    resolve!(game)
    skip_to(game, :precombat_main, turn: game.turn + 2)
    bolt = id_of(game, "spec_flash_bolt", :graveyard)
    expect(game.legal_options.none? { it[:type] == "cast" && it[:object] == bolt }).to be(true)
  end

  it "a printed flashback for its mana cost pays X too (CR 702.34a, 107.3)" do
    game = board(graveyard: ["Spec X Blast"])
    blast = id_of(game, "spec_x_blast", :graveyard)
    game.submit(game.legal_options.find { it[:type] == "cast" && it[:object] == blast })
    game.submit(type: "x", value: 2) if game.pending_decision.kind == "choose_x"
    pay!(game)
    resolve!(game)
    expect(bob_life(game)).to eq(18)
    expect(exiled(game)).to include("spec_x_blast")
  end

  it "describes itself (CR 702.34a)" do
    ability = Enjine::CardDefinition.from_h(blast).ability_instances.map(&:ability).find { it.kind == :alternative_cost }
    expect(ability.to_s).to eq("Flashback (its mana cost)")
  end
end
