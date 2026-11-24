# frozen_string_literal: true

# Rules-correctness details with invented cards: sources of your choice (CR 609.7a-b), prevention follow-ups for
# damage that can't be prevented (CR 615.12), the affected player ordering damage replacement and prevention
# effects (CR 616.1), creatures put onto the battlefield attacking a planeswalker (CR 508.4) and copying a
# triggered ability that has left the stack (CR 707.10).
RSpec.describe "Rules-correctness details" do
  def creature(name, power, toughness, *abilities, keywords: [])
    { "name" => name, "mana_cost" => "{1}", "types" => ["creature"], "subtypes" => ["bear"], "power" => power,
      "toughness" => toughness, "keywords" => keywords, "abilities" => abilities }
  end

  def spell(name, *effects, targets: [], types: ["instant"])
    { "name" => name, "mana_cost" => "{R}", "types" => types,
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects } }] }
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, who) = game.state.players[game.names.index(who)].life

  let(:chosen_shield) do
    spell("Chosen Shield", { "prevent_damage" => { "to" => "you", "by" => "chosen_source",
                                                   "then" => [{ "gain_life" => { "amount" => 1 } }] } })
  end
  let(:pinger) do
    creature("Ping Bear", 1, 1, { "triggered" => { "when" => { "enters" => {} },
                                                   "effects" => [{ "deal_damage" => { "amount" => 2, "to" => "each_opponent" } }] } })
  end
  let(:raise_dead) do
    spell("Raise Again", { "return_to_hand" => { "to" => { "target" => 0 } } },
          targets: [{ "graveyard_card" => { "controller" => "opponent" } }], types: ["sorcery"])
  end
  let(:warden) do # prevents damage to its controller and gains that much life
    { "name" => "Warding Shrine", "mana_cost" => "{2}", "types" => ["enchantment"],
      "abilities" => [{ "prevent_damage" => { "to" => { "controller" => "you" },
                                              "then" => [{ "gain_life" => { "amount" => { "triggering" => "amount" } } }] } }] }
  end
  let(:mercy) do # prevents damage to its controller; they gain 1 life
    { "name" => "Mercy Shrine", "mana_cost" => "{2}", "types" => ["enchantment"],
      "abilities" => [{ "prevent_damage" => { "to" => { "controller" => "you" }, "then" => [{ "gain_life" => { "amount" => 1 } }] } }] }
  end
  let(:doubler) do
    { "name" => "Cruel Doubler", "mana_cost" => "{2}", "types" => ["enchantment"],
      "abilities" => [{ "damage_replacement" => { "by" => { "controller" => "you" }, "to" => { "controller" => "opponent" },
                                                  "multiply" => 2 } }] }
  end
  let(:shield3) { spell("Small Shield", { "prevent_damage" => { "to" => "you", "next" => 3 } }) }
  let(:unpreventable) { spell("Raw Shock", "damage_unpreventable", { "deal_damage" => { "amount" => 2, "to" => "each_opponent" } }) }
  let(:shock) { spell("Small Shock", { "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }, targets: ["any_target"]) }
  let(:brute) { creature("Brute", 2, 2) }
  let(:catalog) { catalog_with(chosen_shield, pinger, raise_dead, warden, mercy, doubler, shield3, unpreventable, shock, brute) }

  def board(alice: [], bob: [], hand: [], their_hand: [], graveyard: [], active: "alice", mana: { R: 3 }, their_mana: {},
            step: :precombat_main)
    build_game(catalog) do
      turn 3, active: active, step: step
      player("alice", mana_pool: mana) do
        battlefield(*alice) unless alice.empty?
        hand(*hand) unless hand.empty?
        graveyard(*graveyard) unless graveyard.empty?
        library "Forest", count: 8
      end
      player("bob", mana_pool: their_mana) do
        battlefield(*bob) unless bob.empty?
        hand(*their_hand) unless their_hand.empty?
        library "Forest", count: 8
      end
    end
  end

  # Passes priority (paying from the pool) and answers other decisions with `answers` or the first option.
  def resolve_all(game, answers = [])
    while game.state.stack.any? || game.state.pending_triggers.any? || game.pending_decision.kind != "priority"
      decision = game.pending_decision
      game.submit(case decision.kind
                  when "priority" then { type: "pass" }
                  when "pay_cost" then game.legal_options.find { it[:type] == "pay_mana" }
                  else answers.shift || game.legal_options.first
                  end)
    end
  end

  def submit_cast(game, card, player) = game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: player))

  describe "a source of your choice (CR 609.7a-b)" do
    it "can be an object a spell on the stack refers to, or an object in the command zone" do
      game = board(hand: ["Chosen Shield"], their_hand: ["Raise Again"], graveyard: ["Ping Bear"], active: "bob",
                   their_mana: { R: 1 })
      eng = engine(game)
      emblem = eng.create_emblem!(1, "ping_bear", "none")
      submit_cast(game, "Raise Again", "bob")
      game.submit(type: "target", target: obj_id(game, "Ping Bear", zone: :graveyard, player: "alice"))
      game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
      game.submit(type: "pass")
      submit_cast(game, "Chosen Shield", "alice")
      game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
      game.submit(type: "pass")
      game.submit(type: "pass")
      sources = game.legal_options.map { it[:object] }
      expect(sources).to include(obj_id(game, "Ping Bear", zone: :graveyard, player: "alice"), emblem.id,
                                 game.state.stack.last)
    end

    it "follows a chosen permanent spell onto the battlefield" do
      game = board(hand: ["Chosen Shield"], their_hand: ["Ping Bear"], active: "bob", their_mana: { G: 1 })
      submit_cast(game, "Ping Bear", "bob")
      game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
      game.submit(type: "pass")
      submit_cast(game, "Chosen Shield", "alice")
      resolve_all(game, [{ type: "source", object: game.state.stack.last }])
      expect(life(game, "alice")).to eq(21) # the Bear's damage is prevented, then 1 life
    end
  end

  describe "damage that can't be prevented (CR 615.12)" do
    it "still gets a prevention effect's additional effects, preventing nothing" do
      game = board(hand: ["Raw Shock"], bob: ["Mercy Shrine"])
      cast = obj_id(game, "Raw Shock", zone: :hand, player: "alice")
      game.submit(type: "cast", object: cast)
      resolve_all(game)
      expect(life(game, "bob")).to eq(19) # dealt, then gains 1
    end

    it "doesn't use up a shield" do
      game = board(hand: ["Small Shield"])
      submit_cast(game, "Small Shield", "alice")
      resolve_all(game)
      eng = engine(game)
      eng.add_continuous_effect!("damage_unpreventable", Enjine::Mechanics::EffectContext.new(0, nil, nil, [], []), [], {})
      expect(eng.deal_damage!(nil, "player:alice", 2)).to eq(2)
      expect(game.state.effects.find { it["kind"] == "prevent_damage" }["remaining"]).to eq(3)
    end
  end

  describe "the affected player orders replacement and prevention effects (CR 616.1)" do
    it "asks when the order changes the result, and applies the chosen order" do
      game = board(hand: ["Small Shield"], their_hand: ["Small Shock"], bob: ["Cruel Doubler"], their_mana: { R: 1 })
      submit_cast(game, "Small Shield", "alice")
      resolve_all(game)
      game.submit(type: "pass") # bob gets priority in alice's turn
      submit_cast(game, "Small Shock", "bob")
      game.submit(type: "target", target: "player:alice")
      game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
      game.submit(type: "pass")
      game.submit(type: "pass") until game.pending_decision.kind != "priority"
      expect(game.pending_decision.kind).to eq("damage_order")
      expect(game.pending_decision.player).to eq("alice")
      expect(game.legal_options.map { it[:amount] }).to contain_exactly(0, 1) # prevent 3 of 2, or of 4
      game.submit(game.legal_options.find { it[:amount].zero? })
      resolve_all(game)
      expect(life(game, "alice")).to eq(20)
      expect(game.state.effects.find { it["kind"] == "prevent_damage" }["remaining"]).to eq(1)
    end

    it "keeps the default order without asking when the order can't matter" do
      game = board(alice: ["Cruel Doubler", "Cruel Doubler"], hand: ["Small Shock"])
      submit_cast(game, "Small Shock", "alice")
      game.submit(type: "target", target: "player:bob")
      game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
      game.submit(type: "pass") while game.state.stack.any? && game.pending_decision.kind == "priority"
      expect(game.pending_decision.kind).to eq("priority")
      expect(life(game, "bob")).to eq(12) # doubled twice
    end

    it "asks for combat damage too, in the combat damage step" do
      game = board(alice: ["Brute", "Cruel Doubler"], bob: ["Warding Shrine"], step: :beginning_of_combat)
      2.times { game.submit(type: "pass") }
      game.submit(type: "attack", object: obj_id(game, "Brute"), target: "player:bob")
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
      game.submit(type: "pass") until game.pending_decision.kind != "priority" || game.step == :end_of_combat
      expect(game.pending_decision.kind).to eq("damage_order")
      expect(game.pending_decision.player).to eq("bob")
      game.submit(game.legal_options.max_by { it[:steps].first.include?("modify") ? 1 : 0 }) # double, then prevent 4
      game.submit(type: "pass") until game.step == :end_of_combat || game.pending_decision.kind != "priority"
      expect(life(game, "bob")).to eq(24)
    end
  end
end
