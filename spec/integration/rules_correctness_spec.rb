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
  let(:catalog) { catalog_with(chosen_shield, pinger, raise_dead) }

  def board(alice: [], bob: [], hand: [], their_hand: [], graveyard: [], active: "alice", mana: { R: 3 }, their_mana: {})
    build_game(catalog) do
      turn 3, active: active, step: :precombat_main
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
end
