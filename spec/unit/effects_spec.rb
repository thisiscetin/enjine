# frozen_string_literal: true

RSpec.describe "Effects and selectors applied directly (unit)" do
  let(:game) do
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Grizzly Bears", "Vessa, Rally Captain"
        library "Forest", count: 3
      end
      player("bob") do
        battlefield "Hill Giant", "Forest"
        hand "Island"
      end
    end
  end
  let(:engine) { game.instance_variable_get(:@engine) }
  let(:bears) { game.state.battlefield[0] }
  let(:vessa) { game.state.battlefield[1] }
  let(:giant) { game.state.battlefield[2] }
  let(:events) { [] }

  before { engine.instance_variable_set(:@emit, ->(e) { events << e }) }

  def effect(data, targets_count: 1)
    errors = []
    built = Enjine::Mechanics.build_entry(:effect, data, errors, "e", targets_count: targets_count)
    raise errors.join(", ") unless errors.empty?

    built
  end

  def ctx(targets = [], source: bears) = Enjine::Mechanics::EffectContext.new(0, source, nil, targets)

  it "resolves selectors: self, you, each_opponent, each with controller filters" do
    sel = ->(data) { Enjine::Mechanics::Selector.build(data, [], "s", targets_count: 1).resolve(engine, ctx(["player:bob"])) }
    expect(sel.call("self")).to eq([bears])
    expect(sel.call("you")).to eq(["player:alice"])
    expect(sel.call("each_opponent")).to eq(["player:bob"])
    expect(sel.call({ "target" => 0 })).to eq(["player:bob"])
    expect(sel.call({ "each" => "creature" })).to eq([bears, giant])
    expect(sel.call({ "each" => "creature", "controller" => "opponent" })).to eq([giant])
    expect(sel.call({ "each" => "player", "controller" => "you" })).to eq(["player:alice"])
    expect(sel.call({ "each" => "permanent", "controller" => "opponent" })).to eq(game.state.battlefield.last(2))
    expect(sel.call({ "each" => "creature_or_planeswalker", "controller" => "you" })).to eq([bears, vessa])
    gone = Enjine::Mechanics::Selector.build("self", [], "s", targets_count: 0).resolve(engine, ctx(source: "gone#1"))
    expect(gone).to eq([])
  end

  it "describes selectors" do
    texts = [{ "target" => 0 }, "self", "you", "each_opponent", { "each" => "creature", "controller" => "opponent" },
             { "each" => "planeswalker" }].map { Enjine::Mechanics::Selector.build(it, [], "s", targets_count: 1).to_s }
    expect(texts).to eq(["target #1", "itself", "you", "each opponent", "each creature an opponent controls",
                         "each planeswalker"])
  end

  it "filters players and opponents as targets" do
    expect(Enjine::Mechanics::Filters::Opponent.candidates(engine, 0)).to eq(["player:bob"])
    expect(Enjine::Mechanics::Filters::Player.match?(engine, "player:nobody", 0)).to be(false)
    expect(Enjine::Mechanics::Filters::Creature.match?(engine, "missing#1", 0)).to be(false)
    expect(Enjine::Mechanics::Filters::Spell.candidates(engine, 0)).to eq([])
  end

  it "loses life, draws, destroys, and ignores what isn't there" do
    effect({ "lose_life" => { "amount" => 2, "to" => "each_opponent" } }).apply(engine, ctx)
    expect(game.state.players[1].life).to eq(18)
    effect({ "draw" => { "amount" => 2, "to" => "each_opponent" } }).apply(engine, ctx)
    expect(game.state.players[1].drew_from_empty).to be(true) # bob's library is empty
    effect({ "destroy" => { "to" => { "target" => 0 } } }).apply(engine, ctx([giant]))
    expect(game.state.battlefield).not_to include(giant)
    effect({ "counter" => { "to" => { "target" => 0 } } }).apply(engine, ctx([bears])) # not on the stack: no-op
    expect(game.state.battlefield).to include(bears)
    effect({ "gain_life" => { "amount" => 0 } }).apply(engine, ctx)
    expect(events.grep(Enjine::Events::LifeChanged).size).to eq(1)
  end

  it "deals damage to creatures, planeswalkers and players; zero or missing targets do nothing" do
    effect({ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }).apply(engine, ctx([vessa]))
    expect(engine.loyalty(engine.object(vessa))).to eq(1)
    engine.deal_damage!(bears, "gone#1", 3)
    engine.deal_damage!(bears, giant, 0)
    expect(engine.object(giant).damage).to eq(0)
    engine.remove_counters!(engine.object(giant), "loyalty", 1) # nothing to remove
    expect(events.grep(Enjine::Events::CountersChanged).size).to eq(1)
    engine.add_counters!(engine.object(giant), "+1/+1", 0)
    expect(engine.object(giant).counters).to eq({})
  end

  it "describes effects and abilities" do
    expect(effect({ "deal_damage" => { "amount" => 3, "to" => { "target" => 0 } } }).to_s).to eq("deal damage 3 → target #1")
    expect(effect({ "destroy" => { "to" => { "target" => 0 } } }).to_s).to eq("destroy → target #1")
  end
end
