# frozen_string_literal: true

# Committing a crime (CR 700.13). Invented test cards only.
RSpec.describe "Committing a crime (CR 700.13)" do
  let(:fence) do
    { "name" => "Spec Fence", "mana_cost" => "{1}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "commits_crime" => {} },
                                         "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
  end
  let(:lawman) do
    { "name" => "Spec Lawman", "mana_cost" => "{1}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "commits_crime" => { "controller" => "opponent" } },
                                         "effects" => [{ "gain_life" => { "amount" => 2 } }] } }] }
  end
  let(:zapper) do # an activated ability that targets any target
    { "name" => "Spec Zapper", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "activated" => { "cost" => ["tap"], "targets" => ["any_target"],
                                         "effects" => [{ "deal_damage" => { "amount" => 1, "to" => { "target" => 0 } } }] } }] }
  end
  let(:grave_robber) do # a triggered ability that targets a card in a graveyard
    { "name" => "Spec Grave Robber", "mana_cost" => "{B}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} },
                                         "targets" => [{ "graveyard_card" => { "controller" => "opponent" } }],
                                         "effects" => [{ "exile" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:double_shot) do # one spell with two qualifying targets is one crime
    { "name" => "Spec Double Shot", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => %w[any_target any_target],
                                     "effects" => [{ "deal_damage" => { "amount" => 1, "to" => { "target" => 0 } } },
                                                   { "deal_damage" => { "amount" => 1, "to" => { "target" => 1 } } }] } }] }
  end
  let(:catalog) { catalog_with(fence, lawman, zapper, grave_robber, double_shot) }

  def pay_all(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, name) = game.view_for(:observer)["players"].find { it["name"] == name }["life"]

  def board(alice_hand: [], alice_field: [], bob_field: [], bob_grave: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        alice_hand.each { hand it }
        battlefield "Spec Fence", "Mountain", "Swamp", *alice_field
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Spec Lawman", *bob_field
        bob_grave.each { graveyard it }
        library "Forest", count: 5
      end
    end
  end

  def resolve_all(game)
    30.times do
      break if game.state.stack.empty? && game.state.pending_triggers.empty?

      kind = game.pending_decision.kind
      game.submit(kind == "priority" ? { type: "pass" } : game.legal_options.first)
    end
  end

  def activate_zapper(game, target)
    zapper = obj_id(game, "Spec Zapper")
    game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == zapper })
    game.submit(type: "target", target: target)
  end

  it "activating an ability that targets an opponent is a crime: 'whenever you commit a crime' and an opponent's watcher trigger" do
    game = board(alice_field: ["Spec Zapper"])
    activate_zapper(game, "player:bob")
    expect(engine(game).turn_log(0)["crimes"]).to eq(1)
    resolve_all(game)
    expect(life(game, "alice")).to eq(21)
    expect(life(game, "bob")).to eq(21) # 20 - 1 damage + 2 from Spec Lawman
  end

  it "targeting your own permanent or yourself is no crime" do
    game = board(alice_field: ["Spec Zapper"])
    activate_zapper(game, obj_id(game, "Spec Fence"))
    resolve_all(game)
    expect(engine(game).turn_log(0)["crimes"]).to be_nil
    expect(life(game, "alice")).to eq(20)
  end

  it "targeting a permanent an opponent controls is a crime" do
    game = board(alice_field: ["Spec Zapper"])
    activate_zapper(game, obj_id(game, "Spec Lawman"))
    expect(engine(game).turn_log(0)["crimes"]).to eq(1)
  end

  it "a triggered ability put on the stack targeting a card in an opponent's graveyard is a crime" do
    game = board(alice_hand: ["Spec Grave Robber"], bob_grave: ["Forest"])
    robber = ids_in(game, "alice", :hand).first
    game.submit(type: "cast", object: robber)
    pay_all(game)
    pass_both(game) # the Grave Robber resolves; its enters trigger asks for a target
    target = ids_in(game, "bob", :graveyard).first
    game.submit(type: "target", target: target)
    expect(engine(game).turn_log(0)["crimes"]).to eq(1)
    resolve_all(game)
    expect(life(game, "alice")).to eq(21)
  end

  it "one spell with several qualifying targets is one crime, counted by crimes_this_turn" do
    game = board(alice_hand: ["Spec Double Shot"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: "player:bob")
    game.submit(type: "target", target: obj_id(game, "Spec Lawman"))
    pay_all(game)
    expect(engine(game).turn_log(0)["crimes"]).to eq(1)
    amount = Enjine::Mechanics::Amount.build({ "crimes_this_turn" => "you" }, [], "a", targets_count: 0)
    ctx = Enjine::Mechanics::EffectContext.new(0, obj_id(game, "Spec Fence"), nil, [])
    expect(amount.value(engine(game), ctx)).to eq(1)
    resolve_all(game)
    expect(life(game, "alice")).to eq(21) # one trigger
  end

  it "a cancelled cast commits no crime" do
    game = board(alice_hand: ["Spec Double Shot"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: "player:bob")
    game.submit(type: "cancel")
    expect(engine(game).turn_log(0)["crimes"]).to be_nil
  end
end
