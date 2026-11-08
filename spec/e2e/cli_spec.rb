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

  describe "random decks" do
    let(:sets) { ["--sets-dir", DeckBuilderHelpers::SET_FIXTURES] }

    it "prints a reproducible random deck document as JSON" do
      code, out = run(sets + %w[--random-deck sets=fxa,fxb colors=WU seed=7])
      expect(code).to eq(0)
      doc = JSON.parse(out)
      expect(doc["description"]).to include("sets=fxa,fxb colors=WU seed=7")
      expect(Enjine::Player.new(name: "p", deck: doc)).to be_ready
      expect(run(sets + ["--random-deck", "sets=fxb,fxa colors=UW seed=7"])[1]).to eq(out)
      expect(run(sets + %w[--random-deck sets=fxa,fxb,colors=W,U,seed=7])[1]).to eq(out)
    end

    it "picks random colors, all sets or Standard sets, and the --seed by default" do
      two = JSON.parse(run(sets + %w[--seed 5 --random-deck colors=2])[1])
      expect(two["description"]).to match(/sets=fxa,fxb colors=[WUBRG]{2} seed=5/)
      allow(Date).to receive(:today).and_return(Date.new(2026, 1, 1)) # only fxa is out by then
      expect(run(sets + %w[--random-deck sets=standard seed=1])[1]).to include("sets=fxa colors")
      expect(JSON.parse(run(sets + %w[--random-deck sets=standard size=61 seed=1])[1])["main"].sum { it["count"] }).to eq(61)
      expect(JSON.parse(run(sets + %w[--random-deck sets=all colors=any seed=1])[1])).to include("cards", "main")
      expect(run(sets + %w[--seed 1 --random-deck])[0]).to eq(0)
    end

    it "reports bad specs and impossible decks with exit code 1" do
      expect(run(sets + %w[--random-deck colors=X])).to eq([1, "error: unknown color X (use W U B R G)\n"])
      expect(run(sets + %w[--random-deck sets=nope])[1]).to start_with("error: unknown set \"nope\"")
      expect(run(sets + ["--random-deck", "fxa"])[1]).to include("expected key=value")
      expect(run(sets + %w[--random-deck mood=happy])[1]).to include("unknown random deck option(s): mood")
      expect(run(sets + %w[--random-deck sets=fxa colors=W size=200])[1]).to start_with("error: cannot build a 200-card W deck")
    end

    it "lists the sets in the sets directory" do
      _, out = run(sets + %w[--list-sets])
      expect(out).to include("fxa    Ashfall Reaches (2025-06-13) · 48 playable, 2 unsupported",
                             "fxb    Tidewild Expanse")
    end

    it "plays games with random:SPEC decks" do
      code, out = run(sets + %w[--deck1 random:sets=fxa,colors=2 --deck2 random --p1 random --p2 random --seed 3])
      expect(code).to eq(0)
      expect(out).to include("alice: random deck: sets=fxa colors=", "bob: random deck: sets=fxa,fxb", "seed=4", "GAME OVER")
      expect(run(sets + %w[--deck1 random:colors=X --p1 random --p2 random])).to eq([1, "error: unknown color X (use W U B R G)\n"])
    end
  end

  describe "collections" do
    let(:sets) { ["--sets-dir", DeckBuilderHelpers::SET_FIXTURES] }
    let(:binder) { ["--collection", DeckBuilderHelpers::BINDER] }

    it "prints random decks built only from the collection" do
      code, out = run(sets + binder + %w[--random-deck colors=WU seed=3])
      expect(code).to eq(0)
      doc = JSON.parse(out)
      expect(doc["description"]).to start_with("random deck: collection=binder.json colors=WU seed=3")
      expect(Enjine::Player.new(name: "p", deck: doc)).to be_ready
      owned = Enjine::Collection.load(DeckBuilderHelpers::BINDER, sets_dir: DeckBuilderHelpers::SET_FIXTURES)
      expect(doc["main"].map { it["card"] }).to all(satisfy { owned.include?(it) || %w[Plains Island].include?(it) })
      expect(JSON.parse(run(sets + binder + %w[--random-deck colors=WU seed=3 basics=owned])[1])["description"])
        .to include("basics=owned")
    end

    it "plays games with random decks from the collection, and reports problems" do
      code, out = run(sets + binder + %w[--deck1 random:colors=R --deck2 random:colors=WU --p1 random --p2 random --seed 2 --quiet])
      expect(code).to eq(0)
      expect(out).to include("GAME OVER")
      expect(run(sets + binder + %w[--random-deck colors=B seed=1])[1]).to start_with("error: cannot build a 60-card B deck")
      expect(run(sets + binder + %w[--random-deck sets=fxa])[1]).to eq("error: pass either sets: or collection:, not both\n")
      expect(run(sets + %w[--collection nope.json --random-deck])).to eq([1, "error: collection file not found: nope.json\n"])
      expect(run(sets + %w[--collection nope.json --p1 random --p2 random --deck1 random])[1])
        .to eq("error: collection file not found: nope.json\n")
    end

    it "prints the resolution report as JSON, exit code 1 when some cards are unknown" do
      code, out = run(sets + ["--collection-report", DeckBuilderHelpers::BINDER])
      expect(code).to eq(1)
      report = JSON.parse(out)
      expect(report.keys).to eq(%w[resolved unsupported unknown])
      expect(report["unsupported"].map { it["name"] }).to eq(["Prismatic Tidecaller", "Skyveil Seraph"])
      Dir.mktmpdir do |dir|
        clean = File.join(dir, "clean.json")
        File.write(clean, JSON.generate("format" => 1, "cards" => [{ "name" => "Dawnward Squire", "count" => 4 }]))
        expect(run(sets + ["--collection-report", clean])[0]).to eq(0)
        File.write(clean, "[1]")
        expect(run(sets + ["--collection-report", clean])).to eq([1, "{\"error\":\"cards[0]: expected an object, got 1\"}\n"])
      end
    end
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
