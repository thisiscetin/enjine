# frozen_string_literal: true

# Cast triggers filtered on the spell's targets (CR 603.2, 115.1) and on where it was cast from (CR 601.2a),
# copying activated and triggered abilities (CR 707.10), random choices (CR 701.9b), coin flips (CR 705),
# proliferate (CR 701.34) and poison counters on players (CR 122.1f). The cards are invented fixtures
# (spec/fixtures/cards).
RSpec.describe "Stack, cast filters and randomness" do
  # Alice's turn 3, precombat main. Permanents are names or [name, options].
  def board(hand: [], battlefield: [], graveyard: [], theirs: [], their_hand: [], mana: {}, poison: 0, seed: 1,
            catalog: core_catalog)
    build_game(catalog) do
      seed seed
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: mana) do
        hand(*hand)
        graveyard(*graveyard)
        library "Island", count: 10
        battlefield.each { |card, opts| battlefield card, **(opts || {}) }
      end
      player("bob", poison: poison) do
        hand(*their_hand)
        library "Swamp", count: 10
        theirs.each { |card, opts| battlefield card, **(opts || {}) }
      end
    end
  end

  # Submits `action`, answers further decisions with `answers` (an option or a block taking the game), pays
  # costs from the pool and passes until the stack is empty (`resolve: false`: stops at the first priority).
  def play(game, action, *answers, resolve: true)
    game.submit(action) if action
    until game.over? || ((decision = game.pending_decision).kind == "priority" && (!resolve || game.state.stack.empty?))
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

  def cast(game, card, *, **) = play(game, { type: "cast", object: obj_id(game, card, zone: :hand, player: "alice") }, *, **)
  def target(ref) = { type: "target", target: ref }
  def events(game) = game.history_for(:observer).flat_map { it["events"] }
  def hand_size(game, player) = ids_in(game, player, :hand).size

  describe "cast triggers on the spell's targets (CR 603.2, 115.1)" do
    it "triggers on a spell that targets a creature you control, not one that targets another" do
      game = board(hand: ["Giant Growth", "Giant Growth"], battlefield: ["Spellguard Duelist"], theirs: ["Grizzly Bears"],
                   mana: { G: 2 })
      duelist = obj_id(game, "Spellguard Duelist")
      cast(game, "Giant Growth", target(obj_id(game, "Grizzly Bears")))
      expect(game.state.object(duelist).counters["+1/+1"].to_i).to eq(0)
      cast(game, "Giant Growth", target(duelist))
      expect(game.state.object(duelist).counters["+1/+1"]).to eq(1)
    end

    it "\"targets this creature\": only a spell targeting the source itself" do
      game = board(hand: ["Giant Growth", "Giant Growth"], battlefield: ["Lodestar Rhino", "Grizzly Bears"], mana: { G: 2 })
      cast(game, "Giant Growth", target(obj_id(game, "Grizzly Bears")))
      expect(hand_size(game, "alice")).to eq(1)
      cast(game, "Giant Growth", target(obj_id(game, "Lodestar Rhino")))
      expect(hand_size(game, "alice")).to eq(1) # cast one, drew one
    end
  end

  describe "spells cast from anywhere other than your hand (CR 601.2a)" do
    it "reduce their cost and trigger, while spells from the hand don't" do
      lesson = { "name" => "Echo Lesson", "mana_cost" => "{2}{U}", "types" => ["sorcery"],
                 "abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 1 } }] } },
                                 { "flashback" => { "cost" => [{ "mana" => "{2}{U}" }] } }] }
      game = board(hand: ["Echo Lesson"], battlefield: ["Afterimage Adept", "Graverunner Savant"],
                   mana: { U: 4, C: 1 }, catalog: catalog_with(lesson))
      cast(game, "Echo Lesson") # {2}{U} from the hand: full cost, no trigger
      expect(game.state.players[1].life).to eq(20)
      expect(game.state.players[0].mana_pool.values.sum).to eq(2)
      flashback = game.legal_options.find { it[:type] == "cast" && ids_in(game, "alice", :graveyard).include?(it[:object]) }
      play(game, flashback) # {1}{U}: one less from the graveyard
      expect(game.state.players[0].mana_pool.values.sum).to eq(0)
      expect(game.state.players[1].life).to eq(19)
    end
  end

  describe "copying abilities on the stack (CR 707.10)" do
    it "copies a triggered ability you control; the copy has the same source and resolves too" do
      game = board(hand: ["Tower Scholar"], battlefield: ["Echo Tactician"], mana: { U: 2, C: 1 })
      cast(game, "Tower Scholar", resolve: false) # the Scholar resolves, its draw trigger waits on the stack
      game.submit(type: "pass")
      game.submit(type: "pass")
      trigger = game.state.stack.first
      expect(game.state.object(trigger).kind).to eq("ability")
      play(game, { type: "activate", object: obj_id(game, "Echo Tactician"), ability: "printed:0" }, target(trigger))
      expect(hand_size(game, "alice")).to eq(2)
    end

    it "a copy of a targeted trigger may get a new target; both resolve (CR 707.10c)" do
      herald = { "name" => "Spark Herald", "mana_cost" => "{R}", "types" => ["creature"], "power" => 1, "toughness" => 1,
                 "abilities" => [{ "triggered" => { "when" => { "enters" => {} }, "targets" => ["creature"],
                                                    "effects" => [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }] } }] }
      game = board(hand: ["Spark Herald"], battlefield: ["Echo Tactician"], theirs: ["Grizzly Bears", "Grizzly Bears"],
                   mana: { R: 1, C: 1 }, catalog: catalog_with(herald))
      first, second = game.state.battlefield.select { game.state.object(it).card == "grizzly_bears" }
      cast(game, "Spark Herald", resolve: false)
      game.submit(type: "pass")
      game.submit(type: "pass")
      game.submit(target(first)) # the enters trigger's target (CR 603.3d)
      trigger = game.state.stack.first
      expect(game.state.object(trigger).targets).to eq([first])
      play(game, { type: "activate", object: obj_id(game, "Echo Tactician"), ability: "printed:0" }, target(trigger),
           ->(g) { g.legal_options.find { it[:target] == second } || raise("no new target: #{g.legal_options}") })
      expect(game.state.players[1].graveyard.size).to eq(2)
    end

    it "can't target an opponent's ability (`controller: you`)" do
      game = board(battlefield: ["Echo Tactician"], their_hand: ["Tower Scholar"], mana: { C: 1 })
      expect(game.legal_options.map { it[:type] }).not_to include("activate")
    end
  end

  describe "random choices (CR 701.9b)" do
    it "discards a card at random with no decision, the same one on a replay of the seed" do
      picks = 2.times.map do
        game = board(hand: ["Rift Toad"], their_hand: %w[Forest Island Swamp], mana: { B: 1, C: 1 }, seed: 7)
        cast(game, "Rift Toad")
        expect(hand_size(game, "bob")).to eq(2)
        game.state.players[1].graveyard.map { game.state.object(it).card }
      end
      expect(picks.first.size).to eq(1)
      expect(picks.first).to eq(picks.last)
    end

    it "picks a matching card at random from a graveyard" do
      game = board(hand: ["Grave Lottery"], graveyard: ["Grizzly Bears", "Forest", "Forest"], mana: { B: 1, C: 1 })
      cast(game, "Grave Lottery")
      expect(ids_in(game, "alice", :hand).map { game.state.object(it).card }).to eq(["grizzly_bears"])
    end
  end

  describe "coin flips (CR 705)" do
    it "the flipper calls the flip and draws only if the call wins (CR 705.2)" do
      game = board(battlefield: ["Coinflip Gambler"], mana: { C: 1 })
      play(game, { type: "activate", object: obj_id(game, "Coinflip Gambler"), ability: "printed:0" },
           { type: "call", call: "heads" })
      flip = events(game).find { it["type"] == "coin_flipped" }
      expect(flip["won"]).to eq(flip["heads"])
      expect(hand_size(game, "alice")).to eq(flip["won"] ? 1 : 0)
    end

    it "counting heads: no one wins or loses, and the count is the effect's amount" do
      game = board(hand: ["Fortune's Toss"], mana: { R: 1 }, seed: 3)
      cast(game, "Fortune's Toss")
      flips = events(game).select { it["type"] == "coin_flipped" }
      expect(flips.size).to eq(3)
      expect(flips.map { it["won"] }).to all(be_nil)
      expect(game.state.players[1].life).to eq(20 - flips.count { it["heads"] })
    end
  end

  describe "proliferate (CR 701.34a) and poison counters (CR 122.1f)" do
    it "gives each chosen permanent and player another counter of each kind" do
      game = board(battlefield: ["Counter Tender", ["Grizzly Bears", { counters: { "+1/+1" => 1, "stun" => 1 } }],
                                 ["Grizzly Bears", { counters: { "+1/+1" => 1 } }]],
                   poison: 3, mana: { C: 1 })
      bears = game.state.battlefield.select { game.state.object(it).card == "grizzly_bears" }
      play(game, { type: "activate", object: obj_id(game, "Counter Tender"), ability: "printed:0" },
           ->(g) { g.legal_options.find { it[:object] == bears.first } },
           ->(g) { g.legal_options.find { it[:object] == "player:bob" } },
           { type: "done" })
      expect(game.state.object(bears.first).counters).to include("+1/+1" => 2, "stun" => 2)
      expect(game.state.object(bears.last).counters["+1/+1"]).to eq(1)
      expect(game.state.players[1].poison).to eq(4)
    end

    it "gives a chosen player another counter of each kind they have, not only poison (CR 122.1)" do
      game = board(battlefield: ["Counter Tender"], poison: 1, mana: { C: 1 })
      game.state.players[1].counters = { "experience" => 2 }
      play(game, { type: "activate", object: obj_id(game, "Counter Tender"), ability: "printed:0" },
           ->(g) { g.legal_options.find { it[:object] == "player:bob" } })
      expect([game.state.players[1].poison, game.state.players[1].counters]).to eq([2, { "experience" => 3 }])
    end

    it "\"that player gets two poison counters\"; ten poison counters lose the game (CR 704.5c)" do
      game = build_game do
        turn 3, active: "alice", step: :beginning_of_combat
        player("alice") { battlefield "Venomtongue Stalker" }
        player("bob", poison: 8) { library "Swamp", count: 5 }
      end
      pass_both(game)
      game.submit(type: "attack", object: obj_id(game, "Venomtongue Stalker"), target: "player:bob")
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
      game.submit(type: game.legal_options.first[:type]) until game.over?
      expect(game.state.players[1].poison).to eq(10)
      expect(game.state.result).to include("winner" => "alice")
    end
  end
end
