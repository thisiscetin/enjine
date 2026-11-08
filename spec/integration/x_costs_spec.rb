# frozen_string_literal: true

RSpec.describe "X costs (CR 107.3, 601.2b)" do
  # Pays whatever is left: mana from the pool first, otherwise the first untapped source.
  def pay_all(game)
    while game.pending_decision&.kind == "pay_cost"
      options = game.legal_options
      game.submit(options.find { it[:type] == "pay_mana" } || options.find { it[:type] == "activate_mana" })
    end
  end

  def board(hand: [], lands: 3, extra: [], pool: {})
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: pool) do
        hand.each { hand it }
        battlefield "Mountain", count: lands
        battlefield "Forest", count: 2
        extra.each { battlefield it }
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Grizzly Bears"
        library "Forest", count: 5
      end
    end
  end

  def life(game, who) = game.state.players[game.names.index(who)].life

  it "announces X before targets (601.2b), up to what the available mana can pay, and X adds to the cost" do
    game = board(hand: ["Flare Torrent"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    expect(game.pending_decision).to have_attributes(kind: "choose_x", details: { "max" => 4 })
    expect(game.legal_options).to eq((0..4).map { { type: "x", value: it } } + [{ type: "cancel" }])
    entry = game.submit(type: "x", value: 3)
    expect(entry.events.map(&:type)).to eq(["x_announced"])
    expect(game.pending_decision.kind).to eq("choose_target")
    game.submit(type: "target", target: "player:bob")
    expect(game.pending_decision.details["remaining"]).to eq("{3}{R}")
    pay_all(game)
    pass_both(game)
    expect(life(game, "bob")).to eq(17)
  end

  it "X = 0 is legal: the spell costs only its colored part (CR 107.3a)" do
    game = board(hand: ["Flare Torrent"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "x", value: 0)
    game.submit(type: "target", target: "player:bob")
    expect(game.pending_decision.details["remaining"]).to eq("{R}")
    pay_all(game)
    pass_both(game)
    expect(life(game, "bob")).to eq(20)
  end

  it "cancelling after announcing X rewinds the whole cast" do
    game = board(hand: ["Flare Torrent"])
    card = ids_in(game, "alice", :hand).first
    game.submit(type: "cast", object: card)
    game.submit(type: "x", value: 2)
    game.submit(type: "cancel")
    expect(ids_in(game, "alice", :hand)).to eq([card])
    expect(game.state.stack).to be_empty
  end

  it "keeps X on the stack across export/import and uses it on resolution" do
    game = board(hand: ["Flare Torrent"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "x", value: 2)
    game.submit(type: "target", target: "player:bob")
    pay_all(game)
    copy = Enjine::Game.import(game.export, catalog: game.catalog)
    expect(copy.state.object(copy.state.stack.first).x).to eq(2)
    pass_both(copy)
    expect(life(copy, "bob")).to eq(18)
  end

  it "an enters trigger of a permanent cast with X uses that X (CR 107.3m)" do
    game = board(hand: ["Brood Caller"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "x", value: 2)
    pay_all(game)
    pass_both(game) # the creature resolves; its trigger goes on the stack
    caller = game.state.battlefield.find { game.state.object(it).card == "brood_caller" }
    expect(game.state.object(caller).x).to eq(2)
    pass_both(game)
    saplings = game.state.battlefield.select { game.state.object(it).card.start_with?("sapling_token") }
    expect(saplings.size).to eq(2)
  end

  it "an activated ability with {X} in its cost announces X too (CR 107.3k)" do
    game = board(extra: ["Arc Lantern"])
    lantern = game.state.battlefield.find { game.state.object(it).card == "arc_lantern" }
    game.submit(type: "activate", object: lantern, ability: "printed:0")
    expect(game.pending_decision).to have_attributes(kind: "choose_x", details: { "max" => 5 })
    game.submit(type: "x", value: 2)
    bears = game.state.battlefield.find { game.state.object(it).card == "grizzly_bears" }
    game.submit(type: "target", target: bears)
    expect(game.pending_decision.details["remaining"]).to eq("{2}")
    pay_all(game)
    pass_both(game)
    expect(game.state.battlefield).not_to include(bears)
  end

  it "mana value treats X as 0 off the stack (CR 202.3e, 107.3g)" do
    cost = Enjine::Mana::Cost.parse("{X}{X}{W}{W}")
    expect([cost.x_symbols, cost.mana_value, cost.to_s]).to eq([2, 2, "{X}{X}{W}{W}"])
    expect(cost.with_x(3).to_s).to eq("{6}{W}{W}")
  end
end
