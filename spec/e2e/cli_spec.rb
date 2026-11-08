# frozen_string_literal: true

require "stringio"

RSpec.describe Enjine::CLI do
  def run(args, input = "")
    out = StringIO.new
    code = described_class.new(args, input: StringIO.new(input), output: out).run
    [code, out.string]
  end

  it "plays random vs random to the end" do
    code, out = run(%w[--p1 random --p2 random --seed 3])
    expect(code).to eq(0)
    expect(out).to include("seed 3", "== Turn 1", "Game over:")
  end

  it "prints only the result with --quiet" do
    _, out = run(%w[--p1 random --seed 3 --quiet])
    expect(out.lines.size).to eq(2)
    expect(out).to match(/Game over: p\d wins by empty_library/)
  end

  it "lets a human choose numbered options and concede with q" do
    _, out = run(%w[--p1 human --p2 human --seed 4 --max-decisions 50], "x\n99\n1\n1\n1\n1\n2\nq\n")
    expect(out).to include("play_or_draw", "1. Play first", "Enter 1-2", "Keep hand", "Mulligan", "Game over:")
  end

  it "concedes for the pending player when the decision limit is reached" do
    _, out = run(%w[--p1 random --p2 random --seed 4 --max-decisions 30])
    expect(out).to include("wins by concede")
  end

  it "describes every option type" do
    game = build_game do
      turn 2, active: "alice", step: :precombat_main
      player("alice") do
        hand "Forest"
        battlefield "Mountain"
      end
      player("bob")
    end
    texts = game.legal_options.map { described_class::Text.option(game, it) }
    expect(texts).to eq(["Pass priority", "Play Forest [#{ids_in(game, "alice", :hand).first}]",
                         "Activate Mountain [#{game.state.battlefield.first}]: {T}: Add {R}."])
    expect(described_class::Text.option(game, { type: "discard", object: ids_in(game, "alice", :hand).first }))
      .to start_with("Discard Forest")
    expect(described_class::Text.option(game, { type: "draw" })).to eq("Draw first")
    expect(described_class::Text.option(game, { type: "future" })).to eq('{type: "future"}')
    expect(described_class::Text.result("winner" => nil, "reason" => "life")).to eq("draw (life)")
    expect(described_class::Text.event("type" => "zone_changed", "owner" => "a", "from" => "hand", "to" => "graveyard",
                                       "reason" => "discard")).to eq("a: a card hand → graveyard (discard)")
    board = described_class::Text.board(game.view_for("alice"))
    expect(board).to include("hand: Forest", "battlefield: Mountain")
  end
end
