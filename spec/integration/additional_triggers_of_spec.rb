# frozen_string_literal: true

# "If a triggered ability of an Ally you control triggers, that ability triggers an additional time"
# (CR 603.2d): additional_triggers narrowed by the permanent whose ability triggers (`of`), with "another"
# and "of the chosen type" from the filter (CR 607.2d).
RSpec.describe "Additional triggers for abilities of matching permanents (CR 603.2d)" do
  let(:etb_life) { [{ "triggered" => { "when" => { "enters" => {} }, "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
  let(:captain) do
    { "name" => "Spec Banner Captain", "mana_cost" => "{2}{W}", "types" => ["creature"], "subtypes" => ["human"],
      "power" => 2, "toughness" => 2,
      "abilities" => [{ "additional_triggers" => { "of" => { "creature" => { "subtypes" => ["ally"] } } } }] }
  end
  let(:ally) do
    { "name" => "Spec Ally Scout", "mana_cost" => "{W}", "types" => ["creature"], "subtypes" => ["ally"],
      "power" => 1, "toughness" => 1, "abilities" => etb_life }
  end
  let(:loner) do
    { "name" => "Spec Lone Scout", "mana_cost" => "{W}", "types" => ["creature"], "subtypes" => ["scout"],
      "power" => 1, "toughness" => 1, "abilities" => etb_life }
  end
  let(:catalog) { catalog_with(captain, ally, loner) }

  def life_after_casting(card, captain: "Spec Banner Captain", bob_has: nil)
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: { W: 1 }) do
        battlefield captain
        hand card
        library "Forest", count: 3
      end
      player("bob") do
        battlefield bob_has if bob_has
        library "Forest", count: 3
      end
    end
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    until game.pending_decision.kind == "priority" && game.state.stack.empty? && game.state.pending_triggers.empty?
      options = game.legal_options
      game.submit(options.find { it[:type] == "pay_mana" } || options.find { it[:type] == "pass" } || options.first)
    end
    game.state.players[0].life
  end

  it "doubles the triggers of matching permanents you control only" do
    expect(life_after_casting("Spec Ally Scout")).to eq(22)
    expect(life_after_casting("Spec Lone Scout")).to eq(21)
  end

  it "validates and describes it" do
    expect(Enjine::CardDefinition.from_h(captain).abilities.first.to_s)
      .to start_with("triggered abilities of ").and end_with(" trigger an additional time")
    bad = captain.merge("abilities" => [{ "additional_triggers" => {} }])
    expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition, /needs cause or of/)
  end
end
