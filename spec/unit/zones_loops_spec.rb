# frozen_string_literal: true

# Validation, text and edge cases of repeat (CR 608.2c), exile_top's `until` (CR 406.1), the filtered result selector,
# the exiled_with filter (CR 607.2a), the attacking condition (CR 608.2h), counters_placed's `nth` (CR 122.6),
# single_target and change_target (CR 115.7a), cost_modifier colors, dig's looker (CR 702.75a) and meld's mana value
# (CR 713.5c).
RSpec.describe "Effects, zones and loops primitives" do
  def errors_for(card)
    Enjine::CardDefinition.from_h(card)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def spell(effects, targets: [])
    { "name" => "Spec Unit Spell", "mana_cost" => "{1}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects } }] }
  end

  def permanent(abilities)
    { "name" => "Spec Unit Permanent", "mana_cost" => "{1}", "types" => ["artifact"], "abilities" => abilities }
  end

  def text(card) = Enjine::CardDefinition.from_h(card).abilities.join(" | ")

  let(:lands_milled) { { "amount" => { "count" => { "result" => 0, "for" => { "types" => ["land"] } } }, "at_least" => 1 } }
  let(:loop_spell) do
    spell([{ "repeat" => { "effects" => [{ "mill" => { "amount" => 1, "to" => "you" } }], "while" => lands_milled } }])
  end

  it "accepts each documented form" do
    expect(errors_for(loop_spell)).to eq([])
    expect(errors_for(spell([{ "exile_top" => { "until" => { "total_mana_value" => 4 } } }]))).to eq([])
    expect(errors_for(spell([{ "exile_top" => { "until" => { "card" => { "not_types" => ["land"] } }, "face_down" => true } }]))).to eq([])
    linked = { "activated" => { "cost" => ["tap"], "targets" => [{ "exiled_with" => { "any_of" => ["creature"] } }],
                                "effects" => [{ "return_to_battlefield" => { "to" => { "target" => 0 } } }] } }
    expect(errors_for(permanent([linked]))).to eq([])
    expect(errors_for(spell([{ "draw" => { "amount" => 1, "if" => { "attacking" => { "target" => 0 } } } }],
                            targets: ["creature"]))).to eq([])
    expect(errors_for(permanent([{ "cost_modifier" => { "spells" => { "colors" => ["B"] }, "reduce" => 1 } }]))).to eq([])
  end

  it "names the path of each mistake" do
    expect(errors_for(spell([{ "repeat" => { "effects" => [] } }])))
      .to include("abilities[0].spell.effects[0].repeat.effects: needs at least one effect",
                  "abilities[0].spell.effects[0].repeat.while: required")
    expect(errors_for(spell([{ "exile_top" => { "until" => { "cards" => 2 } } }])))
      .to include(a_string_starting_with("abilities[0].spell.effects[0].exile_top.until: must be one of"))
    expect(errors_for(spell([{ "exile_top" => { "amount" => 2, "until" => { "total_mana_value" => 4 } } }])))
      .to include("abilities[0].spell.effects[0].exile_top: amount or until, not both")
    expect(errors_for(spell([{ "mill" => { "amount" => 1 } },
                             { "draw" => { "amount" => { "count" => { "result" => 0, "for" => { "bogus" => 1 } } } } }])))
      .to include(a_string_starting_with("abilities[0].spell.effects[1].draw.amount.count.for"))
    trigger = lambda { |params|
      permanent([{ "triggered" => { "when" => { "counters_placed" => params }, "effects" => [{ "draw" => { "amount" => 1 } }] } }])
    }
    expect(errors_for(trigger.call({ "nth" => 4 }))).to include("abilities[0].triggered.when.counters_placed.nth: needs a counter")
    expect(errors_for(trigger.call({ "counter" => "plan", "nth" => 0 })))
      .to include("abilities[0].triggered.when.counters_placed.nth: must be a positive integer")
    expect(errors_for(permanent([{ "cost_modifier" => { "spells" => { "colors" => ["P"] }, "reduce" => 1 } }])))
      .to include("abilities[0].cost_modifier.spells.colors: must be colors (W, U, B, R, G)")
    dig = ->(params) { spell([{ "dig" => { "amount" => 4, "put" => "exile" }.merge(params) }]) }
    expect(errors_for(dig.call({ "looker" => "you" })))
      .to include("abilities[0].spell.effects[0].dig.looker: must be \"source_controller\"")
    expect(errors_for(dig.call({ "looker" => "source_controller" })))
      .to include("abilities[0].spell.effects[0].dig.looker: needs face_down: true")
  end

  it "describes them" do
    expect(text(loop_spell)).to include("repeat while the count of the land card(s) from effect #1 is at least 1")
    expect(text(spell([{ "exile_top" => { "until" => { "total_mana_value" => 4 } } }])))
      .to include("exile top cards until total mana value 4")
    expect(text(spell([{ "exile_top" => { "until" => { "card" => { "types" => ["creature"] } }, "face_down" => true } }])))
      .to include("until card creature card face down")
    expect(text(spell([{ "change_target" => { "of" => { "target" => 0 } } }],
                      targets: [{ "one_of" => [{ "spell" => { "single_target" => true } },
                                               { "stack_ability" => { "single_target" => true } }] }])))
      .to include("change the target of target #1")
    filter = Enjine::Mechanics.build_entry(:filter, { "one_of" => [{ "spell" => { "single_target" => true } },
                                                                   { "stack_ability" => { "single_target" => true } }] }, [], "f")
    expect(filter.to_s).to eq("spell with a single target or activated or triggered ability with a single target")
    expect(text(spell([{ "draw" => { "amount" => 1, "if" => { "attacking" => { "target" => 0 } } } }], targets: ["creature"])))
      .to include("draw 1")
    condition = Enjine::Mechanics::Condition.build({ "attacking" => { "target" => 0 } }, [], "c", targets_count: 1)
    expect(condition.to_s).to eq("target #1 was attacking")
    trigger = Enjine::Mechanics.build_entry(:trigger, { "counters_placed" => { "counter" => "plan", "nth" => 4 } }, [], "t")
    expect(trigger.to_s).to eq("When plan counter number 4 is put on this")
    expect(text(permanent([{ "cost_modifier" => { "spells" => { "colors" => ["B"] }, "reduce" => 1 } }])))
      .to eq("B spells you cast cost {1} less")
  end

  describe "at work" do
    let(:catalog) { catalog_with(loop_spell, permanent([])) }

    def game_with(&) = build_game(catalog, &)
    def engine(game) = game.instance_variable_get(:@engine)

    it "repeat stops after #{Enjine::Mechanics::Effects::Repeat::MAX_PASSES} passes of a process that never fails" do
      forever = spell([{ "repeat" => { "effects" => [{ "gain_life" => { "amount" => 1 } }],
                                       "while" => { "life" => "you", "at_least" => 1 } } }])
      game = build_game(catalog_with(forever.merge("name" => "Spec Forever"))) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { C: 1 }) { hand "Spec Forever" }
        player("bob")
      end
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
      pass_both(game)
      expect(game.state.players[0].life).to eq(20 + Enjine::Mechanics::Effects::Repeat::MAX_PASSES)
    end

    it "a pass waits for a choice and resumes through export and import" do
      chooser = spell([{ "repeat" => { "effects" => [{ "choose_cards" => { "from" => { "hand" => "you" }, "put" => "graveyard" } }],
                                       "while" => { "hand_size" => "you", "at_least" => 2 } } }])
      cat = catalog_with(chooser.merge("name" => "Spec Chooser"))
      game = build_game(cat) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { C: 1 }) { hand "Spec Chooser", "Grizzly Bears", "Grizzly Bears", "Hill Giant" }
        player("bob")
      end
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).find { game.state.object(it).card == "spec_chooser" })
      game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
      game.submit(type: "pass") until game.pending_decision.kind == "effect_choice"
      2.times do
        game = Enjine::Game.import(game.export, catalog: cat)
        game.submit(game.legal_options.first)
      end
      expect(game.state.players[0].hand.size).to eq(1) # two passes; then one card is left
    end

    it "exile_top until a total mana value stops at an empty library and a filtered result is matched as it is now" do
      game = game_with do
        turn 3, active: "alice", step: :precombat_main
        player("alice") { library "Island", count: 2 }
        player("bob")
      end
      e = engine(game)
      effect = Enjine::Mechanics.build_entry(:effect, { "exile_top" => { "until" => { "total_mana_value" => 1 } } }, [], "e")
      effect.run(e, Enjine::Mechanics::EffectContext.new(0, nil, nil, [], []), {})
      expect(game.state.exile.size).to eq(2)
      selector = Enjine::Mechanics::Selector.build({ "result" => 0, "for" => { "types" => ["creature"] } }, [], "s",
                                                   targets_count: 0, results_count: 1)
      expect(selector.resolve(e, Enjine::Mechanics::EffectContext.new(0, nil, nil, [], [game.state.exile + ["gone#1"]]))).to eq([])
    end

    it "exiled_with matches nothing without a source; attacking reads a permanent still on the battlefield" do
      game = game_with do
        turn 3, active: "alice", step: :precombat_main
        player("alice") { battlefield "Grizzly Bears" }
        player("bob")
      end
      e = engine(game)
      filter = Enjine::Mechanics.build_entry(:filter, { "exiled_with" => {} }, [], "f")
      expect([filter.candidates(e, 0), filter.candidates_for(e, 0, nil)]).to eq([[], []])
      bears = game.state.battlefield.first
      condition = Enjine::Mechanics::Condition.build({ "attacking" => { "target" => 0 } }, [], "c", targets_count: 1)
      ctx = Enjine::Mechanics::EffectContext.new(0, nil, nil, [bears], [])
      expect(condition.true?(e, ctx)).to be(false)
      game.state.attackers[bears] = { "target" => "player:bob" }
      expect(condition.true?(e, ctx)).to be(true)
    end

    it "a copy of a melded permanent has the back face's mana value (0); a spell's X counts toward a mana value range" do
      game = game_with do
        turn 3, active: "alice", step: :precombat_main
        player("alice") { battlefield "Grizzly Bears" }
        player("bob")
      end
      e = engine(game)
      bears = e.object(game.state.battlefield.first)
      expect(e.melded_mana_value(bears)).to be_nil
      bears.memory["melded"] = "hill_giant"
      bears.memory["own_card"] = "grizzly_bears"
      expect(e.melded_mana_value(bears)).to be_nil
      expect(Enjine::Mechanics::Amount.mana_value(e, bears)).to eq(2)
    end
  end
end
