# frozen_string_literal: true

RSpec.describe "Starting the game (CR 103)" do
  let(:game) { basics_setup.new_game(seed: 11) }

  it "rolls a die and lets the winner choose to play or draw (CR 103.1)" do
    opening = game.history.first
    expect(opening.option).to be_nil
    expect(opening.events.map(&:type)).to eq(%w[game_started die_rolled])
    winner = opening.events.last.winner
    expect(game.pending_decision.to_h).to eq("player" => winner, "kind" => "play_or_draw",
                                             "options" => [{ "type" => "play" }, { "type" => "draw" }])
    game.submit(type: "draw")
    other = (game.names - [winner]).first
    expect(game.state.starting_player).to eq(game.names.index(other))
  end

  it "shuffles and draws seven cards each, then asks the starting player first (CR 103.3-103.5)" do
    game.submit(type: "play")
    view = game.view_for(:observer)
    expect(view["players"].map { it["hand_count"] }).to eq([7, 7])
    expect(view["players"].map { it["library_count"] }).to eq([53, 53])
    expect(game.pending_decision.kind).to eq("mulligan")
    expect(game.pending_decision.player).to eq(game.names[game.state.starting_player])
  end

  it "declares in turn order, then mulligans simultaneously; bottoms come with the mulligan (London, CR 103.5)" do
    game.submit(type: "play")
    first, second = game.state.starting_player.then { [game.names[it], game.names[1 - it]] }
    first_index = game.names.index(first)
    game.submit(type: "mulligan")
    expect(game.pending_decision.player).to eq(second)
    expect(game.state.players.map(&:hand).map(&:size)).to eq([7, 7]) # nothing happens until all declared
    game.submit(type: "keep")

    # The mulligan happens now: new 7-card hand, then 1 card to the bottom before declaring again.
    expect(game.pending_decision).to have_attributes(kind: "bottom", player: first, details: { "count" => 1 })
    expect(game.state.players[first_index].hand.size).to eq(7)
    card = game.legal_options.first[:object]
    entry = game.submit(type: "bottom", object: card)
    expect(game.state.players[first_index].library.last).to eq(entry.events.first.new_id)
    expect(game.pending_decision).to have_attributes(kind: "mulligan", player: first)
    expect(game.state.players[first_index].hand.size).to eq(6) # the declaration is made on the smaller hand

    game.submit(type: "keep")
    expect(game.step).to eq(:upkeep)
    expect(game.turn).to eq(1)

    opponent_view = game.history_for(second).find { it["kind"] == "bottom" }
    expect(opponent_view["option"]).to eq("type" => "bottom")
    expect(opponent_view["events"].first).not_to have_key("card")
    expect(game.history_for(first).find { it["kind"] == "bottom" }["option"]).to eq("type" => "bottom", "object" => card)
  end

  it "stops offering mulligans once the hand would be empty" do
    game.submit(type: "play")
    starter = game.state.starting_player
    7.times do |n|
      game.submit(type: "mulligan") # starting player
      game.submit(type: "keep") if n.zero? # the other player keeps right away
      (n + 1).times { game.submit(game.legal_options.first) } # bottom n+1 cards
    end
    expect(game.state.players[starter].hand).to be_empty
    expect(game.legal_options).to eq([{ type: "keep" }])
    game.submit(type: "keep")
    expect(game.turn).to eq(1)
  end
end
