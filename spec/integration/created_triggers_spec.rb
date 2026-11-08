# frozen_string_literal: true

# Invented test cards only.
RSpec.describe "Created, reflexive and choice-driven triggers (CR 603.7, 603.12, 608.2e, 614.12, 614.1c)" do
  def creature(name, stats, abilities, cost: "{1}")
    { "name" => name, "mana_cost" => cost, "types" => ["creature"], "power" => stats[0], "toughness" => stats[1],
      "abilities" => abilities }
  end

  def spell(name, targets, effects, types: ["instant"])
    { "name" => name, "mana_cost" => "{G}", "types" => types,
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? } }] }
  end

  def triggered(when_, effects, **extra) = { "triggered" => { "when" => when_, "effects" => effects }.merge(extra.transform_keys(&:to_s)) }
  def draw(n = 1) = { "draw" => { "amount" => n } }
  def counter_on(to) = { "add_counters" => { "counter" => "+1/+1", "amount" => 1, "to" => to } }
  def watched_dies = { "dies" => { "subject" => "watched" } }
  def yours(filter) = { "each" => filter, "controller" => "you" }

  let(:cards) do
    [
      spell("Last Stand Rite", ["creature"], [{ "pump" => { "power" => 2, "toughness" => 0, "to" => { "target" => 0 } } },
                                              { "delayed_trigger" => { "when" => watched_dies, "watch" => { "target" => 0 },
                                                                       "this_turn" => true, "effects" => [draw] } }]),
      spell("Arrival Surge", [], [{ "delayed_trigger" => { "when" => { "enters" => { "subject" => yours("creature") } },
                                                           "this_turn" => true,
                                                           "effects" => [counter_on({ "triggering" => "object" })] } }],
            types: ["sorcery"]),
      spell("Echo Bond", ["creature"], [{ "delayed_trigger" => { "when" => { "deals_damage" => { "subject" => "watched", "combat" => true,
                                                                                                 "to" => "player" } },
                                                                 "watch" => { "target" => 0 }, "this_turn" => true,
                                                                 "effects" => [draw({ "triggering" => "amount" })] } }]),
      spell("Second Chance Vow", ["creature"], [
              { "delayed_trigger" => { "when" => watched_dies, "watch" => { "target" => 0 }, "this_turn" => true, "effects" => [
                { "delayed_trigger" => { "when" => { "step_begins" => { "step" => "end", "whose" => "each" } },
                                         "watch" => { "triggering" => "object" },
                                         "effects" => [{ "return_to_battlefield" => { "to" => "watched",
                                                                                      "counters" => { "+1/+1" => 1 } } }] } }
              ] } }
            ]),
      spell("Mass Zap", [], [{ "deal_damage" => { "amount" => 3, "to" => { "each" => "creature" } } }], types: ["sorcery"]),
      creature("Bold Duelist", [2, 2], [triggered({ "enters" => {} }, [
                                                    { "may" => { "effects" => [{ "lose_life" => { "amount" => 2, "to" => "you" } }],
                                                                 "then" => [{ "reflexive_trigger" => {
                                                                   "targets" => ["any_target"],
                                                                   "effects" => [{ "deal_damage" => { "amount" => 2,
                                                                                                      "to" => { "target" => 0 } } }]
                                                                 } }] } }
                                                  ])]),
      { "name" => "Hard Bargain", "mana_cost" => "{G}", "types" => ["enchantment"], "abilities" => [
        triggered({ "enters" => {} }, [{ "may" => { "chooser" => { "target" => 0 }, "effects" => [draw],
                                                    "otherwise" => [{ "lose_life" => { "amount" => 4, "to" => { "target" => 0 } } }] } }],
                  targets: ["opponent"])
      ] },
      creature("Number Keeper", [1, 3], [{ "choose_number" => { "min" => 0, "max" => 3 } },
                                         triggered({ "cast" => { "controller" => "opponent", "mana_value" => "chosen" } }, [draw])]),
      creature("Name Warden", [3, 1], [{ "choose_card_name" => { "not" => ["land"] } },
                                       triggered({ "any_of" => [{ "cast" => { "controller" => "opponent", "name" => "chosen" } },
                                                                { "activates_ability" => { "controller" => "opponent",
                                                                                           "name" => "chosen" } }] },
                                                 [{ "lose_life" => { "amount" => 3, "to" => { "triggering" => "player" } } }])]),
      { "name" => "Frontier Post", "types" => ["land"], "abilities" => [
        { "enters_tapped_unless" => { "condition" => { "controls" => { "each" => "land", "controller" => "you" }, "at_least" => 2 } } },
        triggered({ "enters" => { "untapped" => true } }, [{ "gain_life" => { "amount" => 2 } }]),
        { "mana" => { "cost" => ["tap"], "produce" => "{G}" } }
      ] },
      { "name" => "Chronicle Altar", "mana_cost" => "{2}", "types" => ["artifact"], "abilities" => [
        { "activated" => { "cost" => [{ "mana" => "{1}" }], "targets" => ["permanent"],
                           "effects" => [{ "another_counter" => { "to" => { "target" => 0 } } }] } }
      ] }
    ]
  end
  let(:catalog) { catalog_with(*cards) }

  def slug(card) = Enjine::CardDefinition.slug(card)
  def life(game, index) = game.state.players[index].life
  def engine_of(game) = game.instance_variable_get(:@engine)
  def hand_id(game, player, card) = ids_in(game, player, :hand).find { game.state.object(it).card == slug(card) }
  def stack_cards(game) = game.state.stack.map { game.state.object(it).card }

  def pay_all(game)
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
  end

  def cast(game, card, player: "alice", targets: [])
    game.submit(type: "cast", object: hand_id(game, player, card))
    targets.each { game.submit(type: "target", target: it) }
    pay_all(game)
  end

  def pass_until_stack_empty(game, limit: 20)
    limit.times do
      break if game.pending_decision.kind != "priority" || game.state.stack.empty?

      game.submit(type: "pass")
    end
  end

  # Passes priority until a decision of `kind` is pending.
  def advance_to(game, kind, limit: 20)
    limit.times do
      return if game.pending_decision.kind == kind

      game.submit(type: "pass")
    end
    raise "no #{kind} decision"
  end

  def board(step: :precombat_main, turn: 3, &)
    build_game(catalog) do
      turn turn, active: "alice", step: step
      instance_eval(&)
    end
  end

  describe "delayed triggers watching an object (CR 603.7c)" do
    it "\"when that creature dies this turn\" triggers when the watched creature dies" do
      game = board do
        player("alice", mana_pool: { G: 2 }) do
          battlefield "Grizzly Bears"
          hand "Last Stand Rite", "Mass Zap"
          library "Forest", count: 3
        end
        player("bob") { battlefield "Hill Giant" }
      end
      cast(game, "Last Stand Rite", targets: [obj_id(game, "Grizzly Bears")])
      pass_until_stack_empty(game)
      expect(game.state.delayed_triggers.first).to include("watched" => [anything], "turn" => 3)
      cast(game, "Mass Zap")
      pass_until_stack_empty(game)
      expect(ids_in(game, "alice", :hand).size).to eq(1) # one draw, for the watched creature only
    end

    it "expires at the end of the turn (CR 603.7b)" do
      game = board do
        player("alice", mana_pool: { G: 1 }) do
          battlefield "Grizzly Bears"
          hand "Last Stand Rite"
          library "Forest", count: 3
        end
        player("bob")
      end
      cast(game, "Last Stand Rite", targets: [obj_id(game, "Grizzly Bears")])
      pass_until_stack_empty(game)
      skip_to(game, :upkeep, turn: 4)
      expect(game.state.delayed_triggers).to be_empty
    end

    it "a created trigger can create another delayed trigger that returns the card with a counter (CR 603.7c, 122.6)" do
      game = board do
        player("alice", mana_pool: { G: 2 }) do
          battlefield "Grizzly Bears"
          hand "Second Chance Vow", "Mass Zap"
          library "Forest", count: 3
        end
        player("bob")
      end
      cast(game, "Second Chance Vow", targets: [obj_id(game, "Grizzly Bears")])
      pass_until_stack_empty(game)
      cast(game, "Mass Zap")
      pass_until_stack_empty(game)
      expect(ids_in(game, "alice", :graveyard).map { game.state.object(it).card }).to include("grizzly_bears")
      skip_to(game, :end, turn: 3)
      pass_until_stack_empty(game)
      bears = obj_id(game, "Grizzly Bears")
      expect(game.state.object(bears).counters).to eq("+1/+1" => 1)
    end
  end

  describe "\"whenever ... this turn\" created triggers (CR 603.7b)" do
    it "trigger each time, with the triggering object, until the turn ends" do
      game = board do
        player("alice", mana_pool: { G: 1, R: 2 }) do
          hand "Arrival Surge", "Raging Goblin", count: 1
          hand "Raging Goblin"
        end
        player("bob")
      end
      cast(game, "Arrival Surge")
      pass_until_stack_empty(game)
      2.times do
        cast(game, "Raging Goblin")
        pass_until_stack_empty(game)
      end
      goblins = game.state.battlefield.select { game.state.object(it).card == "raging_goblin" }
      expect(goblins.map { game.state.object(it).counters }).to eq([{ "+1/+1" => 1 }] * 2)
    end

    it "\"that many\" is the damage dealt in the triggering event" do
      game = board(step: :beginning_of_combat) do
        player("alice", mana_pool: { G: 1 }) do
          battlefield "Hill Giant"
          hand "Echo Bond"
          library "Forest", count: 5
        end
        player("bob")
      end
      cast(game, "Echo Bond", targets: [obj_id(game, "Hill Giant")])
      pass_until_stack_empty(game)
      pass_both(game)
      game.submit(type: "attack", object: obj_id(game, "Hill Giant"), target: "player:bob")
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
      pass_both(game, 2)
      pass_until_stack_empty(game)
      expect(ids_in(game, "alice", :hand).size).to eq(3)
    end
  end

  describe "reflexive triggers (CR 603.12)" do
    def duelist_board
      board do
        player("alice", mana_pool: { G: 1 }) { hand "Bold Duelist" }
        player("bob") { battlefield "Grizzly Bears" }
      end
    end

    it "\"when you do\" triggers only if the optional action was taken; its target is chosen as it goes on the stack" do
      game = duelist_board
      cast(game, "Bold Duelist")
      advance_to(game, "effect_choice")
      game.submit(type: "yes")
      expect(game.pending_decision.kind).to eq("choose_target")
      game.submit(type: "target", target: obj_id(game, "Grizzly Bears"))
      pass_until_stack_empty(game)
      expect(life(game, 0)).to eq(18)
      expect(game.state.players[1].graveyard.map { game.state.object(it).card }).to eq(["grizzly_bears"])
    end

    it "doesn't trigger when the player declines" do
      game = duelist_board
      cast(game, "Bold Duelist")
      advance_to(game, "effect_choice")
      game.submit(type: "no")
      expect(game.state.pending_triggers).to be_empty
      expect(game.pending_decision.kind).to eq("priority")
    end
  end

  describe "an optional effect decided by another player (CR 608.2e)" do
    it "the target opponent chooses; if they don't, they lose life" do
      game = board do
        player("alice", mana_pool: { G: 2 }) do
          hand "Hard Bargain"
          library "Forest", count: 3
        end
        player("bob")
      end
      cast(game, "Hard Bargain")
      advance_to(game, "choose_target")
      game.submit(type: "target", target: "player:bob")
      advance_to(game, "effect_choice")
      expect(game.pending_decision.player).to eq("bob")
      game.submit(type: "no")
      expect(life(game, 1)).to eq(16)
    end
  end

  describe "\"as this enters\" choices (CR 614.12, 201.4)" do
    it "a chosen number: opponents' spells with that mana value draw you a card" do
      game = board do
        player("alice", mana_pool: { G: 1 }) do
          hand "Number Keeper"
          library "Forest", count: 3
        end
        player("bob", mana_pool: { R: 2 }) { hand "Lightning Bolt", "Hill Giant" }
      end
      cast(game, "Number Keeper")
      advance_to(game, "enter_choice")
      expect(game.legal_options.map { it[:number] }).to eq([0, 1, 2, 3])
      game.submit(type: "number", number: 1)
      keeper = obj_id(game, "Number Keeper")
      expect(game.state.object(keeper).memory["chosen_number"]).to eq(1)
      game.submit(type: "pass")
      cast(game, "Lightning Bolt", player: "bob", targets: ["player:alice"])
      expect(stack_cards(game)).to eq(%w[number_keeper lightning_bolt])
    end

    it "a chosen card name: casting a spell or activating an ability of that name costs its controller life" do
      game = board do
        player("alice", mana_pool: { G: 1 }) { hand "Name Warden" }
        player("bob", mana_pool: { R: 1 }) do
          battlefield "Prodigal Pyromancer"
          hand "Lightning Bolt"
        end
      end
      cast(game, "Name Warden")
      advance_to(game, "enter_choice")
      names = game.legal_options.map { it[:name] }
      expect(names).to include("Prodigal Pyromancer", "Lightning Bolt")
      expect(names).not_to include("Mountain")
      game.submit(type: "name", name: "Prodigal Pyromancer")
      game.submit(type: "pass")
      game.submit(type: "activate", object: obj_id(game, "Prodigal Pyromancer"), ability: "printed:0")
      game.submit(type: "target", target: "player:alice")
      pass_until_stack_empty(game)
      expect(life(game, 1)).to eq(17)
      game.submit(type: "pass")
      cast(game, "Lightning Bolt", player: "bob", targets: ["player:alice"])
      pass_until_stack_empty(game)
      expect(life(game, 1)).to eq(17)
    end
  end

  describe "enters tapped unless (CR 614.1c) and \"when it enters untapped\"" do
    def land_board(lands)
      board do
        player("alice") do
          hand "Frontier Post"
          lands.times { battlefield "Forest" }
        end
        player("bob")
      end
    end

    it "enters tapped with fewer than two other lands, and doesn't trigger" do
      game = land_board(1)
      game.submit(type: "play_land", object: hand_id(game, "alice", "Frontier Post"))
      expect(game.state.object(obj_id(game, "Frontier Post")).tapped).to be(true)
      expect(game.state.stack).to be_empty
    end

    it "enters untapped with two other lands and triggers" do
      game = land_board(2)
      game.submit(type: "play_land", object: hand_id(game, "alice", "Frontier Post"))
      expect(game.state.object(obj_id(game, "Frontier Post")).tapped).to be(false)
      pass_until_stack_empty(game)
      expect(life(game, 0)).to eq(22)
    end
  end

  describe "another counter of a kind already there (CR 122.1)" do
    it "adds one counter, asking which kind when there are several" do
      game = board do
        player("alice", mana_pool: { G: 2 }) do
          battlefield "Chronicle Altar"
          battlefield "Grizzly Bears", counters: { "+1/+1" => 1, "shield" => 1 }
          battlefield "Hill Giant", counters: { "+1/+1" => 2 }
        end
        player("bob")
      end
      altar = obj_id(game, "Chronicle Altar")
      game.submit(type: "activate", object: altar, ability: "printed:0")
      game.submit(type: "target", target: obj_id(game, "Hill Giant"))
      pay_all(game)
      pass_until_stack_empty(game)
      expect(game.state.object(obj_id(game, "Hill Giant")).counters).to eq("+1/+1" => 3)
      game.submit(type: "activate", object: altar, ability: "printed:0")
      game.submit(type: "target", target: obj_id(game, "Grizzly Bears"))
      pay_all(game)
      pass_both(game)
      expect(game.legal_options).to eq([{ type: "counter", counter: "+1/+1" }, { type: "counter", counter: "shield" }])
      game.submit(type: "counter", counter: "shield")
      expect(game.state.object(obj_id(game, "Grizzly Bears")).counters).to eq("+1/+1" => 1, "shield" => 2)
    end
  end
end
