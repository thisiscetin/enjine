# frozen_string_literal: true

# Collect evidence N (CR 701.59a-c): exile cards from your graveyard with total mana value N or greater.
RSpec.describe "Collect evidence" do
  let(:coverup) do
    { "name" => "Spec Cover-Up", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "additional_cost" => { "cost" => [{ "collect_evidence" => 4 }], "optional" => true } },
                      { "spell" => { "effects" => [{ "gain_life" => { "amount" => 1 } },
                                                   { "draw" => { "amount" => 1, "if" => { "cast_with" => "additional_cost" } } }] } }] }
  end
  let(:probe) do
    { "name" => "Spec Probe", "mana_cost" => "{B}", "types" => ["instant"],
      "abilities" => [{ "additional_cost" => { "cost" => [{ "collect_evidence" => 3 }] } },
                      { "spell" => { "effects" => [{ "gain_life" => { "amount" => 2 } }] } }] }
  end
  let(:two) { { "name" => "Spec Two Drop", "mana_cost" => "{1}{B}", "types" => ["creature"], "power" => 2, "toughness" => 2 } }
  let(:three) { { "name" => "Spec Three Drop", "mana_cost" => "{2}{B}", "types" => ["creature"], "power" => 3, "toughness" => 3 } }
  let(:catalog) { catalog_with(coverup, probe, two, three) }

  def board(hand:, graveyard:)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Swamp", count: 2
        hand(*hand)
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

  def exiled(game) = game.state.exile.map { game.state.object(it).card }
  def hand_size(game) = ids_in(game, "alice", :hand).size

  it "an optional collect evidence: chosen one card at a time, done once the total reaches N (CR 701.59a, 601.2h)" do
    game = board(hand: ["Spec Cover-Up"], graveyard: ["Spec Two Drop", "Spec Three Drop", "Forest"])
    game.submit(type: "cast", object: obj_id(game, "spec_cover_up", zone: :hand, player: "alice"))
    game.submit(type: "kick")
    expect(game.pending_decision.kind).to eq("choose_cost")
    expect(game.legal_options.map { it[:type] }).not_to include("done")
    game.submit(game.legal_options.find { it[:object] == obj_id(game, "spec_two_drop", zone: :graveyard, player: "alice") })
    expect(game.legal_options.map { it[:type] }).not_to include("done")
    game.submit(game.legal_options.find { it[:object] == obj_id(game, "spec_three_drop", zone: :graveyard, player: "alice") })
    game.submit(type: "done") if game.pending_decision.kind == "choose_cost"
    pay!(game)
    resolve!(game)
    expect(exiled(game)).to contain_exactly("spec_two_drop", "spec_three_drop")
    expect(hand_size(game)).to eq(1) # "if evidence was collected": drew
  end

  it "isn't offered without enough mana value in the graveyard (CR 701.59b, 118.3)" do
    game = board(hand: ["Spec Cover-Up", "Spec Probe"], graveyard: ["Spec Two Drop"])
    cover = obj_id(game, "spec_cover_up", zone: :hand, player: "alice")
    probe = obj_id(game, "spec_probe", zone: :hand, player: "alice")
    expect(game.legal_options.none? { it[:object] == probe }).to be(true)
    game.submit(type: "cast", object: cover)
    expect(game.legal_options.map { it[:type] }).not_to include("kick")
  end

  it "a mandatory collect evidence finishes by itself when no card is left to choose (CR 701.59a)" do
    game = board(hand: ["Spec Probe"], graveyard: ["Spec Three Drop"])
    game.submit(type: "cast", object: obj_id(game, "spec_probe", zone: :hand, player: "alice"))
    game.submit(game.legal_options.find { it[:type] == "cost" }) if game.pending_decision.kind == "choose_cost"
    pay!(game)
    resolve!(game)
    expect(exiled(game)).to eq(["spec_three_drop"])
    expect(game.view_for(:observer)["players"][0]["life"]).to eq(22)
  end

  it "validates N and describes itself (CR 701.59a)" do
    bad = probe.merge("name" => "Spec Bad Probe", "abilities" => [{ "additional_cost" => { "cost" => [{ "collect_evidence" => 0 }] } }])
    expect { catalog_with(bad) }.to raise_error(Enjine::InvalidCardDefinition, /collect_evidence/)
    defn = Enjine::CardDefinition.from_h(probe)
    expect(defn.ability_instances.first.ability.to_s).to include("Collect evidence 3")
  end
end
