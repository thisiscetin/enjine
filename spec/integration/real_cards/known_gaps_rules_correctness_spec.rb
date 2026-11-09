# frozen_string_literal: true

# Real cards for rules-correctness details (spec/fixtures/cards/real/known_gaps_rules_correctness.json, plus real cards
# of other families they interact with): new targets triggering ward and "becomes the target" (CR 115.7, 702.21a),
# keeping the division of a divided spell (CR 115.7f, 601.2d), creatures put onto the battlefield attacking a
# planeswalker (CR 508.4), the order of damage replacement and prevention effects (CR 616.1), prevention follow-ups
# for damage that can't be prevented (CR 615.12), sources of your choice (CR 609.7a-b) and copying a triggered
# ability that already left the stack (CR 707.10). Test cards stand in for the spells they interact with.
RSpec.describe "Real cards: rules-correctness details" do
  let(:test_cards) do
    [{ "name" => "Test Shock", "mana_cost" => "{R}", "types" => ["instant"],
       "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                      "effects" => [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }] } }] },
     { "name" => "Test Watcher", "mana_cost" => "{U}", "types" => ["creature"], "power" => 1, "toughness" => 1,
       "abilities" => [{ "triggered" => { "when" => { "becomes_target" => {} },
                                          "effects" => [{ "draw" => { "amount" => 1 } }] } }] },
     { "name" => "Test Trinket", "mana_cost" => "{1}", "types" => ["artifact"] },
     { "name" => "Test Raw Shock", "mana_cost" => "{R}", "types" => ["instant"],
       "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                      "effects" => ["damage_unpreventable",
                                                    { "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }] } }] },
     { "name" => "Test Bear", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 2, "toughness" => 2 }]
  end
  let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.real_cards + test_cards) }

  def board(hand: [], battlefield: [], theirs: [], their_hand: [], mana: {}, their_mana: {}, step: :precombat_main,
            life: 20, their_life: 20, active: "alice")
    build_game(catalog) do
      turn 3, active: active, step: step
      player("alice", mana_pool: mana, life: life) do
        hand(*hand)
        library "Island", count: 10
        battlefield.each { |card, opts| battlefield card, **(opts || {}) }
      end
      player("bob", mana_pool: their_mana, life: their_life) do
        hand(*their_hand)
        library "Swamp", count: 10
        theirs.each { |card, opts| battlefield card, **(opts || {}) }
      end
    end
  end

  # Submits `action`, answers further decisions with `answers` (options or blocks taking the game), pays from the
  # pool and passes until the stack is empty.
  def play(game, action, *answers)
    game.submit(action) if action
    until game.over? || ((decision = game.pending_decision).kind == "priority" && game.state.stack.empty?)
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost"
        game.submit(game.legal_options.find { %w[pay_mana activate_mana].include?(it[:type]) } || raise("can't pay"))
      else
        warn [decision.kind, decision.to_h["prompt"], game.legal_options].inspect if ENV["DBG"]
        answer = answers.shift or raise "no answer for #{decision.kind}: #{game.legal_options}"
        game.submit(answer.respond_to?(:call) ? answer.call(game) : answer)
      end
    end
    expect(answers).to be_empty
    game
  end

  def cast(game, card, *) = play(game, { type: "cast", object: obj_id(game, card, zone: :hand, player: "alice") }, *)
  def target(ref) = { type: "target", target: ref }
  def life(game, name) = game.state.players[game.names.index(name)].life
  def hand_size(game, name) = ids_in(game, name, :hand).size
  def pay = ->(game) { game.legal_options.find { it[:type] != "decline" } }
  def decline = { type: "decline" }

  # The permanent named `name` that `player` controls.
  def permanent(game, name, player = "bob")
    index = game.names.index(player)
    game.state.battlefield.find { (o = game.state.object(it)).controller == index && o.card == Enjine::CardDefinition.slug(name) }
  end

  def mine(name) = ->(game) { target(permanent(game, name, "alice")) }
  def theirs(name) = ->(game) { target(permanent(game, name)) }

  describe "Speedball, New Warrior: new targets are targeted (CR 115.7d, 702.21a, 603.2)" do
    it "triggers ward of the new target, which counters the spell unless its controller pays" do
      game = board(hand: ["Test Shock"], mana: { R: 1 }, theirs: ["Speedball, New Warrior", "Mica, Reader of Ruins"])
      cast(game, "Test Shock", theirs("Speedball, New Warrior"), theirs("Mica, Reader of Ruins"), decline)
      expect(game.state.object(obj_id(game, "Mica, Reader of Ruins")).damage).to eq(0) # countered by ward
      expect(ids_in(game, "alice", :graveyard).map { game.state.object(it).card }).to include("test_shock")
    end

    it "makes the new target's controller pay for ward with the spell's controller paying" do
      game = board(hand: ["Test Shock"], mana: { R: 1 }, theirs: ["Speedball, New Warrior", "Mica, Reader of Ruins"])
      cast(game, "Test Shock", theirs("Speedball, New Warrior"), theirs("Mica, Reader of Ruins"),
           pay)
      expect(life(game, "alice")).to eq(17)
      expect(game.state.object(obj_id(game, "Mica, Reader of Ruins")).damage).to eq(2)
    end

    it "triggers \"whenever this becomes the target\" of the new target" do
      game = board(hand: ["Test Shock"], mana: { R: 1 }, theirs: ["Speedball, New Warrior", "Test Watcher"])
      cast(game, "Test Shock", theirs("Speedball, New Warrior"), theirs("Test Watcher"))
      expect(hand_size(game, "bob")).to eq(1)
    end

    it "keeps the division of a divided spell with the new targets (CR 115.7f, 601.2d)" do
      game = board(hand: ["Twin Bolt"], mana: { R: 2 }, theirs: ["Speedball, New Warrior"])
      cast(game, "Twin Bolt", { type: "count", count: 2 }, theirs("Speedball, New Warrior"), target("player:bob"),
           lambda { |g|
             expect(g.legal_options.map { it[:target] }).not_to include("player:bob") # each target gets at least one
             target("player:alice")
           },
           target("player:bob"))
      expect([life(game, "alice"), life(game, "bob")]).to eq([19, 19])
    end
  end

  describe "Mica, Reader of Ruins: a copy's targets are targeted (CR 707.10, 702.21a)" do
    it "triggers ward of a permanent the copy targets" do
      game = board(hand: ["Test Shock"], mana: { R: 1 }, battlefield: ["Mica, Reader of Ruins", "Test Trinket"],
                   theirs: ["Mica, Reader of Ruins"])
      cast(game, "Test Shock", target("player:bob"), pay, pay, theirs("Mica, Reader of Ruins"), decline)
      expect(game.state.object(permanent(game, "Mica, Reader of Ruins")).damage).to eq(0)
      expect(life(game, "bob")).to eq(18)
    end
  end

  describe "Kavaron Harrier: a token put onto the battlefield attacking (CR 508.4)" do
    def attack_with_harrier(game)
      pass_both(game)
      game.submit(type: "attack", object: permanent(game, "Kavaron Harrier", "alice"), target: "player:bob")
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
    end

    it "lets its controller choose a planeswalker the defending player controls" do
      game = board(battlefield: ["Kavaron Harrier", "Mountain", "Mountain"],
                   theirs: [["Ajani, Caller of the Pride", { loyalty: 4 }]], step: :beginning_of_combat)
      attack_with_harrier(game)
      play(game, nil, pay, lambda { |g|
        expect(g.legal_options).to contain_exactly({ type: "attack", target: "player:bob" },
                                                   { type: "attack", target: permanent(g, "Ajani, Caller of the Pride") })
        theirs("Ajani, Caller of the Pride").call(g).merge(type: "attack")
      })
      robot = game.state.attackers.keys - [permanent(game, "Kavaron Harrier", "alice")]
      expect(game.state.attackers[robot.first]["target"]).to eq(permanent(game, "Ajani, Caller of the Pride"))
    end

    it "attacks the defending player without asking when they control no planeswalker" do
      game = board(battlefield: ["Kavaron Harrier", "Mountain", "Mountain"], step: :beginning_of_combat)
      attack_with_harrier(game)
      play(game, nil, pay)
      expect(game.state.attackers.values.map { it["target"] }).to eq(["player:bob", "player:bob"])
    end
  end

  describe "New Way Forward against an opponent's spell" do
    # Bob casts `spell` at alice; alice answers with New Way Forward choosing that spell as the source.
    def bob_casts_at_alice(game, spell)
      game.submit(type: "cast", object: obj_id(game, spell, zone: :hand, player: "bob"))
      game.submit(target("player:alice"))
      game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
      game.submit(type: "pass")
      shock = game.state.stack.first
      game.submit(type: "cast", object: obj_id(game, "New Way Forward", zone: :hand, player: "alice"))
      game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
      game.submit(type: "pass") while game.pending_decision.kind == "priority"
      game.submit(type: "source", object: shock)
    end

    it "lets alice double the damage before preventing it, with Twinflame Tyrant's doubling (CR 616.1)" do
      game = board(hand: ["New Way Forward"], mana: { U: 1, R: 1, W: 1, C: 2 }, their_hand: ["Test Shock"],
                   their_mana: { R: 1 }, theirs: ["Twinflame Tyrant"], active: "bob")
      bob_casts_at_alice(game, "Test Shock")
      game.submit(type: "pass") until game.pending_decision.kind != "priority" # New Way Forward resolved; the Shock resolves
      expect(game.pending_decision.kind).to eq("damage_order")
      orders = game.legal_options
      expect(orders.size).to eq(2)
      play(game, orders.find { it[:steps].first.start_with?("Twinflame") })
      expect(life(game, "alice")).to eq(20)
      expect(life(game, "bob")).to eq(16) # the doubled 4, dealt back
      expect(hand_size(game, "alice")).to eq(4)
    end

    it "prevents nothing and doesn't trigger when the damage can't be prevented (CR 615.12)" do
      game = board(hand: ["New Way Forward"], mana: { U: 1, R: 1, W: 1, C: 2 }, their_hand: ["Test Raw Shock"],
                   their_mana: { R: 1 }, active: "bob")
      bob_casts_at_alice(game, "Test Raw Shock")
      game.submit(type: "pass") while game.state.stack.any? && game.pending_decision.kind == "priority"
      expect(life(game, "alice")).to eq(18)
      expect([life(game, "bob"), hand_size(game, "alice")]).to eq([20, 0])
      expect(game.state.effects.count { it["kind"] == "prevent_damage" }).to eq(1) # the shield isn't used up
    end
  end

  describe "Firebender Ascension: copying an ability that already resolved (CR 707.10, 608.2h)" do
    it "copies the attack trigger as it last existed on the stack" do
      game = board(battlefield: [["Firebender Ascension", { counters: { "quest" => 3 } }], "Jeong Jeong, the Deserter"],
                   step: :beginning_of_combat)
      jeong = permanent(game, "Jeong Jeong, the Deserter", "alice")
      pass_both(game)
      game.submit(type: "attack", object: jeong, target: "player:bob")
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
      ascension = game.state.pending_triggers.find { it["card"] == "firebender_ascension" }
      game.submit(type: "trigger", trigger: ascension["id"]) # it goes on the stack first: the firebending resolves first
      play(game, nil, { type: "yes" })
      mana = game.history_for(:observer).flat_map { it["events"] }.count { it["type"] == "mana_added" && it["mana"] == "{R}" }
      expect(mana).to eq(2) # the original and the copy of it
    end
  end
end
