# frozen_string_literal: true

RSpec.describe "Delayed triggers, optional effects and results: card data validation (unit)" do
  def errors_for(effects, targets: [])
    card = { "name" => "Probe Card", "mana_cost" => "{R}", "types" => ["instant"],
             "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? } }] }
    Enjine::CardDefinition.from_h(card)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  let(:base) { "abilities[0].spell.effects" }

  it "accepts {\"result\": n} only for an earlier effect of the same list (CR 400.7j)" do
    expect(errors_for([{ "exile" => { "to" => { "result" => 0 } } }]))
      .to eq(["#{base}[0].exile.to.result: must refer to one of the 0 earlier effects"])
    expect(errors_for([{ "draw" => { "amount" => 1 } }, { "exile" => { "to" => { "result" => 1, "x" => 1 } } }]))
      .to eq(["#{base}[1].exile.to: unknown parameter \"x\"",
              "#{base}[1].exile.to.result: must refer to one of the 1 earlier effects"])
    expect(errors_for([{ "draw" => { "amount" => 1 } }, { "exile" => { "to" => { "result" => 0 } } }])).to eq([])
  end

  it "checks may: needs effects; nested lists see the parent's earlier results (CR 118.12)" do
    expect(errors_for([{ "may" => {} }])).to eq(["#{base}[0].may.effects: needs at least one effect"])
    expect(errors_for([{ "may" => { "effects" => [{ "draw" => { "amount" => 1 } }],
                                    "then" => [{ "exile" => { "to" => { "result" => 0 } } }] } }]))
      .to eq(["#{base}[0].may.then[0].exile.to.result: must refer to one of the 0 earlier effects"])
    expect(errors_for([{ "may" => { "effects" => [{ "draw" => { "amount" => 1 } }], "else" => [] } }]))
      .to eq(["#{base}[0].may: unknown parameter \"else\""])
  end

  it "checks delayed_trigger: needs a trigger condition and effects (CR 603.7)" do
    expect(errors_for([{ "delayed_trigger" => {} }]))
      .to eq(["#{base}[0].delayed_trigger.when: required", "#{base}[0].delayed_trigger.effects: needs at least one effect"])
    expect(errors_for([{ "delayed_trigger" => { "when" => { "teatime" => {} }, "effects" => [{ "draw" => { "amount" => 1 } }] } }]).first)
      .to start_with("#{base}[0].delayed_trigger.when: unknown trigger \"teatime\"")
  end

  it "checks return_to_battlefield's under and the was_cast condition" do
    expect(errors_for([{ "draw" => { "amount" => 1 } },
                       { "return_to_battlefield" => { "to" => { "result" => 0 }, "under" => "anyone" } }]))
      .to eq(["#{base}[1].return_to_battlefield.under: must be one of owner, you"])
    expect(errors_for([{ "draw" => { "amount" => 1, "if" => { "cast_by" => "you" } } }]))
      .to eq(["#{base}[0].draw.if: unknown condition (use controls, life, hand_size, your_turn, was_cast, not, all, any)"])
  end

  it "addresses delayed abilities by path and registers tokens nested in them" do
    token = { "name" => "Probe Drone", "types" => ["artifact"] }
    card = Enjine::CardDefinition.from_h(
      "name" => "Probe Card", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "effects" => [
        { "may" => { "effects" => [{ "delayed_trigger" => { "when" => { "step_begins" => { "step" => "upkeep" } },
                                                            "effects" => [{ "create_token" => { "token" => token } }] } }] } }
      ] } }]
    )
    ref = "delayed:abilities[0].spell.effects[0].may.effects[0].delayed_trigger"
    expect(card.ability(ref).trigger.to_s).to eq("At the beginning of your upkeep")
    expect(card.token_definitions.map(&:name)).to eq(["Probe Drone"])
    expect(card.all_effects.map { it.class.primitive_name }).to eq(%w[may delayed_trigger create_token])
    expect(card.all_effects.first.to_s).to start_with("you may: delayed: At the beginning of your upkeep")
  end

  it "describes the new effects and selector" do
    build = lambda do |data|
      errors = []
      Enjine::Mechanics.build_entry(:effect, data, errors, "e", targets_count: 0, results_count: 1).tap do
        raise errors.join(", ") unless errors.empty?
      end
    end
    expect(build.call({ "return_to_battlefield" => { "to" => { "result" => 0 }, "tapped" => true, "under" => "you" } }).to_s)
      .to eq("return to the battlefield tapped under your control → the object(s) from effect #1")
    expect(build.call({ "sacrifice" => { "to" => { "result" => 0 } } }).to_s).to eq("sacrifice → the object(s) from effect #1")
    may = build.call({ "may" => { "effects" => [{ "draw" => { "amount" => 1 } }], "then" => [{ "gain_life" => { "amount" => 1 } }],
                                  "otherwise" => [{ "lose_life" => { "amount" => 1, "to" => "you" } }] } })
    expect(may.to_s).to eq("you may: draw 1 → you — if you do: gain life 1 → you — if you don't: lose life 1 → you")
  end

  it "returns only permanent cards still in exile or a graveyard (CR 400.4a, 603.7c)" do
    game = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        graveyard "Lightning Bolt", "Grizzly Bears"
        hand "Hill Giant"
      end
      player("bob")
    end
    engine = game.instance_variable_get(:@engine)
    effect = Enjine::Mechanics.build_entry(:effect, { "return_to_battlefield" => { "to" => { "result" => 0 } } }, [], "e",
                                           results_count: 1)
    refs = ids_in(game, "alice", :graveyard) + ids_in(game, "alice", :hand) + ["gone#99"]
    effect.apply(engine, Enjine::Mechanics::EffectContext.new(0, nil, nil, [], [refs]))
    expect(game.state.battlefield.map { game.state.object(it).card }).to eq(["grizzly_bears"])
    expect(ids_in(game, "alice", :graveyard).map { game.state.object(it).card }).to eq(["lightning_bolt"])
  end

  it "may: skips without asking when its condition is false; yes needs something to sacrifice (CR 118.3)" do
    game = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") { battlefield "Grizzly Bears" }
      player("bob") { battlefield "Hill Giant" }
    end
    engine = game.instance_variable_get(:@engine)
    build = ->(data) { Enjine::Mechanics.build_entry(:effect, data, [], "e") }
    sacrifice = { "sacrifice" => { "to" => { "each" => "creature", "controller" => "you" } } }
    ctx = ->(controller) { Enjine::Mechanics::EffectContext.new(controller, nil, nil, [], []) }
    expect(build.call({ "may" => { "effects" => [sacrifice], "if" => { "your_turn" => false } } }).run(engine, ctx.call(0), {}))
      .to eq(:done)
    expect(game.state.pending["kind"]).to eq("priority")
    may = build.call({ "may" => { "effects" => [sacrifice] } })
    expect(may.run(engine, ctx.call(0), {})).to eq(:wait)
    expect(game.state.pending["choices"]).to eq([{ "type" => "yes" }, { "type" => "no" }])
    game.state.battlefield.delete_at(0) && game.state.objects.delete(game.state.objects.keys.first) # alice has no creature
    expect(may.run(engine, ctx.call(0), {})).to eq(:wait)
    expect(game.state.pending["choices"]).to eq([{ "type" => "no" }])
  end

  it "validates delayed triggers and object memory in snapshots" do
    game = build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") { battlefield "Forest" }
      player("bob")
    end
    data = game.state.to_h
    data["objects"].first["memory"] = []
    data["delayed_triggers"] = [{ "controller" => 2, "card" => "forest", "ability" => "printed:9", "results" => {} }, 5]
    expect(Enjine::Snapshot.validate(data, game.catalog)).to include(
      "objects[0].memory: must be an object"
    )
    data["objects"].first["memory"] = {}
    expect(Enjine::Snapshot.validate(data, game.catalog)).to eq(
      ["delayed_triggers[0].controller: must be 0 or 1", "delayed_triggers[0].results: must be a list",
       "delayed_triggers[0]: \"forest\" has no delayed ability \"printed:9\"", "delayed_triggers[1]: must be an object"]
    )
    data["delayed_triggers"] = {}
    expect(Enjine::Snapshot.validate(data, game.catalog)).to eq(["delayed_triggers: must be a list"])
  end
end
