# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Enjine::CLI do
  def run(args, input = "")
    out = StringIO.new
    code = described_class.new(args, input: StringIO.new(input), output: out).run
    [code, out.string]
  end

  it "lists the sample decks" do
    _, out = run(%w[--list-decks])
    expect(out).to include("gruul_beats", "azorius_walkers", "izzet_spells")
  end

  it "plays random vs random to the end, narrating every event" do
    code, out = run(%w[--p1 random --p2 random --seed 3])
    expect(code).to eq(0)
    expect(out).to include("seed 3", "══ Turn 1", "GAME OVER")
  end

  it "prints only the result with --quiet" do
    _, out = run(%w[--p1 random --p2 random --seed 3 --quiet])
    expect(out.lines.size).to eq(1)
    expect(out).to match(/GAME OVER: (\w+ wins \(\w+\)|draw)/)
  end

  it "is hot-seat by default: shows the deciding player's view and numbered options" do
    _, out = run(%w[--seed 4], "x\n99\n1\n1\n1\nq\n")
    expect(out).to include("must act: play or draw", " 1) Play first", "Unknown command", "Choose 1-2",
                           "must act: mulligan", "Keep hand")
    expect(out).to match(/Hand: .*\[/) # the deciding player's own hand is visible
  end

  it "supports fast-forward, board, observer, history, help, save, undo and concede" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "game.json")
      _, out = run(%w[--seed 4], "1\n1\n1\nf\nb\no\nh 3\n?\ns #{path}\nu\nc\n")
      expect(out).to include("(passed", "Observer view on", "Library (top first)", "Commands:", "Saved to",
                             "Undid", "GAME OVER")
      expect(File).to exist(path)

      _, resumed = run(["--load", path, "--p1", "random", "--p2", "random", "--quiet"])
      expect(resumed).to include("GAME OVER")
      _, no_undo = run(["--load", path], "u\nq\n")
      expect(no_undo).to include("Undo needs a game started in this session")
    end
  end

  it "concedes for the pending player when the decision limit is reached" do
    _, out = run(%w[--p1 random --p2 random --seed 4 --max-decisions 30 --observer])
    expect(out).to include("wins (concede)")
  end

  it "says when there is nothing to undo" do
    _, out = run(%w[--seed 4], "u\nq\n")
    expect(out).to include("Nothing to undo")
  end

  it "describes every option and event type in plain text" do
    game = build_game do
      turn 2, active: "alice", step: :precombat_main
      player("alice") do
        hand "Forest", "Lightning Bolt"
        battlefield "Mountain", "Vessa, Rally Captain"
        battlefield "Grizzly Bears", counters: { "+1/+1" => 1 }, damage: 1
      end
      player("bob")
    end
    text = described_class::Text.new(game)
    mountain, vessa, bears = game.state.battlefield
    expect(game.legal_options.map { text.option(it) }).to include(
      "Pass priority", "Play land Forest", "Cast Lightning Bolt {R}",
      "Tap Mountain for mana ({T}: Add {R}.)", "Activate Vessa, Rally Captain: +1: +1/+1 until end of turn → each creature you control"
    )
    {
      { type: "target", target: "player:bob" } => "Target bob", { type: "cancel" } => "Cancel (rewind this cast/activation)",
      { type: "pay_mana", mana: "G" } => "Pay {G} from mana pool", { type: "done" } => "Done",
      { type: "attack", object: bears, target: vessa } => "Attack Vessa, Rally Captain with Grizzly Bears",
      { type: "block", object: bears, attacker: bears } => "Block Grizzly Bears with Grizzly Bears",
      { type: "assign", object: bears } => "Assign 1 damage to Grizzly Bears", { type: "keep" } => "Keep hand",
      { type: "mulligan" } => "Mulligan", { type: "draw" } => "Draw first",
      { type: "discard", object: mountain } => "Discard Mountain", { type: "future" } => '{type: "future"}'
    }.each { |opt, words| expect(text.option(opt)).to eq(words) }

    board = text.board(game.view_for("alice"))
    expect(board).to include("Grizzly Bears · 3/3 · damage 1 · 1×+1/+1", "Vessa, Rally Captain · loyalty 3", "Hand:")

    events = Enjine::Events::REGISTRY.values.map do |klass|
      sample = klass.members.to_h { [it, %i[targets affected players].include?(it) ? [] : "x"] }
      sample.merge!(details: { "power" => 1, "toughness" => 1 }) if klass.members.include?(:details)
      sample.merge!(mulligans: 1) if klass.members.include?(:mulligans)
      text.event(klass.new(**sample).to_h)
    end
    expect(events.compact).not_to be_empty
    %w[draw play_land cast resolve mulligan sba_lethal_damage sba_toughness sba_loyalty destroy].each do |reason|
      text.zone_changed("type" => "zone_changed", "card" => "forest", "owner" => "alice", "from" => "hand",
                        "to" => "battlefield", "reason" => reason)
    end
    expect(text.result("winner" => nil, "reason" => "life")).to eq("draw (life)")
    expect(text.event("type" => "brand_new")).to start_with("brand_new")
  end
end
