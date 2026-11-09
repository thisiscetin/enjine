# frozen_string_literal: true

# Invented test cards only.
RSpec.describe "Turn-history conditions and zone-change triggers (CR 508.1, 400.7, 603.2, 603.6c, 603.10a)" do
  def creature(name, stats, abilities, cost: "{1}", types: ["creature"], subtypes: [])
    { "name" => name, "mana_cost" => cost, "types" => types, "subtypes" => subtypes, "power" => stats[0],
      "toughness" => stats[1], "abilities" => abilities }
  end

  def spell(name, effects, cost: "{G}", targets: [])
    { "name" => name, "mana_cost" => cost, "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? } }] }
  end

  def triggered(when_, effects, **extra) = { "triggered" => { "when" => when_, "effects" => effects }.merge(extra.transform_keys(&:to_s)) }
  def gain(amount) = { "gain_life" => { "amount" => amount } }
  def food = { "artifact" => { "subtypes" => ["food"] } }
  def its_counters = { "counters" => { "of" => "self", "kind" => "+1/+1" } }
  def at_least(kind, data, n = 1) = { "amount" => { kind => data }, "at_least" => n }

  let(:cards) do
    [
      creature("Parting Gift", [1, 1], [triggered({ "leaves_battlefield" => {} }, [gain(2)])]),
      creature("Hoarding Mentor", [1, 1], [triggered({ "leaves_battlefield" => {} },
                                                     [{ "add_counters" => { "counter" => "+1/+1", "amount" => its_counters,
                                                                            "to" => { "target" => 0 } } }],
                                                     targets: ["creature"])]),
      creature("Proud Martyr", [2, 2], [triggered({ "any_of" => [{ "dies" => {} }, { "leaves_battlefield" => { "to" => "exile" } }] },
                                                  [gain(5)], if: { "amount" => { "power" => "self" }, "at_least" => 4 })]),
      creature("Exile Watcher", [1, 1], [triggered({ "leaves_battlefield" => { "to" => "exile",
                                                                               "subject" => { "each" => "creature", "controller" => "you",
                                                                                              "other" => true } } },
                                                   [gain(1)])]),
      creature("Scrap Savant", [1, 1], [triggered({ "sacrifices" => { "subject" => { "each" => "artifact", "controller" => "you" } } },
                                                  [gain(1)])]),
      creature("Rummage Fiend", [1, 1], [triggered({ "discards" => { "batched" => true } },
                                                   [{ "gain_life" => { "amount" => { "triggering" => "amount" } } }])]),
      creature("Page Mourner", [1, 1], [triggered({ "discards" => { "card" => "land" } }, [gain(1)])]),
      creature("Cycle Keeper", [1, 1], [triggered({ "cycles" => {} }, [gain(3)])]),
      creature("Seer Acolyte", [1, 1], [triggered({ "any_of" => [{ "scries" => {} }, { "surveils" => {} }] }, [gain(1)])]),
      creature("Spring Loaded", [1, 1], [triggered({ "becomes_untapped" => {} }, [gain(1)])]),
      creature("Bone Collector", [1, 1], [triggered({ "put_into" => { "zone" => "graveyard", "card" => "creature",
                                                                      "batched" => true } },
                                                    [{ "gain_life" => { "amount" => { "triggering" => "amount" } } }])]),
      creature("Exile Archivist", [1, 1], [triggered({ "put_into" => { "zone" => "exile", "from" => ["graveyard"],
                                                                       "controller" => "any" } }, [gain(1)])]),
      creature("Raid Bannerman", [2, 2], [triggered({ "step_begins" => { "step" => "end" } }, [gain(3)],
                                                    if: { "you_attacked_this_turn" => true })]),
      creature("Vanishing Act", [1, 1], [triggered({ "enters" => {} }, [gain(4)],
                                                   if: at_least("left_this_turn", { "controller" => "you" }))]),
      { "name" => "Trinket", "mana_cost" => "{1}", "types" => ["artifact"] },
      { "name" => "Trail Ration", "mana_cost" => "{1}", "types" => ["artifact"], "subtypes" => ["food"],
        "abilities" => [{ "activated" => { "cost" => ["sacrifice"], "effects" => [gain(3)] } }] },
      creature("Ration Hoarder", [1, 1], [triggered({ "sacrifices" => { "subject" => { "each" => food, "controller" => "you" } } },
                                                    [{ "draw" => { "amount" => 1 } }])]),
      { "name" => "Mourning Bell", "mana_cost" => "{1}", "types" => ["artifact"],
        "abilities" => [triggered({ "dies" => { "subject" => { "each" => "creature" } } }, [gain(1)])] },
      creature("Pack Mourner", [1, 1], [triggered({ "leaves_battlefield" => { "subject" => { "each" => "creature", "controller" => "you",
                                                                                             "other" => true } } }, [gain(1)])]),
      spell("Cleansing Purge", [{ "destroy" => { "to" => { "each" => "permanent", "controller" => "any" } } }], cost: "{W}"),
      spell("Ember Sweep", [{ "deal_damage" => { "amount" => 1, "to" => { "each" => "creature", "controller" => "any" } } }], cost: "{R}"),
      spell("Brain Drain", [{ "discard" => { "amount" => 2 } }]),
      spell("Glimpse", [{ "scry" => { "amount" => 2 } }]),
      spell("Glimpse Nothing", [{ "scry" => { "amount" => 0 } }]),
      spell("Grave Tide", [{ "mill" => { "amount" => 3 } }]),
      { "name" => "Cycling Rock", "mana_cost" => "{3}", "types" => ["artifact"], "abilities" => [{ "cycling" => { "cost" => "{G}" } }] }
    ]
  end
  let(:catalog) { catalog_with(*cards) }

  def slug(card) = Enjine::CardDefinition.slug(card)
  def life(game, index = 0) = game.state.players[index].life
  def engine_of(game) = game.instance_variable_get(:@engine)
  def hand_id(game, card, player: "alice") = ids_in(game, player, :hand).find { game.state.object(it).card == slug(card) }
  def pending_cards(game) = game.state.pending_triggers.map { it["card"] }

  # Puts the triggers of a direct engine change on the stack (as before a player gets priority) and resolves them.
  def flush(game)
    engine = engine_of(game)
    game.send(:record, "alice", "test") do # a recorded step, so the game offers the decisions that follow
      engine.put_triggers_first!(0)
      engine.advance!
    end
    resolve_all(game)
  end

  def board(step: :precombat_main, &)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      instance_eval(&)
    end
  end

  def pay_all(game)
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
  end

  def cast(game, card, targets: [])
    game.submit(type: "cast", object: hand_id(game, card))
    targets.each { game.submit(type: "target", target: it) }
    pay_all(game)
  end

  def resolve_all(game, limit: 30)
    limit.times do
      break if game.state.stack.empty? && game.pending_decision.kind == "priority"

      game.pending_decision.kind == "priority" ? game.submit(type: "pass") : game.submit(game.legal_options.first)
    end
  end

  def amount(game, data, controller: 0)
    errors = []
    built = Enjine::Mechanics::Amount.build(data, errors, "a", targets_count: 0)
    raise errors.join(", ") unless errors.empty?

    built.value(engine_of(game), Enjine::Mechanics::EffectContext.new(controller, nil, nil, []))
  end

  describe "turn history (CR 400.7, 508.1, 701.9a, 701.21a)" do
    it "records permanents leaving, sacrifices, exile, draws and discards, and forgets them next turn" do
      game = board do
        player("alice") do
          battlefield "Grizzly Bears", "Trinket", "Forest"
          hand "Forest", "Island"
          graveyard "Hill Giant"
          library "Forest", count: 5
        end
        player("bob") { battlefield "Savannah Lions" }
      end
      engine = engine_of(game)
      engine.move!(obj_id(game, "Trinket"), :graveyard, reason: "sacrifice")
      engine.move!(obj_id(game, "Grizzly Bears"), :exile, reason: "exile")
      engine.move!(ids_in(game, "alice", :graveyard).find { game.state.object(it).card == "hill_giant" }, :exile, reason: "exile")
      engine.move!(obj_id(game, "Savannah Lions"), :hand, reason: "bounce")
      engine.draw!(0)
      engine.move!(hand_id(game, "Island"), :graveyard, reason: "discard")
      expect(amount(game, { "left_this_turn" => { "controller" => "you" } })).to eq(2)
      expect(amount(game, { "left_this_turn" => { "each" => { "permanent" => { "not" => ["land"] } } } })).to eq(3)
      expect(amount(game, { "left_this_turn" => { "each" => "creature", "controller" => "opponent" } })).to eq(1)
      expect(amount(game, { "sacrificed_this_turn" => { "each" => "artifact", "controller" => "you" } })).to eq(1)
      expect(amount(game, { "sacrificed_this_turn" => { "each" => "creature" } })).to eq(0)
      expect(amount(game, { "exiled_this_turn" => {} })).to eq(2)
      expect(amount(game, { "exiled_this_turn" => { "controller" => "opponent" } })).to eq(0)
      expect(amount(game, { "cards_drawn_this_turn" => "you" })).to eq(1)
      expect(amount(game, { "cards_discarded_this_turn" => "you" })).to eq(1)
      expect(amount(game, { "cards_discarded_this_turn" => "each_opponent" })).to eq(0)
      copy = Enjine::Game.import(game.export, catalog: game.catalog)
      expect(copy.state.players[0].turn_log).to eq(game.state.players[0].turn_log)
      skip_to(game, :upkeep, turn: 4)
      expect(amount(game, { "left_this_turn" => {} })).to eq(0)
    end

    it "raid: an end step trigger checks whether you attacked this turn, and attackers are matched by subtype" do
      game = board(step: :beginning_of_combat) do
        player("alice") { battlefield "Raid Bannerman", "Grizzly Bears" }
        player("bob") { library "Forest", count: 5 }
      end
      pass_both(game)
      game.submit(type: "attack", object: obj_id(game, "Grizzly Bears"), target: "player:bob")
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
      expect(amount(game, { "attackers_this_turn" => { "each" => { "creature" => { "subtypes" => ["bear"] } }, "controller" => "you" } }))
        .to eq(1)
      expect(amount(game, { "attackers_this_turn" => { "controller" => "opponent" } })).to eq(0)
      skip_to(game, :end)
      resolve_all(game)
      expect(life(game)).to eq(23)
    end

    it "raid: no trigger when you didn't attack (CR 603.4)" do
      game = board do
        player("alice") { battlefield "Raid Bannerman" }
        player("bob") { library "Forest", count: 5 }
      end
      skip_to(game, :end)
      expect(game.state.pending_triggers).to be_empty
      expect(game.state.stack).to be_empty
      expect(life(game)).to eq(20)
    end

    it "an enters trigger with \"if a permanent left the battlefield under your control this turn\"" do
      game = board do
        player("alice", mana_pool: { G: 2 }) do
          battlefield "Trinket"
          hand "Vanishing Act", "Vanishing Act"
        end
        player("bob")
      end
      cast(game, "Vanishing Act")
      resolve_all(game)
      expect(life(game)).to eq(20)
      engine_of(game).move!(obj_id(game, "Trinket"), :hand, reason: "bounce")
      cast(game, "Vanishing Act")
      resolve_all(game)
      expect(life(game)).to eq(24)
    end
  end

  describe "leaves_battlefield (CR 603.6c, 603.10a)" do
    it "the permanent's own ability triggers whichever zone it went to" do
      game = board do
        player("alice") { battlefield "Parting Gift" }
        player("bob")
      end
      engine_of(game).move!(obj_id(game, "Parting Gift"), :hand, reason: "bounce")
      flush(game)
      expect(life(game)).to eq(22)
    end

    it "uses the counters the permanent had as it last existed" do
      game = board do
        player("alice") do
          battlefield "Hoarding Mentor", counters: { "+1/+1" => 3 }
          battlefield "Grizzly Bears"
        end
        player("bob")
      end
      engine_of(game).move!(obj_id(game, "Hoarding Mentor"), :graveyard, reason: "destroy")
      flush(game)
      expect(game.state.object(obj_id(game, "Grizzly Bears")).counters).to eq("+1/+1" => 3)
    end

    it "an intervening if reads the power it had as it last existed (CR 603.4, 603.10a)" do
      game = board do
        player("alice") do
          battlefield "Proud Martyr", counters: { "+1/+1" => 2 }
          battlefield "Proud Martyr"
        end
        player("bob")
      end
      big, small = game.state.battlefield.first(2)
      engine_of(game).move!(small, :exile, reason: "exile")
      expect(game.state.pending_triggers).to be_empty
      engine_of(game).move!(big, :exile, reason: "exile")
      flush(game)
      expect(life(game)).to eq(25)
    end

    it "`to: exile` triggers only for permanents put into exile; `other` skips the source" do
      game = board do
        player("alice") { battlefield "Exile Watcher", "Grizzly Bears", "Hill Giant" }
        player("bob") { battlefield "Savannah Lions" }
      end
      engine = engine_of(game)
      engine.move!(obj_id(game, "Hill Giant"), :graveyard, reason: "destroy")
      engine.move!(obj_id(game, "Savannah Lions"), :exile, reason: "exile")
      expect(game.state.pending_triggers).to be_empty
      engine.move!(obj_id(game, "Grizzly Bears"), :exile, reason: "exile")
      expect(pending_cards(game)).to eq(["exile_watcher"])
      engine.move!(obj_id(game, "Exile Watcher"), :exile, reason: "exile")
      expect(pending_cards(game)).to eq(["exile_watcher"])
    end
  end

  describe "looking back at permanents that leave at the same time (CR 603.10a)" do
    it "an artifact destroyed along with creatures sees them die" do
      game = board do
        player("alice", mana_pool: { W: 1 }) do
          battlefield "Mourning Bell", "Grizzly Bears"
          hand "Cleansing Purge"
        end
        player("bob") { battlefield "Hill Giant" }
      end
      cast(game, "Cleansing Purge")
      resolve_all(game)
      expect(life(game)).to eq(22)
    end

    it "creatures dying to state-based actions at once each see the others leave" do
      game = board do
        player("alice", mana_pool: { R: 1 }) do
          battlefield "Pack Mourner", "Pack Mourner", "Grizzly Bears"
          hand "Ember Sweep"
        end
        player("bob")
      end
      cast(game, "Ember Sweep")
      resolve_all(game)
      expect(life(game)).to eq(22) # each Mourner saw the other one; the Bears survived
    end
  end

  describe "sacrifices (CR 701.21a, 603.10a)" do
    it "triggers when you sacrifice a matching permanent, not when it's destroyed" do
      game = board do
        player("alice") { battlefield "Scrap Savant", "Trinket", "Trinket" }
        player("bob")
      end
      trinkets = game.state.battlefield.select { game.state.object(it).card == "trinket" }
      engine_of(game).move!(trinkets[0], :graveyard, reason: "destroy")
      expect(game.state.pending_triggers).to be_empty
      engine_of(game).move!(trinkets[1], :graveyard, reason: "sacrifice")
      flush(game)
      expect(life(game)).to eq(21)
    end
  end

  describe "sacrificing a permanent to pay its own cost (CR 701.21a, 118.3)" do
    it "counts as a sacrifice for triggers and this turn's history" do
      game = board do
        player("alice") do
          battlefield "Ration Hoarder", "Trail Ration"
          library "Forest", count: 3
        end
        player("bob")
      end
      game.submit(type: "activate", object: obj_id(game, "Trail Ration"), ability: "printed:0")
      pay_all(game)
      expect(amount(game, { "sacrificed_this_turn" => { "each" => food, "controller" => "you" } })).to eq(1)
      resolve_all(game)
      expect([life(game), ids_in(game, "alice", :hand).size]).to eq([23, 1])
    end
  end

  describe "discards and cycles (CR 701.9a, 702.29)" do
    it "\"one or more cards\" triggers once per discard event; \"that many\" counts the cards" do
      game = board do
        player("alice", mana_pool: { G: 1 }) do
          battlefield "Rummage Fiend", "Page Mourner"
          hand "Brain Drain", "Forest", "Forest"
        end
        player("bob")
      end
      cast(game, "Brain Drain")
      game.submit(type: "pass")
      game.submit(type: "pass")
      2.times { game.submit(game.legal_options.first) } # discard both Forests
      expect(pending_cards(game).tally).to eq("rummage_fiend" => 1, "page_mourner" => 2)
      resolve_all(game)
      expect(life(game)).to eq(24)
    end

    it "cycling a card triggers cycles and discards" do
      game = board do
        player("alice", mana_pool: { G: 1 }) do
          battlefield "Cycle Keeper", "Rummage Fiend"
          hand "Cycling Rock"
          library "Forest", count: 3
        end
        player("bob")
      end
      game.submit(type: "activate", object: hand_id(game, "Cycling Rock"), ability: "printed:0")
      pay_all(game)
      resolve_all(game)
      expect(life(game)).to eq(24)
    end
  end

  describe "scries / surveils (CR 701.22b, 701.25c-d)" do
    it "triggers after scrying; scry 0 is no scry" do
      game = board do
        player("alice", mana_pool: { G: 2 }) do
          battlefield "Seer Acolyte"
          hand "Glimpse", "Glimpse Nothing"
          library "Forest", count: 4
        end
        player("bob")
      end
      cast(game, "Glimpse Nothing")
      resolve_all(game)
      expect(life(game)).to eq(20)
      cast(game, "Glimpse")
      resolve_all(game)
      expect(life(game)).to eq(21)
    end
  end

  describe "becomes_untapped (CR 603.2e)" do
    it "triggers when it untaps, not when it enters untapped" do
      game = board do
        player("alice") do
          battlefield "Spring Loaded", tapped: true
          graveyard "Spring Loaded"
        end
        player("bob")
      end
      engine = engine_of(game)
      engine.move!(ids_in(game, "alice", :graveyard).first, :battlefield, reason: "return")
      expect(game.state.pending_triggers).to be_empty
      engine.untap!(game.state.object(game.state.battlefield.find { game.state.object(it).tapped }))
      expect(pending_cards(game)).to eq(["spring_loaded"])
    end
  end

  describe "put_into from anywhere (CR 603.6c, 603.2c)" do
    it "one or more creature cards put into your graveyard: once per batch, that many" do
      game = board do
        player("alice", mana_pool: { G: 1 }) do
          battlefield "Bone Collector"
          hand "Grave Tide"
          library "Grizzly Bears", "Hill Giant", "Forest", "Forest"
        end
        player("bob")
      end
      cast(game, "Grave Tide")
      resolve_all(game)
      expect(life(game)).to eq(22)
    end

    it "`from` limits where the card came from; `controller: any` watches every player's cards" do
      game = board do
        player("alice") { battlefield "Exile Archivist", "Grizzly Bears" }
        player("bob") { graveyard "Hill Giant" }
      end
      engine = engine_of(game)
      engine.move!(obj_id(game, "Grizzly Bears"), :exile, reason: "exile")
      expect(game.state.pending_triggers).to be_empty
      engine.move!(ids_in(game, "bob", :graveyard).first, :exile, reason: "exile")
      expect(pending_cards(game)).to eq(["exile_archivist"])
    end
  end
end
