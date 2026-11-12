# frozen_string_literal: true

# Plot (CR 702.170): a special action exiles the card from its owner's hand at sorcery timing; on a later turn
# its owner may cast it from exile without paying its mana cost, during their main phase with an empty stack.
# "It becomes plotted" (the plot effect) does the same for a spell or an exiled card.
RSpec.describe "Plot (CR 702.170, 116.2k)" do
  let(:outlaw) do
    { "name" => "Spec Dusty Outlaw", "mana_cost" => "{3}{R}", "types" => ["creature"], "power" => 4, "toughness" => 3,
      "abilities" => [{ "plot" => { "cost" => "{1}{R}" } }] }
  end
  let(:trick) do
    { "name" => "Spec Quickdraw Trick", "mana_cost" => "{2}{R}", "types" => ["instant"],
      "abilities" => [{ "plot" => { "cost" => "{R}" } },
                      { "spell" => { "effects" => [{ "lose_life" => { "amount" => 3, "to" => "each_opponent" } }] } }] }
  end
  let(:stash) do
    { "name" => "Spec Stash Away", "mana_cost" => "{1}{U}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["spell"], "effects" => [{ "plot" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:catalog) { catalog_with(outlaw, trick, stash) }

  def board(hand:, mana: { R: 2 }, step: :precombat_main, bob_hand: [], bob_mana: {})
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana) do
        hand(*hand)
        library "Forest", count: 10
      end
      player("bob", mana_pool: bob_mana) do
        hand(*bob_hand)
        library "Forest", count: 10
      end
    end
  end

  def card(game, id) = game.state.object(id).card
  def plot_option(game) = game.legal_options.find { it[:type] == "special_action" }
  def plotted_casts(game) = game.legal_options.select { it[:type] == "cast" && it[:via] == "plotted" }

  def pay_up(game)
    game.submit(game.legal_options.find { it[:type] == "pay_mana" } || raise("can't pay")) while game.pending_decision.kind == "pay_cost"
  end

  # Passes priority until the block holds.
  def advance(game)
    300.times do
      return if yield

      options = game.legal_options
      game.submit(options.find { it[:type] == "pass" } || options.find { it[:type] == "done" } || options.first)
    end
    raise "never got there"
  end

  def plot!(game)
    game.submit(plot_option(game))
    pay_up(game)
  end

  it "exiles the card face up as a special action, and can't be cast from exile the same turn" do
    game = board(hand: ["Spec Dusty Outlaw"])
    plot!(game)
    exiled = game.state.exile.first
    expect(card(game, exiled)).to eq("spec_dusty_outlaw")
    expect(game.state.object(exiled).memory["plotted"]).to eq(3)
    expect(game.state.players[0].mana_pool.values.sum).to eq(0)
    expect(game.pending_decision.kind).to eq("priority") # special actions don't use the stack (CR 116.3)
    expect(plotted_casts(game)).to be_empty
  end

  it "casts a plotted card for free on a later turn, at sorcery timing even for an instant" do
    game = board(hand: ["Spec Quickdraw Trick"], mana: { R: 1 })
    plot!(game)
    advance(game) { game.state.active == 1 && game.state.step == :upkeep }
    expect(plotted_casts(game)).to be_empty # bob's turn: not alice's main phase
    advance(game) { game.state.active.zero? && game.state.step == :upkeep }
    expect(plotted_casts(game)).to be_empty # an instant still waits for the main phase
    advance(game) { game.state.active.zero? && game.state.step == :precombat_main }
    game.submit(plotted_casts(game).first)
    pay_up(game)
    advance(game) { game.state.stack.empty? && game.pending_decision.kind == "priority" }
    expect(game.state.players[1].life).to eq(17)
    expect(game.state.players[0].graveyard.map { card(game, it) }).to eq(["spec_quickdraw_trick"])
  end

  it "plots only from the hand at sorcery timing" do
    expect(plot_option(board(hand: ["Spec Dusty Outlaw"], step: :upkeep))).to be_nil
    expect(plot_option(board(hand: ["Spec Dusty Outlaw"], mana: {}))).to be_nil # can't pay {1}{R}
  end

  it "the plot effect exiles a spell and it becomes plotted for its owner" do
    game = board(hand: ["Spec Dusty Outlaw"], mana: { R: 4 }, bob_hand: ["Spec Stash Away"], bob_mana: { U: 2 })
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay_up(game)
    game.submit(type: "pass")
    stash_id = ids_in(game, "bob", :hand).first
    game.submit(type: "cast", object: stash_id)
    advance(game) { game.pending_decision.kind == "pay_cost" }
    pay_up(game)
    advance(game) { game.state.stack.empty? && game.pending_decision.kind == "priority" }
    exiled = game.state.exile.find { card(game, it) == "spec_dusty_outlaw" }
    expect(game.state.object(exiled).memory["plotted"]).to eq(3)
    expect(game.state.battlefield).to be_empty
  end

  it "describes and validates" do
    expect(Enjine::CardDefinition.from_h(outlaw).abilities.first.to_s).to eq("Plot {1}{R}")
    bad = outlaw.merge("abilities" => [{ "plot" => { "cost" => "{1}{R}", "when" => "now" } }])
    expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition, /unknown parameter "when"/)
  end
end
