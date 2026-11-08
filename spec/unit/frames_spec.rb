# frozen_string_literal: true

RSpec.describe Enjine::Frames do
  def bolt_game
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Lightning Bolt"
        battlefield "Mountain"
        library "Forest", count: 3
      end
      player("bob") { library "Forest", count: 3 }
    end
  end

  def cast_bolt(game)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: "player:bob")
    game.submit(type: "activate_mana", object: game.state.battlefield.first, ability: mana_ref(game, game.state.battlefield.first))
    game.submit(type: "pay_mana", mana: "R")
  end

  it "raises on unknown frame types" do
    expect { described_class.fetch("warp") }.to raise_error(ArgumentError, /unknown frame type/)
  end

  it "validates that cast and resolve frames point at stack objects" do
    errors = []
    data = { "stack" => [] }
    described_class::Cast.validate({ "object" => "x#1" }, data, errors)
    described_class::Resolve.validate({ "object" => "x#1" }, data, errors)
    described_class::CombatDamage.validate({}, data, errors)
    expect(errors).to eq(["frames: cast object x#1 is not on the stack", "frames: resolving object x#1 is not on the stack"])
  end

  it "lets an effect pause resolution and resume it later, surviving export/import" do
    game = bolt_game
    cast_bolt(game)
    calls = 0
    pausing = Class.new do
      define_method(:run) do |engine, ctx, locals|
        calls += 1
        next :done.tap { engine.deal_damage!(ctx.source, "player:bob", 3) } if locals["asked"]

        locals["asked"] = true
        engine.ask!("kind" => "priority", "player" => 1) # stand-in for a real mid-resolution choice
        :wait
      end
    end.new
    fake_ability = Struct.new(:targets, :effects) do
      def targets_for(_chosen) = targets
      def effect_plan(_chosen) = effects.map { [it, 0, targets.size] }
    end.new([Enjine::Mechanics::Filters::AnyTarget], [pausing])
    allow(game.instance_variable_get(:@engine)).to receive(:resolving_ability).and_return(fake_ability)
    allow(Enjine::Frames::Resolve).to receive(:decisions).and_return(["priority"])
    pass_both(game)
    expect(game.state.frames.map { it["type"] }).to eq(["resolve"])
    expect(game.state.frames.last["locals"]).to eq("0" => { "asked" => true })
    expect(Enjine::Snapshot.validate(game.state.to_h, game.catalog)).to eq([])
    game.state.pending = nil
    game.instance_variable_get(:@engine).advance!
    expect(calls).to eq(2)
    expect(game.state.players[1].life).to eq(17)
    expect(game.state.frames).to be_empty
  end
end
