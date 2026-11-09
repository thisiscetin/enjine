# frozen_string_literal: true

# CR 601.2h: the mana spent to cast a spell is recorded as it is paid, and the permanent the spell becomes
# remembers it (CR 400.7d). Converge (CR 207.2c) counts its colors; "if {W}{W} was spent" counts one type;
# "if four or more mana was spent to cast that spell" asks about the triggering spell (CR 603.4). A copy of a
# spell had no mana spent on it (CR 707.10). Prowess (CR 702.108a).
RSpec.describe "Mana spent to cast a spell (CR 601.2h, 207.2c) and prowess (CR 702.108a)" do
  def spent(**opts) = { "mana_spent" => opts.transform_keys(&:to_s) }

  let(:cards) do
    [
      { "name" => "Spec Prism Burst", "mana_cost" => "{2}{R}", "types" => ["instant"],
        "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                       "effects" => [{ "deal_damage" => { "amount" => spent(colors: true), "to" => { "target" => 0 } } }] } }] },
      { "name" => "Spec Dawn Herald", "mana_cost" => "{1}{W/G}{W/G}", "types" => ["creature"], "power" => 2, "toughness" => 2,
        "abilities" => [{ "triggered" => { "when" => { "enters" => {} },
                                           "if" => { "amount" => spent(color: "W"), "at_least" => 2 },
                                           "effects" => [{ "gain_life" => { "amount" => 3 } }] } }] },
      { "name" => "Spec Tally Golem", "mana_cost" => "{X}", "types" => ["artifact", "creature"], "power" => 0, "toughness" => 0,
        "abilities" => [{ "enters_with_counters" => { "counters" => { "+1/+1" => spent } } }] },
      { "name" => "Spec Grand Listener", "mana_cost" => "{1}{U}", "types" => ["creature"], "power" => 1, "toughness" => 1,
        "abilities" => [{ "triggered" => { "when" => { "cast" => { "controller" => "you", "spell" => "noncreature" } },
                                           "if" => { "amount" => spent(of: { "triggering" => "object" }), "at_least" => 4 },
                                           "effects" => [{ "draw" => { "amount" => 1 } }] } }] },
      { "name" => "Spec Mana Echo", "mana_cost" => "{U}", "types" => ["instant"],
        "abilities" => [{ "spell" => { "targets" => ["spell"],
                                       "effects" => [{ "gain_life" => { "amount" => spent(of: { "target" => 0 }) } }] } }] },
      { "name" => "Spec Big Draw", "mana_cost" => "{3}{U}", "types" => ["sorcery"],
        "abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 1 } }] } }] },
      { "name" => "Spec Swift Monk", "mana_cost" => "{R}", "types" => ["creature"], "keywords" => ["prowess"],
        "power" => 1, "toughness" => 2 },
      { "name" => "Spec Monk Lesson", "mana_cost" => "{W}", "types" => ["instant"],
        "abilities" => [{ "spell" => { "targets" => ["creature"],
                                       "effects" => [{ "grant" => { "keywords" => ["prowess"], "to" => { "target" => 0 } } }] } }] },
      { "name" => "Spec Twin Cast", "mana_cost" => "{U}", "types" => ["instant"],
        "abilities" => [{ "spell" => { "targets" => ["spell"],
                                       "effects" => [{ "copy_spell" => { "of" => { "target" => 0 } } }] } }] }
    ]
  end
  let(:catalog) { catalog_with(*cards) }

  def board(hand:, pool: {}, field: [], bob_hand: [], bob_pool: {})
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: pool) do
        hand(*hand)
        battlefield(*field) unless field.empty?
        library "Forest", count: 5
      end
      player("bob", mana_pool: bob_pool) do
        hand(*bob_hand) unless bob_hand.empty?
        library "Forest", count: 5
      end
    end
  end

  def cast(game, card, player: "alice", x: nil, target: nil, pay: [])
    game.submit(type: "cast", object: ids_in(game, player, :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) })
    game.submit(type: "x", value: x) if x
    game.submit(type: "target", target: target) if target
    pay.each { game.submit(type: "pay_mana", mana: it) }
  end

  def resolve_all(game)
    40.times do
      break if game.pending_decision.kind == "priority" && game.state.stack.empty?

      game.submit(game.pending_decision.kind == "priority" ? { type: "pass" } : game.legal_options.first)
    end
  end

  describe "converge: the number of colors spent (CR 207.2c)" do
    it "counts each color once and ignores colorless mana (CR 105.1)" do
      { %w[R U G] => 3, %w[R R R] => 1, %w[R C C] => 1, %w[R U U] => 2 }.each do |paid, colors|
        game = board(hand: ["Spec Prism Burst"], pool: paid.tally.transform_keys(&:to_sym))
        cast(game, "Spec Prism Burst", target: "player:bob", pay: paid)
        expect(game.state.object(game.state.stack.first).mana_spent.sort).to eq(paid.sort)
        resolve_all(game)
        expect(game.state.players[1].life).to eq(20 - colors), "paid #{paid.join}"
      end
    end
  end

  describe "the permanent remembers what was spent to cast it (CR 400.7d)" do
    it "triggers its enters ability only if {W}{W} was spent" do
      { %w[G W W] => 23, %w[W G G] => 20 }.each do |paid, life|
        game = board(hand: ["Spec Dawn Herald"], pool: paid.tally.transform_keys(&:to_sym))
        cast(game, "Spec Dawn Herald", pay: paid)
        resolve_all(game)
        herald = obj_id(game, "Spec Dawn Herald")
        expect(game.state.object(herald).mana_spent.sort).to eq(paid.sort)
        expect(game.state.players[0].life).to eq(life), "paid #{paid.join}"
      end
    end

    it "enters with counters equal to the amount spent, and a snapshot keeps it" do
      game = board(hand: ["Spec Tally Golem"], pool: { C: 3 })
      cast(game, "Spec Tally Golem", x: 3, pay: %w[C C C])
      resolve_all(game)
      golem = game.state.object(obj_id(game, "Spec Tally Golem"))
      expect(golem.counters).to eq("+1/+1" => 3)
      copy = Enjine::Game.import(game.export, catalog: catalog)
      expect(copy.state.object(golem.id).mana_spent).to eq(%w[C C C])
    end

    it "nothing was spent on a permanent that wasn't cast" do
      game = board(hand: [], field: ["Spec Tally Golem"])
      expect(game.state.object(obj_id(game, "Spec Tally Golem")).mana_spent).to be_nil
    end

    it "a trigger whose source has left remembers what was spent on it (CR 608.2h)" do
      game = board(hand: ["Spec Dawn Herald"], pool: { W: 3 })
      cast(game, "Spec Dawn Herald", pay: %w[W W W])
      game.submit(type: "pass")
      game.submit(type: "pass") # the creature resolves; its trigger waits on the stack
      trigger = game.state.object(game.state.stack.first)
      expect(trigger.memory["source_mana_spent"]).to eq(%w[W W W])
      game.state.battlefield.delete(trigger.source)
      game.state.objects.delete(trigger.source)
      resolve_all(game)
      expect(game.state.players[0].life).to eq(23)
    end
  end

  describe "the triggering spell's mana (CR 603.4)" do
    it "an intervening if counts the mana spent on the spell that was cast" do
      game = board(hand: ["Spec Big Draw"], pool: { U: 4 }, field: ["Spec Grand Listener"])
      cast(game, "Spec Big Draw", pay: %w[U U U U])
      expect(game.state.stack.size).to eq(2) # four mana: the listener triggers
      resolve_all(game)
      expect(ids_in(game, "alice", :hand).size).to eq(2)

      game = board(hand: ["Spec Prism Burst"], pool: { U: 2, R: 1 }, field: ["Spec Grand Listener"])
      cast(game, "Spec Prism Burst", target: "player:bob", pay: %w[R U U])
      expect(game.state.stack.size).to eq(1) # three mana: it doesn't trigger
    end

    it "reads a target spell's mana, and a copy has none (CR 707.10)" do
      game = board(hand: ["Spec Prism Burst", "Spec Mana Echo", "Spec Twin Cast"], pool: { R: 1, G: 1, W: 1, U: 2 })
      cast(game, "Spec Prism Burst", target: "player:bob", pay: %w[R G W])
      burst = game.state.stack.first
      cast(game, "Spec Twin Cast", target: burst, pay: %w[U])
      game.submit(type: "pass")
      game.submit(type: "pass") # Twin Cast resolves: a copy of the burst is on top
      copy = game.state.object(game.state.stack.first)
      expect(copy.mana_spent).to be_nil
      cast(game, "Spec Mana Echo", target: burst, pay: %w[U])
      game.submit(type: "pass")
      game.submit(type: "pass") # Mana Echo: three mana was spent on the burst
      expect(game.state.players[0].life).to eq(23)
      game.submit(type: "pass")
      game.submit(type: "pass") # the copy deals 0
      expect(game.state.players[1].life).to eq(20)
      resolve_all(game)
      expect(game.state.players[1].life).to eq(17)
    end
  end

  describe "prowess (CR 702.108a)" do
    it "gets +1/+1 until end of turn whenever its controller casts a noncreature spell" do
      game = board(hand: ["Spec Big Draw", "Spec Swift Monk"], pool: { U: 4, R: 1 }, field: ["Spec Swift Monk"])
      monk = obj_id(game, "Spec Swift Monk")
      cast(game, "Spec Big Draw", pay: %w[U U U U])
      expect(game.state.stack.size).to eq(2)
      resolve_all(game)
      expect(view_of(game, monk)["power"]).to eq(2)
      cast(game, "Spec Swift Monk", pay: %w[R]) # a creature spell: no trigger
      expect(game.state.stack.size).to eq(1)
      expect(view_of(game, monk)["toughness"]).to eq(3)
    end

    it "is granted with the keyword, and triggers from a granted instance" do
      game = board(hand: ["Spec Monk Lesson", "Spec Big Draw"], pool: { W: 1, U: 4 }, field: ["Grizzly Bears"])
      bear = obj_id(game, "Grizzly Bears")
      cast(game, "Spec Monk Lesson", target: bear, pay: %w[W])
      resolve_all(game)
      expect(view_of(game, bear)["power"]).to eq(2)
      cast(game, "Spec Big Draw", pay: %w[U U U U])
      resolve_all(game)
      expect(view_of(game, bear)["power"]).to eq(3)
    end
  end
end
