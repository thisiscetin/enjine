# frozen_string_literal: true

# Split second (CR 702.61a-c): while a spell with it is on the stack, no spells and no non-mana activated abilities.
RSpec.describe "Split second" do
  let(:shock) do
    { "name" => "Spec Sudden Jolt", "mana_cost" => "{R}", "types" => ["instant"], "keywords" => ["split_second"],
      "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                     "effects" => [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }] } }] }
  end
  let(:plain) do
    { "name" => "Spec Plain Jolt", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                     "effects" => [{ "deal_damage" => { "amount" => 1, "to" => { "target" => 0 } } }] } }] }
  end
  let(:pinger) do
    { "name" => "Spec Pinger", "mana_cost" => "{1}{R}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{1}" }],
                                         "effects" => [{ "gain_life" => { "amount" => 1 } }] } },
                      { "triggered" => { "when" => { "cast" => { "controller" => "any" } },
                                         "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
  end
  let(:tyrant) do
    { "name" => "Spec Tyrant", "mana_cost" => "{3}{R}", "types" => ["creature"], "power" => 4, "toughness" => 4,
      "abilities" => [{ "spell_keywords" => { "spells" => { "spell" => { "any_of" => %w[instant sorcery] } },
                                              "keywords" => ["split_second"] } }] }
  end
  let(:catalog) { catalog_with(shock, plain, pinger, tyrant) }

  def board(alice_extra: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Mountain", count: 2
        alice_extra.each { battlefield it }
        hand "Spec Sudden Jolt", "Spec Plain Jolt"
        library "Forest", count: 10
      end
      player("bob") do
        battlefield "Mountain", count: 2
        battlefield "Spec Pinger"
        hand "Spec Plain Jolt"
        library "Forest", count: 10
      end
    end
  end

  def cast!(game, card)
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: "alice"))
    while game.pending_decision.kind == "choose_target"
      game.submit(game.legal_options.find { it[:type] == "target" && it[:target].start_with?("player:") })
    end
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  # Puts pending triggers on the stack and passes to bob.
  def to_bob(game)
    20.times do
      break if game.pending_decision.kind == "priority" && game.pending_decision.player == "bob"

      game.submit(game.legal_options.find { it[:type] == "pass" } || game.legal_options.first)
    end
  end

  it "the opponent can't cast spells or activate non-mana abilities, only mana abilities (CR 702.61a, 702.61b)" do
    game = board
    cast!(game, "spec_sudden_jolt")
    to_bob(game)
    types = option_types(game)
    expect(types).not_to include("cast", "activate")
    expect(types).to include("activate_mana", "pass")
  end

  it "triggered abilities still trigger and go on the stack above it (CR 702.61c)" do
    game = board
    cast!(game, "spec_sudden_jolt")
    expect(game.state.pending_triggers.size + game.state.stack.size).to eq(2)
    to_bob(game)
    top = game.state.object(game.state.stack.first)
    expect(top.ability?).to be(true)
  end

  it "without split second the opponent may respond (CR 702.61b)" do
    game = board
    cast!(game, "spec_plain_jolt")
    to_bob(game)
    expect(option_types(game)).to include("cast", "activate")
  end

  it "a static can give instant and sorcery spells you control split second (CR 702.61a, 604.1, 611.3a)" do
    game = board(alice_extra: ["Spec Tyrant"])
    cast!(game, "spec_plain_jolt")
    to_bob(game)
    expect(option_types(game)).not_to include("cast", "activate")
  end

  it "once it has resolved, spells can be cast again (CR 702.61a)" do
    game = board
    cast!(game, "spec_sudden_jolt")
    30.times do
      break if game.state.stack.empty? && game.pending_decision.kind == "priority"

      game.submit(game.legal_options.find { it[:type] == "pass" } || game.legal_options.first)
    end
    expect(option_types(game)).to include("cast")
  end
end
