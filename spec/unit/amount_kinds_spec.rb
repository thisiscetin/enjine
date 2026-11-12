# frozen_string_literal: true

RSpec.describe "Amount kinds, condition forms and selectors (CR 107.1a, 205.3m, 608.2h)" do
  let(:game) do
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        graveyard "Forest", count: 3
        battlefield "Hill Giant", counters: { "+1/+1" => 2, "stun" => 1 }
        battlefield "Grizzly Bears", "Savannah Lions"
      end
      player("bob") { battlefield "Craw Wurm" }
    end
  end
  let(:engine) { game.instance_variable_get(:@engine) }
  let(:giant) { obj_id(game, "Hill Giant") }
  let(:ctx) { Enjine::Mechanics::EffectContext.new(0, giant, nil, [obj_id(game, "Craw Wurm")], [[giant]], [5]) }

  def built(kind, data, results: 1)
    errors = []
    klass = kind == :amount ? Enjine::Mechanics::Amount : Enjine::Mechanics::Condition
    value = klass.build(data, errors, "x", targets_count: 1, results_count: results)
    raise errors.join(", ") unless errors.empty?

    value
  end

  def amount(data) = built(:amount, data).value(engine, ctx)
  def holds?(data) = built(:condition, data).true?(engine, ctx)

  it "computes the new amount kinds" do
    yours = { "each" => "creature", "controller" => "you" }
    expect(amount({ "greatest_power" => yours })).to eq(5)
    expect(amount({ "greatest_power" => { "each" => "planeswalker" } })).to eq(0)
    expect(amount({ "graveyard_size" => "you" })).to eq(3)
    expect(amount({ "library_size" => "you" })).to eq(0)
    expect(amount({ "card_types" => { "each" => { "graveyard_card" => {} }, "controller" => "you" } })).to eq(1) # three Forests
    expect(amount({ "card_types" => yours })).to eq(1)
    expect(amount({ "greatest_mana_value" => yours })).to eq(4) # Hill Giant {3}{R}
    expect(amount({ "greatest_mana_value" => { "each" => "planeswalker" } })).to eq(0)
    expect(amount({ "distinct_types" => yours })).to eq(3) # giant, bear, cat (CR 205.3m)
    expect(amount({ "distinct_types" => { "each" => "land" } })).to eq(0)
    expect(amount({ "counters" => { "of" => "self" } })).to eq(3)
    expect(amount({ "counters" => { "of" => "self", "kind" => "+1/+1" } })).to eq(2)
    expect(amount({ "count" => { "result" => 0 } })).to eq(1)
    expect(amount({ "this_way" => 0 })).to eq(5)
    expect(amount({ "times" => [{ "count" => yours }, -1] })).to eq(-3)
    expect(amount({ "plus" => [1, { "life_gained_this_turn" => "you" }] })).to eq(1)
    expect(amount({ "divide" => [{ "count" => yours }, 2] })).to eq(1) # rounds down (CR 107.1a)
    expect(amount({ "toughness" => { "target" => 0 } })).to eq(4)
  end

  it "uses the source's last known power and counters once it has left (CR 608.2h)" do
    stack = engine.create_object("hill_giant", 0, :stack)
    stack.kind = "ability"
    stack.memory = { "source_lki" => { "power" => 4, "toughness" => 5, "counters" => { "charge" => 2 } } }
    gone = Enjine::Mechanics::EffectContext.new(0, "hill_giant#999", stack.id, [])
    expect(built(:amount, { "power" => "self" }).value(engine, gone)).to eq(4)
    expect(built(:amount, { "counters" => { "of" => "self", "kind" => "charge" } }).value(engine, gone)).to eq(2)
    expect(built(:amount, { "power" => { "each" => "planeswalker" } }).value(engine, gone)).to eq(0)
    nothing = Enjine::Mechanics::EffectContext.new(0, "hill_giant#999", nil, [])
    expect(built(:amount, { "toughness" => "self" }).value(engine, nothing)).to eq(0)
    expect(built(:amount, { "counters" => { "of" => "self" } }).value(engine, nothing)).to eq(0)
  end

  it "checks the new condition forms" do
    expect(holds?({ "amount" => { "power" => { "each" => "creature", "controller" => "you" } }, "at_least" => 9 })).to be(true)
    expect(holds?({ "amount" => { "count" => { "result" => 0 } }, "at_most" => 0 })).to be(false)
    expect(holds?({ "source" => "creature" })).to be(true)
    expect(holds?({ "source" => "land" })).to be(false)
    expect(holds?({ "attacked_this_turn" => true })).to be(false)
    expect(holds?({ "attacked_this_turn" => false })).to be(true)
    expect(holds?({ "nth_resolution" => 1 })).to be(false) # no resolving ability
    expect(built(:condition, { "attacked_this_turn" => false }).to_s).to eq("it didn't attack this turn")
    expect(built(:condition, { "nth_resolution" => 2 }).to_s).to eq("this is resolution number 2 of this ability this turn")
    expect(built(:condition, { "source" => "creature" }).to_s).to start_with("it's a ")
    expect(built(:condition, { "amount" => 3, "at_least" => 1, "at_most" => 4 }).to_s).to eq("3 is at least 1 and at most 4")
  end

  it "describes amounts" do
    expect(built(:amount, { "times" => ["x", -1] }).to_s).to eq("X × -1")
    expect(built(:amount, { "counters" => { "of" => "self", "kind" => "charge" } }).to_s).to eq("the number of charge counters on itself")
    expect(built(:amount, { "this_way" => 0 }).to_s).to eq("the amount from effect #1")
    expect(built(:amount, { "spells_cast_this_turn" => {} }).to_s).to eq("the number of spells cast this turn by you")
    expect(built(:amount, { "died_this_turn" => {} }).to_s).to start_with("the number of ")
  end

  it "names the controller of a target, or its last known controller (CR 608.2h)" do
    selector = Enjine::Mechanics::Selector.build({ "controller_of" => { "target" => 0 } }, [], "s", targets_count: 1)
    expect(selector.resolve(engine, ctx)).to eq(["player:bob"])
    expect(selector.to_s).to eq("the controller of target #1")
    gone = Enjine::Mechanics::EffectContext.new(0, nil, nil, ["craw_wurm#999"])
    expect(selector.resolve(engine, gone)).to eq([])
  end

  it "reports malformed amounts, conditions and selectors with paths" do
    errors = []
    build = ->(data, path) { Enjine::Mechanics::Amount.build(data, errors, path, targets_count: 0) }
    build.call({ "times" => [1] }, "a")
    build.call({ "divide" => [3, 0] }, "b")
    build.call({ "this_way" => 2 }, "c")
    build.call({ "counters" => { "kind" => "+1/+1" } }, "d")
    build.call({ "counters" => { "of" => "self", "kind" => "Bad Name!" } }, "e")
    Enjine::Mechanics::Condition.build({ "nth_resolution" => 0 }, errors, "f")
    Enjine::Mechanics::Selector.build({ "controller_of" => { "target" => 3 }, "x" => 1 }, errors, "g", targets_count: 1)
    expect(errors).to include("a.times: must be a list of two amounts", "b.divide[1]: must be a positive integer",
                              "c.this_way: must refer to one of the 0 earlier effects", "d.counters.of: required",
                              "f.nth_resolution: must be a positive integer", "g: unknown parameter \"x\"",
                              "g.controller_of.target: must refer to one of the 1 declared targets")
    expect(errors.grep(/\Ae\.counters\.kind: /).size).to eq(1)
  end
end
