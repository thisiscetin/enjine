# frozen_string_literal: true

RSpec.describe "Mana from spells and triggers (CR 106.4, 608.2d) and sunburst (CR 702.44)" do
  def pay_all(game)
    while game.pending_decision&.kind == "pay_cost"
      options = game.legal_options
      game.submit(options.find { it[:type] == "pay_mana" } || options.find { it[:type] == "activate_mana" })
    end
  end

  def pool(game, who) = game.state.players[game.names.index(who)].mana_pool.select { |_, n| n.positive? }

  def board(hand:, lands:)
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand.each { hand it }
        lands.each { battlefield it }
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
  end

  it "a resolving spell adds fixed mana to its controller's pool" do
    game = board(hand: ["Ember Surge"], lands: %w[Mountain Mountain])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay_all(game)
    pass_both(game)
    expect(pool(game, "alice")).to eq(R: 3)
  end

  it "an enters trigger asks for one color, then adds two mana of it (CR 608.2d)" do
    game = board(hand: ["Prism Calf"], lands: %w[Forest Forest Forest])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay_all(game)
    pass_both(game) # creature resolves, trigger goes on the stack
    pass_both(game)
    expect(game.pending_decision.kind).to eq("effect_choice")
    expect(game.legal_options).to eq(%w[W U B R G].map { { type: "color", color: it } })
    game.submit(type: "color", color: "U")
    expect(pool(game, "alice")).to eq(U: 2)
  end

  it "each mana can be chosen separately with color: any" do
    data = { "name" => "Splinter Prism", "mana_cost" => "{1}", "types" => ["instant"],
             "abilities" => [{ "spell" => { "effects" => [{ "add_mana" => { "amount" => 2, "color" => "any" } }] } }] }
    game = build_game(catalog_with(data)) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Splinter Prism"
        battlefield "Forest"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay_all(game)
    pass_both(game)
    game.submit(type: "color", color: "W")
    game.submit(type: "color", color: "B")
    expect(pool(game, "alice")).to eq(W: 1, B: 1)
  end

  it "sunburst: a creature enters with a +1/+1 counter per color of mana spent (CR 702.44a-b)" do
    game = board(hand: ["Spectrum Golem"], lands: %w[Mountain Forest Forest Wastes])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay_all(game)
    pass_both(game)
    golem = game.state.battlefield.find { game.state.object(it).card == "spectrum_golem" }
    expect(game.state.object(golem).counters).to eq("+1/+1" => 2) # red and green; colorless doesn't count
  end

  it "sunburst with only colorless mana spent adds no counters (CR 702.44b)" do
    game = board(hand: ["Spectrum Golem"], lands: %w[Wastes Wastes Wastes Wastes])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay_all(game)
    pass_both(game)
    expect(game.state.battlefield.map { game.state.object(it).card }).not_to include("spectrum_golem") # 0/0 dies
  end
end
