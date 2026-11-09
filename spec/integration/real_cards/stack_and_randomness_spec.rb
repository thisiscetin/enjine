# frozen_string_literal: true

# Real cards whose mechanics are cast triggers on a spell's targets, copying abilities, random choices, coin
# flips, proliferate and poison counters, written by hand in the card DSL
# (spec/fixtures/cards/real/stack_and_randomness.json).
RSpec.describe "Real cards: targets of cast spells, copied abilities, randomness and proliferate" do
  let(:pump) do
    { "name" => "Test Pump", "mana_cost" => "{G}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["creature"],
                                     "effects" => [{ "pump" => { "power" => 1, "toughness" => 1, "to" => { "target" => 0 } } }] } }] }
  end
  let(:elf) do
    { "name" => "Test Elf", "mana_cost" => "{G}", "types" => ["creature"], "subtypes" => ["elf"], "power" => 1, "toughness" => 1 }
  end
  let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.real("stack_and_randomness") + [pump, elf]) }

  def board(hand: [], battlefield: [], library: ["Island"] * 10, theirs: [], their_hand: [], mana: {}, step: :precombat_main,
            poison: 0)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana) do
        hand(*hand)
        library(*library)
        battlefield.each { |card, opts| battlefield card, **(opts || {}) }
      end
      player("bob", poison: poison) do
        hand(*their_hand)
        library "Swamp", count: 10
        theirs.each { |card, opts| battlefield card, **(opts || {}) }
      end
    end
  end

  def play(game, action, *answers)
    game.submit(action) if action
    until game.over? || ((decision = game.pending_decision).kind == "priority" && game.state.stack.empty?)
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { it[:type] == "pay_mana" } || raise("can't pay"))
      else
        answer = answers.shift or raise "no answer for #{decision.kind}: #{game.legal_options}"
        game.submit(answer.respond_to?(:call) ? answer.call(game) : answer)
      end
    end
    expect(answers).to be_empty
    game
  end

  def cast(game, card, *) = play(game, { type: "cast", object: obj_id(game, card, zone: :hand, player: "alice") }, *)
  def activate(game, card, *, ability: "printed:0") = play(game, { type: "activate", object: obj_id(game, card), ability: ability }, *)
  def target(ref) = { type: "target", target: ref }
  def first_of(type) = ->(g) { g.legal_options.find { it[:type] == type } }

  it "Colleen Wing gets a counter and scries when you cast a spell that targets your creature (CR 603.2, 115.1)" do
    game = board(hand: ["Test Pump"], battlefield: ["Colleen Wing, Street Samurai"], mana: { G: 1 })
    colleen = obj_id(game, "Colleen Wing, Street Samurai")
    cast(game, "Test Pump", target(colleen), first_of("top"))
    expect(game.state.object(colleen).counters["+1/+1"]).to eq(1)
  end

  it "Gnarlback Rhino draws only for a spell that targets it" do
    game = board(hand: ["Test Pump", "Test Pump"], battlefield: ["Gnarlback Rhino", "Test Elf"], mana: { G: 2 })
    cast(game, "Test Pump", target(obj_id(game, "Test Elf")))
    expect(ids_in(game, "alice", :hand).size).to eq(1)
    cast(game, "Test Pump", target(obj_id(game, "Gnarlback Rhino")))
    expect(ids_in(game, "alice", :hand).size).to eq(1)
  end

  it "Echo, Perceptive Prodigy copies a triggered ability from a creature source (CR 707.10)" do
    game = board(hand: ["Colleen Wing, Street Samurai", "Test Pump"], battlefield: ["Echo, Perceptive Prodigy"],
                 mana: { W: 2, G: 1, C: 1 })
    cast(game, "Colleen Wing, Street Samurai")
    colleen = obj_id(game, "Colleen Wing, Street Samurai")
    game.submit(type: "cast", object: obj_id(game, "Test Pump", zone: :hand, player: "alice"))
    game.submit(target(colleen))
    game.submit(type: "pay_mana", mana: "G")
    trigger = game.state.stack.first # Colleen's trigger, above the pump spell; alice holds priority
    expect(game.state.object(trigger).kind).to eq("ability")
    activate(game, "Echo, Perceptive Prodigy", target(trigger), first_of("top"), first_of("top"))
    expect(game.state.object(colleen).counters["+1/+1"]).to eq(2)
  end

  it "Curse-Marred Demon searches for a card, then discards one at random (CR 701.9b)" do
    game = board(hand: ["Curse-Marred Demon", "Forest", "Forest"], library: (["Island"] * 5) + ["Gnarlback Rhino"],
                 mana: { R: 2, C: 2 })
    cast(game, "Curse-Marred Demon", ->(g) { g.legal_options.find { g.state.objects[it[:object]]&.card == "gnarlback_rhino" } })
    expect(ids_in(game, "alice", :hand).size).to eq(2)
    expect(ids_in(game, "alice", :graveyard).size).to eq(1)
  end

  it "Fynn gives two poison counters for combat damage by a deathtouch creature (CR 122.1f)" do
    game = board(battlefield: ["Fynn, the Fangbearer"], step: :beginning_of_combat)
    pass_both(game)
    game.submit(type: "attack", object: obj_id(game, "Fynn, the Fangbearer"), target: "player:bob")
    game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
    skip_to(game, :postcombat_main)
    expect(game.state.players[1].poison).to eq(2)
  end

  it "High Perfect Morcant: three Elves tapped to proliferate (CR 701.34a)" do
    game = board(battlefield: ["High Perfect Morcant", "Test Elf", "Test Elf", "Test Elf"],
                 theirs: [["Test Elf", { counters: { "+1/+1" => 1 } }]],
                 poison: 1)
    elves = game.state.battlefield.select { game.state.object(it).card == "test_elf" && game.state.object(it).controller.zero? }
    their_elf = (game.state.battlefield - elves - [obj_id(game, "High Perfect Morcant")]).first
    activate(game, "High Perfect Morcant", first_of("cost"), first_of("cost"), first_of("cost"),
             ->(g) { g.legal_options.find { it[:object] == their_elf } },
             ->(g) { g.legal_options.find { it[:object] == "player:bob" } }, ability: "printed:1")
    expect(game.state.object(their_elf).counters["+1/+1"]).to eq(2)
    expect(game.state.players[1].poison).to eq(2)
  end

  it "The Gold Saucer flips a coin and creates a Treasure if the call wins (CR 705.2)" do
    game = board(battlefield: ["The Gold Saucer"], mana: { C: 2 })
    activate(game, "The Gold Saucer", { type: "call", call: "tails" }, ability: "printed:1")
    flip = game.history_for(:observer).flat_map { it["events"] }.find { it["type"] == "coin_flipped" }
    expect(flip["won"]).to eq(!flip["heads"])
    expect(game.state.battlefield.count { game.state.object(it).card.include?("treasure") }).to eq(flip["won"] ? 1 : 0)
  end
end
