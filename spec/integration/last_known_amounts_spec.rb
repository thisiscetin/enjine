# frozen_string_literal: true

# Amounts of a permanent that left the battlefield use its last known information (CR 608.2h): a destroyed
# target, a permanent sacrificed by an earlier effect ({"result": n}) and one sacrificed to pay a cost
# ({"sacrificed": "power" | "mana_value"}, CR 601.2h).
RSpec.describe "Last known power and mana value of permanents that left (CR 608.2h)" do
  let(:last_rites) do
    { "name" => "Spec Last Rites", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [
        { "destroy" => { "to" => { "target" => 0 } } },
        { "gain_life" => { "amount" => { "mana_value" => { "target" => 0 } } } },
        { "lose_life" => { "to" => "each_opponent", "amount" => { "power" => { "target" => 0 } } } }
      ] } }] }
  end
  let(:grim_feast) do
    { "name" => "Spec Grim Feast", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [
        { "sacrifice_choice" => { "filter" => "creature" } },
        { "gain_life" => { "amount" => { "power" => { "result" => 0 } } } },
        { "lose_life" => { "to" => "each_opponent", "amount" => { "greatest_mana_value" => { "result" => 0 } } } }
      ] } }] }
  end
  let(:altar) do
    { "name" => "Spec Offering Altar", "mana_cost" => "{2}", "types" => ["artifact"],
      "abilities" => [
        { "activated" => { "cost" => [{ "sacrifice_permanent" => { "filter" => "artifact", "other" => true } }],
                           "effects" => [{ "gain_life" => { "amount" => { "sacrificed" => "mana_value" } } }] } },
        { "activated" => { "cost" => [{ "sacrifice_permanent" => { "filter" => "creature" } }],
                           "effects" => [{ "gain_life" => { "amount" => { "sacrificed" => "power" } } }] } }
      ] }
  end
  let(:graveyard_count) do
    { "name" => "Spec Count the Dead", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [
        { "destroy" => { "to" => { "target" => 0 } } },
        { "gain_life" => { "amount" => { "greatest_power" => { "each" => { "graveyard_card" => {} }, "controller" => "any" } } } }
      ] } }] }
  end
  let(:token_feast) do
    { "name" => "Spec Token Feast", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [
        { "create_token" => { "token" => { "name" => "Spec Brute", "types" => ["creature"], "power" => 3, "toughness" => 3 } } },
        { "add_counters" => { "counter" => "+1/+1", "amount" => 2, "to" => { "result" => 0 } } },
        { "sacrifice" => { "to" => { "result" => 0 } } },
        { "gain_life" => { "amount" => { "power" => { "result" => 2 } } } }
      ] } }] }
  end
  let(:catalog) { catalog_with(last_rites, grim_feast, altar, graveyard_count, token_feast) }

  def life(game, name) = game.state.players[game.names.index(name)].life

  def board(alice: [], bob: [], hand: [], mana: {})
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: mana) do
        alice.each { |card, opts| battlefield card, **(opts || {}) }
        hand(*hand)
        library "Forest", count: 3
      end
      player("bob") do
        bob.each { |card, opts| battlefield card, **(opts || {}) }
        library "Forest", count: 3
      end
    end
  end

  # Submits the action, then answers every other decision with the first option that `pick` accepts.
  def play(game, action, pick: ->(_) { true })
    game.submit(action)
    until (decision = game.pending_decision).kind == "priority" && game.state.stack.empty?
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { it[:type] == "pay_mana" } || raise("can't pay"))
      else game.submit(game.legal_options.find { pick.call(it) } || raise("no answer for #{decision.kind}"))
      end
    end
    game
  end

  def cast(game, card, **)
    id = ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) }
    play(game, { type: "cast", object: id }, **)
  end

  it "reads a destroyed target's mana value and power, counters included, as it last existed" do
    game = board(bob: [["Grizzly Bears", { counters: { "+1/+1" => 2 } }]], hand: ["Spec Last Rites"], mana: { B: 1 })
    cast(game, "Spec Last Rites")
    expect(game.state.players[1].graveyard.size).to eq(1)
    expect(life(game, "alice")).to eq(22) # mana value 2
    expect(life(game, "bob")).to eq(16) # power 4
  end

  it "reads a permanent sacrificed by an earlier effect as it last existed, not as the card in the graveyard" do
    game = board(alice: [["Grizzly Bears", { counters: { "+1/+1" => 3 } }]], hand: ["Spec Grim Feast"], mana: { B: 1 })
    cast(game, "Spec Grim Feast")
    expect(life(game, "alice")).to eq(25) # power 5, not the printed 2
    expect(life(game, "bob")).to eq(18)
  end

  it "reads a card in a graveyard looked at for itself as the card, not as the permanent it was" do
    game = board(bob: [["Grizzly Bears", { counters: { "+1/+1" => 2 } }]], hand: ["Spec Count the Dead"], mana: { B: 1 })
    cast(game, "Spec Count the Dead")
    expect(life(game, "alice")).to eq(22) # the Bears card's printed power, not the 4 it had
  end

  it "reads a sacrificed token as it last existed (CR 111.7, 608.2h)" do
    game = cast(board(hand: ["Spec Token Feast"], mana: { B: 1 }), "Spec Token Feast")
    expect(game.state.battlefield).to be_empty
    expect(life(game, "alice")).to eq(25) # 3/3 with two +1/+1 counters
  end

  it "reads a permanent sacrificed to pay a cost (CR 601.2h)" do
    game = board(alice: [["Spec Offering Altar"], ["Arc Lantern"], ["Hill Giant", { counters: { "+1/+1" => 1 } }]])
    altar = obj_id(game, "Spec Offering Altar")
    play(game, { type: "activate", object: altar, ability: "printed:0" })
    expect(life(game, "alice")).to eq(22) # Arc Lantern: mana value 2
    play(game, { type: "activate", object: altar, ability: "printed:1" })
    expect(life(game, "alice")).to eq(22 + 4) # Hill Giant with a +1/+1 counter
  end

  it "is 0 when the ability wasn't paid with a sacrifice" do
    errors = []
    amount = Enjine::Mechanics::Amount.build({ "sacrificed" => "power" }, errors, "x", targets_count: 0)
    expect(errors).to be_empty
    expect(amount.to_s).to eq("the sacrificed permanent's power")
    expect(Enjine::Mechanics::Amount.build({ "sacrificed" => "color" }, errors, "x", targets_count: 0)).to be_a(Enjine::Mechanics::Amount::Fixed)
    expect(errors.last).to include("x.sacrificed: must be power, toughness or mana_value")
  end
end
