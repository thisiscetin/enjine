# frozen_string_literal: true

# Void (the ability word's condition, CR 207.2c) and warp from the graveyard (CR 702.185a, 601.3).
RSpec.describe "Void and warp from the graveyard" do
  let(:acolyte) do
    { "name" => "Spec Void Acolyte", "mana_cost" => "{1}{B}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "step_begins" => { "step" => "end", "whose" => "your" } },
                                         "if" => { "void" => true }, "effects" => [{ "gain_life" => { "amount" => 3 } }] } }] }
  end
  let(:culler) do
    { "name" => "Spec Culler", "mana_cost" => "{B}{B}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "abilities" => [{ "warp" => { "cost" => [{ "mana" => "{B}" }, { "pay_life" => 2 }], "from" => %w[hand graveyard] } }] }
  end
  let(:doom) do
    { "name" => "Spec Void Doom", "mana_cost" => "{B}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["permanent"], "effects" => [{ "destroy" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:catalog) { catalog_with(acolyte, culler, doom) }

  def board(hand: [], graveyard: [], bob: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Spec Void Acolyte"
        battlefield "Swamp", count: 3
        hand(*hand) unless hand.empty?
        graveyard(*graveyard) unless graveyard.empty?
        library "Forest", count: 10
      end
      player("bob") do
        bob.each { battlefield it }
        library "Forest", count: 10
      end
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def void?(game) = Enjine::Mechanics::Condition.build({ "void" => true }, [], "c").true?(engine(game), ctx(game))
  def ctx(_game) = Enjine::Mechanics::EffectContext.new(0, nil, nil, nil)

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

  it "is false on a quiet turn, true once an opponent's nonland permanent left the battlefield (CR 207.2c, 400.7)" do
    game = board(hand: ["Spec Void Doom"], bob: ["Spec Culler"])
    expect(void?(game)).to be(false)
    game.submit(type: "cast", object: obj_id(game, "spec_void_doom", zone: :hand, player: "alice"))
    game.submit(game.legal_options.find { it[:target] == obj_id(game, "spec_culler") })
    pay!(game)
    resolve!(game)
    expect(void?(game)).to be(true)
  end

  it "a land leaving doesn't count (CR 207.2c)" do
    game = board(hand: ["Spec Void Doom"], bob: ["Swamp"])
    game.submit(type: "cast", object: obj_id(game, "spec_void_doom", zone: :hand, player: "alice"))
    game.submit(game.legal_options.find { it[:target] == obj_id(game, "swamp", player: "bob") })
    pay!(game)
    resolve!(game)
    expect(void?(game)).to be(false)
    expect(Enjine::Mechanics::Condition.build({ "void" => false }, [], "c").true?(engine(game), ctx(game))).to be(true)
  end

  it "warp from the graveyard: castable there for its warp cost, and that spell was warped (CR 702.185a, 702.185c, 601.3)" do
    game = board(graveyard: ["Spec Culler"])
    cull = obj_id(game, "spec_culler", zone: :graveyard, player: "alice")
    option = game.legal_options.find { it[:type] == "cast" && it[:object] == cull }
    expect(option[:via]).to start_with("alt:")
    game.submit(option)
    pay!(game)
    resolve!(game)
    expect(game.state.battlefield.map { game.state.object(it).card }).to include("spec_culler")
    expect(game.view_for(:observer)["players"][0]["life"]).to eq(18)
    expect(void?(game)).to be(true)
  end

  it "warp works only from the hand by default (CR 702.185a)" do
    plain = culler.merge("name" => "Spec Hand Culler", "abilities" => [{ "warp" => { "cost" => "{B}" } }])
    game = build_game(catalog_with(acolyte, plain)) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Swamp", count: 3
        graveyard "Spec Hand Culler"
        library "Forest", count: 10
      end
      player("bob") { library "Forest", count: 10 }
    end
    expect(game.legal_options.select { it[:type] == "cast" }).to be_empty
  end

  it "rejects a bad warp zone and a bad void value (CR 702.185a, 207.2c)" do
    bad = culler.merge("name" => "Spec Bad Culler", "abilities" => [{ "warp" => { "cost" => "{B}", "from" => ["library"] } }])
    expect { catalog_with(bad) }.to raise_error(Enjine::InvalidCardDefinition, /warp.from/)
    errors = []
    Enjine::Mechanics::Condition.build({ "void" => "yes" }, errors, "c")
    expect(errors.join).to include("c.void")
  end
end
