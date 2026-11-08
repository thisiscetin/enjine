# frozen_string_literal: true

RSpec.describe "Mechanics::Amount and Mechanics::Condition" do
  let(:game) do
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice", life: 12) do
        hand "Forest", "Island"
        battlefield "Hill Giant", "Grizzly Bears"
      end
      player("bob") { battlefield "Savannah Lions" }
    end
  end
  let(:engine) { game.instance_variable_get(:@engine) }
  let(:ctx) { Enjine::Mechanics::EffectContext.new(0, game.state.battlefield[0], nil, [game.state.battlefield[0]]) }

  def amount(data)
    errors = []
    built = Enjine::Mechanics::Amount.build(data, errors, "a", targets_count: 1)
    raise errors.join(", ") unless errors.empty?

    built
  end

  def condition(data)
    errors = []
    built = Enjine::Mechanics::Condition.build(data, errors, "c", targets_count: 1)
    raise errors.join(", ") unless errors.empty?

    built
  end

  it "computes every kind of amount" do
    expect(amount(4).value(engine, ctx)).to eq(4)
    expect(amount({ "count" => { "each" => "creature" } }).value(engine, ctx)).to eq(3)
    expect(amount({ "power" => "self" }).value(engine, ctx)).to eq(3)
    expect(amount({ "toughness" => { "target" => 0 } }).value(engine, ctx)).to eq(3)
    expect(amount({ "hand_size" => "you" }).value(engine, ctx)).to eq(2)
    expect(amount({ "life" => "each_opponent" }).value(engine, ctx)).to eq(20)
    expect(amount({ "power" => { "target" => 0 } }).value(engine, ctx.to_h.merge(targets: ["gone#1"]).then do
      Enjine::Mechanics::EffectContext.new(*it.values)
    end)).to eq(0)
    expect(amount({ "count" => "you" }).to_s).to eq("the count of you")
    expect(amount(2).to_s).to eq("2")
  end

  it "rejects malformed amounts" do
    errors = []
    Enjine::Mechanics::Amount.build(-1, errors, "a", targets_count: 0)
    Enjine::Mechanics::Amount.build({ "count" => "you", "power" => "self" }, errors, "b", targets_count: 0)
    expect(errors.size).to eq(2)
  end

  it "evaluates conditions and their combinations" do
    yes = condition({ "life" => "you", "at_most" => 12 })
    no = condition({ "hand_size" => "you", "at_least" => 5 })
    expect(yes.true?(engine, ctx)).to be(true)
    expect(no.true?(engine, ctx)).to be(false)
    expect(condition({ "not" => { "hand_size" => "you", "at_least" => 5 } }).true?(engine, ctx)).to be(true)
    expect(condition({ "all" => [{ "your_turn" => true }, { "life" => "you", "at_least" => 1 }] }).true?(engine, ctx)).to be(true)
    expect(condition({ "any" => [{ "your_turn" => false }, { "hand_size" => "you", "at_least" => 9 }] }).true?(engine, ctx)).to be(false)
    expect(condition({ "controls" => { "each" => "creature", "controller" => "opponent" }, "at_least" => 1, "at_most" => 1 })
      .true?(engine, ctx)).to be(true)
    expect([condition({ "your_turn" => false }), condition({ "not" => { "your_turn" => true } }),
            condition({ "any" => [{ "your_turn" => true }, { "your_turn" => false }] })].map(&:to_s))
      .to eq(["it's not your turn", "not (it's your turn)", "it's your turn or it's not your turn"])
    expect(yes.to_s).to eq("the life of you is at most 12")
  end

  it "rejects malformed conditions" do
    errors = []
    Enjine::Mechanics::Condition.build("sunny", errors, "c")
    Enjine::Mechanics::Condition.build({ "life" => "you", "at_least" => "lots" }, errors, "d")
    expect(errors).to include(a_string_matching(/must be a condition object/), a_string_matching(/at_least: must be an integer/))
  end
end
