# frozen_string_literal: true

# What a triggered ability knows about the object its event was about, after that object left the battlefield:
# its source's new object (CR 400.7e), the triggering permanent as it last existed (CR 603.10a, 608.2h) and how its
# source was cast (CR 400.7d), plus the facts of untap events (CR 603.2).
RSpec.describe "Triggered abilities and last known information (CR 400.7e, 603.10a)" do
  let(:tortoise) do # "When this dies, exile it; you gain life equal to its +1/+1 counters."
    { "name" => "Spec Exiled Tortoise", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "abilities" => [{ "triggered" => { "when" => { "dies" => {} }, "effects" => [
        { "exile" => { "to" => "self" } },
        { "gain_life" => { "amount" => { "counters" => { "of" => "self", "kind" => "+1/+1" } } } },
        { "lose_life" => { "to" => "each_opponent", "amount" => { "power" => "self" } } }
      ] } }] }
  end
  let(:phoenix) do # "When this leaves the battlefield, return it to the battlefield."
    { "name" => "Spec Returning Phoenix", "mana_cost" => "{1}{R}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "abilities" => [{ "triggered" => { "when" => { "leaves_battlefield" => {} }, "effects" => [
        { "return_to_battlefield" => { "to" => "self" } }
      ] } }] }
  end
  let(:ooze) do # "Whenever a creature you control with a +1/+1 counter on it leaves, you gain life equal to them."
    { "name" => "Spec Counting Ooze", "mana_cost" => "{2}", "types" => ["artifact"],
      "abilities" => [{ "triggered" => {
        "when" => { "leaves_battlefield" => { "subject" => { "each" => { "creature" => { "counters" => "+1/+1" } },
                                                             "controller" => "you" } } },
        "effects" => [
          { "gain_life" => { "amount" => { "counters" => { "of" => { "triggering" => "object" }, "kind" => "+1/+1" } } } },
          { "lose_life" => { "to" => "each_opponent", "amount" => { "power" => { "triggering" => "object" } } } }
        ]
      } }] }
  end
  let(:token_watcher) do # "Whenever a creature dies, if it was a token, draw a card."
    { "name" => "Spec Token Watcher", "mana_cost" => "{2}", "types" => ["artifact"],
      "abilities" => [{ "triggered" => { "when" => { "dies" => { "subject" => { "each" => "creature" } } },
                                         "if" => { "triggering" => { "creature" => { "token" => true } } },
                                         "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
  end
  let(:mirror) do
    { "name" => "Spec Mirror Spell", "mana_cost" => "{U}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => ["creature"],
                                     "effects" => [{ "create_token_copy" => { "of" => { "target" => 0 } } }] } }] }
  end
  let(:cast_mourner) do # "When this dies, if you cast it, draw a card. If it was cast from your hand, gain 3 life."
    { "name" => "Spec Cast Mourner", "mana_cost" => "{G}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "dies" => {} }, "if" => { "was_cast" => true }, "effects" => [
        { "draw" => { "amount" => 1 } },
        { "gain_life" => { "amount" => 3, "if" => { "cast_from" => "hand" } } }
      ] } }] }
  end
  let(:orb) do # "Whenever a permanent becomes untapped, that permanent's controller loses 1 life."
    { "name" => "Spec Untap Orb", "mana_cost" => "{2}", "types" => ["artifact"],
      "abilities" => [{ "triggered" => { "when" => { "becomes_untapped" => { "subject" => { "each" => "permanent" } } },
                                         "effects" => [{ "lose_life" => {
                                           "amount" => 1, "to" => { "controller_of" => { "triggering" => "object" } }
                                         } }] } }] }
  end
  let(:catalog) { catalog_with(tortoise, phoenix, ooze, token_watcher, mirror, cast_mourner, orb) }

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, name) = game.state.players[game.names.index(name)].life
  def zone(game, name, zone) = (zone == :exile ? game.state.exile : ids_in(game, name, zone)).map { game.state.object(it).card }

  def board(alice: [], bob: [], hand: [], mana: {})
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: mana) do
        alice.each { |card, opts| battlefield card, **(opts || {}) }
        hand(*hand)
        library "Forest", count: 5
      end
      player("bob") do
        bob.each { |card, opts| battlefield card, **(opts || {}) }
        library "Forest", count: 5
      end
    end
  end

  # Answers every decision with the first acceptable option until priority returns with an empty stack.
  def settle(game, pick: ->(_) { true })
    while game.state.stack.any? || game.state.pending_triggers.any? || game.pending_decision.kind != "priority"
      decision = game.pending_decision
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { it[:type] == "pay_mana" } || raise("can't pay"))
      else game.submit(game.legal_options.find { pick.call(it) } || raise("no answer for #{decision.kind}"))
      end
    end
    game
  end

  def cast(game, card, pick: ->(_) { true })
    id = ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) }
    game.submit(type: "cast", object: id)
    settle(game, pick: pick)
  end

  def destroy(game, card)
    engine(game).move!(obj_id(game, card), :graveyard, reason: "destroy")
    settle(game)
  end

  describe "self in a leaves-the-battlefield trigger (CR 400.7e)" do
    it "finds the card in the graveyard it went to, while amounts still read it as it last existed (CR 608.2h)" do
      game = destroy(board(alice: [["Spec Exiled Tortoise", { counters: { "+1/+1" => 2 } }]]), "Spec Exiled Tortoise")
      expect(zone(game, "alice", :exile)).to eq(["spec_exiled_tortoise"])
      expect(zone(game, "alice", :graveyard)).to be_empty
      expect(life(game, "alice")).to eq(22) # two +1/+1 counters as it last existed
      expect(life(game, "bob")).to eq(16) # power 4 as it last existed, not the card's printed 2
    end

    it "the gem's Ancient Adamantoise exiles itself as it dies" do
      real = Enjine::Catalog.from_definitions(CardFixtures.real("combat_and_damage") + CardFixtures.cards)
      game = destroy(build_game(real) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") { battlefield "Ancient Adamantoise" }
        player("bob")
      end, "Ancient Adamantoise")
      expect(zone(game, "alice", :exile)).to eq(["ancient_adamantoise"])
      expect(game.state.battlefield.count { engine(game).chars(it).name == "Treasure" }).to eq(10)
    end

    it "returns it from the public zone it went to" do
      game = destroy(board(alice: ["Spec Returning Phoenix"]), "Spec Returning Phoenix")
      expect(game.state.battlefield.map { game.state.object(it).card }).to eq(["spec_returning_phoenix"])
    end

    it "can't find it once it has moved on, nor in a hidden zone (CR 400.7)" do
      game = board(alice: ["Spec Returning Phoenix"])
      engine(game).move!(obj_id(game, "Spec Returning Phoenix"), :graveyard, reason: "destroy")
      game.submit(type: "pass") until game.state.stack.any?
      engine(game).move!(ids_in(game, "alice", :graveyard).first, :exile, reason: "exile")
      settle(game)
      expect(zone(game, "alice", :exile)).to eq(["spec_returning_phoenix"])
      expect(game.state.battlefield).to be_empty

      game = board(alice: ["Spec Returning Phoenix"])
      engine(game).move!(obj_id(game, "Spec Returning Phoenix"), :hand, reason: "bounce")
      settle(game)
      expect(zone(game, "alice", :hand)).to eq(["spec_returning_phoenix"])
      expect(game.state.battlefield).to be_empty
    end
  end

  it "reads the triggering permanent's last known counters and power after it left (CR 603.10a, 608.2h)" do
    game = destroy(board(alice: ["Spec Counting Ooze", ["Grizzly Bears", { counters: { "+1/+1" => 3 } }]]), "Grizzly Bears")
    expect(life(game, "alice")).to eq(23)
    expect(life(game, "bob")).to eq(15) # power 5, not the printed 2
  end

  it "knows a dying token copy of a card is a token (CR 111.1, 603.10a)" do
    game = board(alice: ["Spec Token Watcher", "Grizzly Bears"], hand: ["Spec Mirror Spell"], mana: { U: 1 })
    cast(game, "Spec Mirror Spell")
    token = game.state.battlefield.find { game.state.object(it).memory["token"] }
    hand = ids_in(game, "alice", :hand).size
    engine(game).move!(token, :graveyard, reason: "destroy")
    settle(game)
    expect(ids_in(game, "alice", :hand).size).to eq(hand + 1)
    destroy(game, "Grizzly Bears") # the card itself isn't a token
    expect(ids_in(game, "alice", :hand).size).to eq(hand + 1)
  end

  it "remembers that a dying permanent was cast, and from where (CR 400.7d, 603.4)" do
    game = cast(board(hand: ["Spec Cast Mourner"], mana: { G: 1 }), "Spec Cast Mourner")
    hand = ids_in(game, "alice", :hand).size
    destroy(game, "Spec Cast Mourner")
    expect(ids_in(game, "alice", :hand).size).to eq(hand + 1)
    expect(life(game, "alice")).to eq(23)

    game = destroy(board(alice: ["Spec Cast Mourner"]), "Spec Cast Mourner") # put onto the battlefield, not cast
    expect(ids_in(game, "alice", :hand)).to be_empty
    expect(life(game, "alice")).to eq(20)
  end

  it "names the permanent that became untapped (CR 603.2)" do
    game = board(alice: ["Spec Untap Orb"], bob: [["Grizzly Bears", { tapped: true }]])
    engine(game).untap!(game.state.object(obj_id(game, "Grizzly Bears")))
    settle(game)
    expect(life(game, "bob")).to eq(19)
    expect(life(game, "alice")).to eq(20)
  end
end
