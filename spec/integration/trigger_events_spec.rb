# frozen_string_literal: true

# Invented test cards only.
RSpec.describe "Trigger events, limits and trigger doubling (CR 603.2, 603.2c-e, 603.10a, 113.6k)" do
  def creature(name, stats, abilities, cost: "{1}", keywords: [])
    { "name" => name, "mana_cost" => cost, "types" => ["creature"], "power" => stats[0], "toughness" => stats[1],
      "keywords" => keywords, "abilities" => abilities }
  end

  def spell(name, cost, targets, effects, types: ["instant"])
    { "name" => name, "mana_cost" => cost, "types" => types,
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? } }] }
  end

  def triggered(when_, effects, **extra) = { "triggered" => { "when" => when_, "effects" => effects }.merge(extra.transform_keys(&:to_s)) }
  def gain(n) = { "gain_life" => { "amount" => n } }
  def draw(n = 1) = { "draw" => { "amount" => n } }
  def saga_spell = { "triggering" => { "spell" => { "subtypes" => ["saga"] } } }
  def your_creature_cards = { "each" => { "graveyard_card" => { "any_of" => ["creature"] } }, "controller" => "you" }

  def creature_or_spacecraft
    { "one_of" => [{ "spell" => { "any_of" => ["creature"] } }, { "spell" => { "subtypes" => ["spacecraft"] } }] }
  end

  let(:cards) do
    [
      creature("Tapwatch Scout", [2, 2], [triggered({ "becomes_tapped" => {} }, [gain(1)])]),
      creature("Growth Chronicler", [1, 1], [triggered({ "counters_placed" => { "counter" => "+1/+1" } }, [draw])]),
      creature("Guarded Recruit", [1, 1], [triggered({ "becomes_target" => { "subject" => { "each" => "creature", "controller" => "you" },
                                                                             "by" => "opponent" } },
                                                     [{ "add_counters" => { "counter" => "+1/+1", "amount" => 1,
                                                                            "to" => { "triggering" => "object" } } }])]),
      creature("Grave Listener", [1, 1], [triggered({ "leaves_graveyard" => { "batched" => true } }, [gain(1)])]),
      creature("Grave Counter", [1, 1], [triggered({ "leaves_graveyard" => { "card" => "creature" } }, [gain(1)])]),
      creature("Grave Miser", [1, 1], [triggered({ "leaves_graveyard" => {} }, [draw], limit: "once_each_turn")]),
      creature("Toll Collector", [1, 1], [triggered({ "activates_ability" => { "controller" => "opponent" } },
                                                    [{ "lose_life" => { "amount" => 2, "to" => { "triggering" => "player" } } }])]),
      creature("Scar Gatherer", [1, 1], [triggered({ "dies" => { "subject" => { "each" => "creature", "other" => true } } },
                                                   [{ "add_counters" => { "counter" => "+1/+1", "amount" => 1, "to" => "self" } }],
                                                   limit: "once_each_turn")]),
      creature("Joyful Medic", [1, 1], [{ "additional_triggers" => { "cause" => "you_gain_life" } },
                                        triggered({ "gains_life" => {} },
                                                  [{ "add_counters" => { "counter" => "+1/+1", "amount" => 1, "to" => "self" } }])]),
      creature("Echoing Herald", [1, 1], [triggered({ "cast" => { "self" => true } }, [draw])], cost: "{G}"),
      creature("Restless Shade", [2, 2], [triggered({ "gains_life" => { "controller" => "opponent" } },
                                                    [{ "lose_life" => { "amount" => 1, "to" => "each_opponent" } }],
                                                    zone: "graveyard")]),
      creature("Saga Scholar", [1, 1], [triggered({ "cast" => { "spell" => { "spell" => { "any_of" => ["enchantment"] } } } },
                                                  [draw,
                                                   { "lose_life" => { "amount" => 2, "to" => "each_opponent", "if" => saga_spell } }])]),
      creature("Spacefarer Patron", [1, 1], [triggered({ "cast" => { "spell" => creature_or_spacecraft } }, [gain(1)])]),
      { "name" => "Little Saga", "mana_cost" => "{G}", "types" => ["enchantment"], "subtypes" => ["saga"],
        "abilities" => [{ "chapter" => { "chapter" => 1, "effects" => [gain(1)] } }] },
      { "name" => "Plain Charm", "mana_cost" => "{G}", "types" => ["enchantment"] },
      { "name" => "Tiny Skiff", "mana_cost" => "{G}", "types" => ["artifact"], "subtypes" => ["spacecraft"] },
      spell("Second Wind", "{G}", ["creature"], [{ "add_counters" => { "counter" => "+1/+1", "amount" => 2, "to" => { "target" => 0 } } }]),
      spell("Small Blessing", "{G}", [], [gain(2)]),
      spell("Mass Exhumation", "{G}", [], [{ "return_to_battlefield" => { "to" => your_creature_cards } }], types: ["sorcery"]),
      spell("Zap", "{R}", ["any_target"], [{ "deal_damage" => { "amount" => 1, "to" => { "target" => 0 } } }]),
      spell("Mass Zap", "{R}", [], [{ "deal_damage" => { "amount" => 2, "to" => { "each" => "creature" } } }])
    ]
  end
  let(:catalog) { catalog_with(*cards) }

  def slug(card) = Enjine::CardDefinition.slug(card)
  def life(game, index) = game.state.players[index].life
  def stack_cards(game) = game.state.stack.map { game.state.object(it).card }
  def hand_id(game, player, card) = ids_in(game, player, :hand).find { game.state.object(it).card == slug(card) }

  def pay_all(game)
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
  end

  def cast(game, card, player: "alice", targets: [])
    game.submit(type: "cast", object: hand_id(game, player, card))
    targets.each { game.submit(type: "target", target: it) }
    pay_all(game)
  end

  def engine_of(game) = game.instance_variable_get(:@engine)

  def board(step: :precombat_main, &)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      instance_eval(&)
    end
  end

  def resolve_all(game, limit: 20)
    limit.times do
      break if game.state.stack.empty? && game.pending_decision.kind == "priority"

      kind = game.pending_decision.kind
      kind == "priority" ? game.submit(type: "pass") : game.submit(game.legal_options.first)
    end
  end

  describe "becomes_tapped (CR 603.2e)" do
    it "triggers when the permanent becomes tapped by attacking, not when it enters tapped" do
      game = board(step: :beginning_of_combat) do
        player("alice") { battlefield "Tapwatch Scout" }
        player("bob") { library "Forest", count: 3 }
      end
      pass_both(game)
      game.submit(type: "attack", object: obj_id(game, "Tapwatch Scout"), target: "player:bob")
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
      expect(stack_cards(game)).to eq(["tapwatch_scout"])
      resolve_all(game)
      expect(life(game, 0)).to eq(21)
    end

    it "doesn't trigger for a permanent that enters the battlefield tapped" do
      game = board do
        player("alice", mana_pool: { G: 1 }) { graveyard "Tapwatch Scout" }
        player("bob")
      end
      scout = ids_in(game, "alice", :graveyard).first
      engine_of(game).move!(scout, :battlefield, reason: "return", enters: { "tapped" => true })
      expect(game.state.pending_triggers).to be_empty
    end
  end

  describe "counters_placed (CR 122.6)" do
    it "triggers once per placing event, including counters it enters with" do
      game = board do
        player("alice", mana_pool: { G: 1 }) do
          battlefield "Growth Chronicler"
          hand "Second Wind"
          library "Forest", count: 5
        end
        player("bob")
      end
      cast(game, "Second Wind", targets: [obj_id(game, "Growth Chronicler")])
      resolve_all(game)
      expect(ids_in(game, "alice", :hand).size).to eq(1)
      chronicler = obj_id(game, "Growth Chronicler")
      engine_of(game).move!(chronicler, :exile, reason: "exile")
      exiled = game.state.exile.first
      engine_of(game).move!(exiled, :battlefield, reason: "return", enters: { "counters" => { "+1/+1" => 1 } })
      expect(game.state.pending_triggers.size).to eq(1)
    end
  end

  describe "becomes_target (CR 115.1, 603.2c)" do
    it "triggers when an opponent's spell targets your creature, once the spell is cast; the triggering object gets the counter" do
      game = board do
        player("alice") { battlefield "Guarded Recruit", "Grizzly Bears" }
        player("bob", mana_pool: { R: 1 }) { hand "Zap" }
        priority "bob"
      end
      bears = obj_id(game, "Grizzly Bears")
      cast(game, "Zap", player: "bob", targets: [bears])
      expect(game.state.pending_triggers).to be_empty # resolved into the put-on-stack process
      expect(stack_cards(game).first).to eq("guarded_recruit")
      game.submit(type: "pass")
      game.submit(type: "pass")
      expect(game.state.object(bears).counters).to eq("+1/+1" => 1)
    end

    it "doesn't trigger for a cancelled cast or for your own spells" do
      game = board do
        player("alice", mana_pool: { R: 1 }) do
          battlefield "Guarded Recruit"
          hand "Zap"
        end
        player("bob", mana_pool: { R: 1 }) { hand "Zap" }
      end
      recruit = obj_id(game, "Guarded Recruit")
      game.submit(type: "cast", object: hand_id(game, "alice", "Zap"))
      game.submit(type: "target", target: recruit)
      game.submit(type: "cancel")
      cast(game, "Zap", targets: [recruit])
      expect(stack_cards(game)).to eq(["zap"])
    end
  end

  describe "leaves_graveyard (CR 603.10a, 603.2c)" do
    def exhumation_board
      board do
        player("alice", mana_pool: { G: 1 }) do
          battlefield "Grave Listener", "Grave Counter", "Grave Miser"
          hand "Mass Exhumation"
          graveyard "Grizzly Bears", "Hill Giant", "Small Blessing"
          library "Forest", count: 5
        end
        player("bob")
      end
    end

    it "one or more cards leaving in one event batch trigger a batched ability once; per-card abilities once per card" do
      game = exhumation_board
      cast(game, "Mass Exhumation")
      game.submit(type: "pass")
      game.submit(type: "pass")
      sources = game.state.pending_triggers.map { it["card"] }
      sources = stack_cards(game) if sources.empty?
      expect(sources.tally).to include("grave_listener" => 1, "grave_counter" => 2, "grave_miser" => 1)
    end

    it "an ability that triggers only once each turn triggers again the next turn, and only for that object" do
      game = exhumation_board
      cast(game, "Mass Exhumation")
      resolve_all(game)
      miser = game.state.objects[obj_id(game, "Grave Miser")]
      expect(miser.memory["triggered_turn"]).to eq("printed:0" => 3)
      engine_of(game).move!(ids_in(game, "alice", :graveyard).first, :exile, reason: "exile")
      expect(game.state.pending_triggers.map { it["card"] }).not_to include("grave_miser")
      game.state.turn = 4
      engine_of(game).move!(ids_in(game, "alice", :graveyard).first, :exile, reason: "exile") unless ids_in(game, "alice",
                                                                                                            :graveyard).empty?
      engine_of(game).move!(ids_in(game, "alice", :hand).first, :graveyard, reason: "discard")
      engine_of(game).move!(ids_in(game, "alice", :graveyard).first, :exile, reason: "exile")
      expect(game.state.pending_triggers.map { it["card"] }).to include("grave_miser")
    end
  end

  describe "activates_ability (CR 602.2, 605.1a)" do
    it "an opponent activating a non-mana ability triggers it; that player loses life; mana abilities don't" do
      game = board do
        player("alice") { battlefield "Toll Collector" }
        player("bob") { battlefield "Prodigal Pyromancer", "Mountain" }
        priority "bob"
      end
      game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
      expect(game.state.pending_triggers).to be_empty
      game.submit(type: "activate", object: obj_id(game, "Prodigal Pyromancer"), ability: "printed:0")
      game.submit(type: "target", target: "player:alice")
      resolve_all(game)
      expect(life(game, 1)).to eq(18)
      expect(life(game, 0)).to eq(19)
    end
  end

  describe "trigger limits (at most once each turn)" do
    it "two creatures dying at once trigger it only once" do
      game = board do
        player("alice", mana_pool: { R: 1 }) do
          battlefield "Scar Gatherer", "Grizzly Bears", "Raging Goblin"
          hand "Mass Zap"
        end
        player("bob")
      end
      game.state.object(obj_id(game, "Scar Gatherer")).counters["+1/+1"] = 2 # survives the 2 damage
      cast(game, "Mass Zap")
      resolve_all(game)
      expect(game.state.object(obj_id(game, "Scar Gatherer")).counters["+1/+1"]).to eq(3)
    end
  end

  describe "triggering an additional time (CR 603.2d)" do
    it "a triggered ability of your permanent triggered by you gaining life triggers twice; an opponent's gain doesn't count" do
      game = board do
        player("alice", mana_pool: { G: 1 }) do
          battlefield "Joyful Medic"
          hand "Small Blessing"
        end
        player("bob") { battlefield "Restless Shade" }
      end
      cast(game, "Small Blessing")
      resolve_all(game)
      expect(game.state.object(obj_id(game, "Joyful Medic")).counters["+1/+1"]).to eq(2)
      engine_of(game).change_life!(1, 1)
      expect(game.state.pending_triggers).to be_empty
    end
  end

  describe "cast triggers" do
    it "\"when you cast this spell\" triggers from the stack and resolves before the spell (CR 601.2i)" do
      game = board do
        player("alice", mana_pool: { G: 1 }) do
          hand "Echoing Herald"
          library "Forest", count: 3
        end
        player("bob")
      end
      cast(game, "Echoing Herald")
      expect(stack_cards(game)).to eq(%w[echoing_herald echoing_herald])
      expect(game.state.object(game.state.stack.first).kind).to eq("ability")
      resolve_all(game)
      expect(ids_in(game, "alice", :hand).size).to eq(1)
    end

    it "filters spells by type and subtype; a condition reads the triggering spell (\"if it's a Saga spell\")" do
      game = board do
        player("alice", mana_pool: { G: 3, R: 1 }) do
          battlefield "Saga Scholar", "Spacefarer Patron"
          hand "Little Saga", "Plain Charm", "Tiny Skiff", "Raging Goblin"
          library "Forest", count: 5
        end
        player("bob")
      end
      cast(game, "Little Saga")
      resolve_all(game)
      expect(life(game, 1)).to eq(18)
      cast(game, "Plain Charm")
      resolve_all(game)
      expect(life(game, 1)).to eq(18)
      expect(ids_in(game, "alice", :hand).size).to eq(4) # two draws, two cards cast
      cast(game, "Tiny Skiff")
      resolve_all(game)
      cast(game, "Raging Goblin")
      resolve_all(game)
      expect(life(game, 0)).to eq(23) # Little Saga's chapter I + two Spacefarer Patron triggers
    end
  end

  describe "graveyard triggers (CR 113.6k)" do
    it "functions only while its card is in a graveyard, controlled by its owner" do
      game = board do
        player("alice", mana_pool: { G: 2 }) { hand "Small Blessing", count: 2 }
        player("bob") do
          battlefield "Restless Shade"
          graveyard "Restless Shade"
        end
      end
      cast(game, "Small Blessing")
      resolve_all(game)
      expect(life(game, 0)).to eq(21) # 22 - 1: only the graveyard copy triggered
      expect(game.history.flat_map(&:events).grep(Enjine::Events::AbilityTriggered).map(&:player)).to eq(["bob"])
    end
  end
end
