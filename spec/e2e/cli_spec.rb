# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Enjine::CLI do
  let(:examples) { File.join(CardFixtures::ROOT, "examples") }
  let(:pool) { ["--pool", "#{examples}/pool.json"] }
  let(:decks) { ["--deck1", "#{examples}/decks/gruul_beats.json", "--deck2", "#{examples}/decks/azorius_walkers.json"] }

  def run(args, input = "")
    out = StringIO.new
    code = described_class.new(args, input: StringIO.new(input), output: out).run
    [code, out.string]
  end

  # A game between the example decks.
  def play(args, input = "") = run(decks + args, input)

  it "plays deck files, naming them in the intro, and explains missing or broken ones" do
    _, out = play(%w[--p1 random --p2 random --seed 3 --max-decisions 1])
    expect(out).to include("alice: gruul_beats   bob: azorius_walkers")
    expect(run(%w[--p1 random])).to eq([1, "error: pass --deck1: a deck file (see examples/decks) or random[:SPEC] with --pool\n"])
    expect(run(%w[--deck1 nope.json --deck2 nope.json])[1]).to start_with("error: No such file or directory")
  end

  it "plays random vs random to the end, narrating every event" do
    code, out = play(%w[--p1 random --p2 random --seed 3])
    expect(code).to eq(0)
    expect(out).to include("seed 3", "══ Turn 1", "GAME OVER")
  end

  it "prints only the result with --quiet" do
    _, out = play(%w[--p1 random --p2 random --seed 3 --quiet])
    expect(out.lines.size).to eq(1)
    expect(out).to match(/GAME OVER: (\w+ wins \(\w+\)|draw)/)
  end

  it "is hot-seat by default: shows the deciding player's view and numbered options" do
    _, out = play(%w[--seed 4], "x\n99\n1\n1\n1\nq\n")
    expect(out).to include("must act: play or draw", " 1) Play first", "Unknown command", "Choose 1-2",
                           "must act: mulligan", "Keep hand")
    expect(out).to match(/Hand: .*\[/) # the deciding player's own hand is visible
  end

  it "supports board, observer, history, help, save, undo and concede" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "game.json")
      _, out = play(%w[--seed 4], "1\n1\n1\nb\no\nh 3\n?\ns #{path}\nu\nc\n")
      expect(out).to include("Observer view on", "Library (top first)", "Commands:", "Saved to",
                             "Undid", "GAME OVER")
      expect(File).to exist(path)

      _, resumed = run(["--load", path, "--p1", "random", "--p2", "random", "--quiet"])
      expect(resumed).to include("GAME OVER")
      _, no_undo = run(["--load", path], "u\nq\n")
      expect(no_undo).to include("Undo needs a game started in this session")
      File.write(path, "{}")
      expect(run(["--load", path])).to eq([1, "error: #{path}: not a game saved with the s command\n"])
    end
  end

  it "concedes for the pending player when the decision limit is reached" do
    _, out = play(%w[--p1 random --p2 random --seed 4 --max-decisions 30 --observer])
    expect(out).to include("wins (concede)")
  end

  it "validates card data blocks, reporting each valid card's canonical form and each error" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "cards.json")
      alfa = { "name" => "Alfa", "types" => ["land"], "rarity" => "common", "printing" => { "set" => "trk", "number" => 12 } }
      File.write(path, JSON.generate([alfa, { "name" => "Bravo" }]))
      code, out = run(["--validate", path])
      report = JSON.parse(out)
      expect([code, report["valid"].map { it["card"]["printing"] }]).to eq([1, [{ "set" => "trk", "number" => "12" }]])
      expect(report["invalid"]).to eq([{ "index" => 1, "name" => "Bravo", "errors" => ["types: must be a non-empty list"] }])
      File.write(path, JSON.generate(alfa))
      expect(run(["--validate", path])[0]).to eq(0)
      File.write(path, "nope")
      expect(run(["--validate", path])[1]).to start_with('{"error":"not valid JSON')
    end
  end

  describe "random decks" do
    it "prints a reproducible random deck document from --pool as JSON" do
      code, out = run(pool + %w[--random-deck colors=WU seed=7])
      expect(code).to eq(0)
      doc = JSON.parse(out)
      expect(doc["description"]).to start_with("random deck: colors=WU seed=7")
      expect(Enjine::Player.new(name: "p", deck: doc)).to be_ready
      expect(run(pool + ["--random-deck", "colors=UW seed=7"])[1]).to eq(out)
      expect(run(pool + %w[--random-deck colors=W,U,seed=7])[1]).to eq(out)
    end

    it "picks random colors, sizes, and the --seed by default" do
      two = JSON.parse(run(pool + %w[--seed 5 --random-deck colors=2])[1])
      expect(two["description"]).to match(/colors=[WUBRG]{2} seed=5/)
      expect(JSON.parse(run(pool + %w[--random-deck size=61 seed=1])[1])["main"].sum { it["count"] }).to eq(61)
      expect(run(pool + %w[--seed 1 --random-deck])[0]).to eq(0)
    end

    it "reports bad specs, impossible decks and a missing pool with exit code 1" do
      expect(run(pool + %w[--random-deck colors=X])).to eq([1, "error: unknown color X (use W U B R G)\n"])
      expect(run(pool + ["--random-deck", "WU"])[1]).to include("expected key=value")
      expect(run(pool + %w[--random-deck mood=happy])[1]).to include("unknown random deck option(s): mood")
      expect(run(pool + %w[--random-deck colors=B])[1]).to start_with("error: cannot build a 60-card B deck from 46 cards")
      expect(run(%w[--random-deck])).to eq([1, "error: random decks need --pool FILE (a JSON array of cards)\n"])
      expect(run(%w[--pool nope.json --random-deck])[1]).to start_with("error: No such file or directory")
    end

    it "plays games with random:SPEC decks" do
      code, out = run(pool + %w[--deck1 random:colors=2 --deck2 random --p1 random --p2 random --seed 3])
      expect(code).to eq(0)
      expect(out).to include("alice: random deck: colors=", "seed=3", "bob: random deck: colors=", "seed=4", "GAME OVER")
      expect(run(pool + %w[--deck1 random:colors=X --deck2 random --p1 random --p2 random]))
        .to eq([1, "error: unknown color X (use W U B R G)\n"])
    end
  end

  it "passes for a human seat when passing (or making unspendable mana) is all it can do" do
    _, out = play(%w[--seed 4], "1\n1\n1\n3\n1\nq\n")
    expect(out).to include("alice plays Mountain", "─ Combat › Declare Attackers", "─ Main 2")
    # asked twice in Main 1 and once in Main 2; the combat steps pass by themselves
    expect(out.scan("must act: priority").size).to eq(3)
    expect(out).not_to include("alice's turn · Beginning of Combat")
  end

  it "shows whose turn it is and where in the turn the game is" do
    game = build_game do
      turn 3, active: "bob", step: :declare_blockers
      player("alice")
      player("bob")
    end
    text = described_class::Text.new(game)
    board = text.board(game.view_for("alice"))
    expect(board).to start_with("━━ Turn 3 · bob's turn · Declare Blockers")
    expect(board).to include("Beginning › Main 1 › ▶COMBAT (begin · attackers · [blockers] · damage · end) › Main 2 › End")
    expect(text.event("type" => "step_began", "step" => "upkeep")).to eq("─ Beginning › Upkeep")
    expect(text.event("type" => "step_began", "step" => "postcombat_main")).to eq("─ Main 2")
  end

  it "says when there is nothing to undo" do
    _, out = play(%w[--seed 4], "u\nq\n")
    expect(out).to include("Nothing to undo")
  end

  it "describes a granted mana ability from the granting card's data (CR 613.1f)" do
    speaker = { "name" => "Sap Herald", "mana_cost" => "{G}", "types" => ["creature"], "power" => 1, "toughness" => 1,
                "abilities" => [{ "static" => { "affects" => { "each" => "creature", "controller" => "you" },
                                                "abilities" => [{ "mana" => { "cost" => ["tap"], "produce" => "{G}" } }] } }] }
    game = build_game(catalog_with(speaker)) do
      turn 2, active: "alice", step: :precombat_main
      player("alice") { battlefield "Sap Herald", "Grizzly Bears" }
      player("bob")
    end
    option = { type: "activate_mana", object: obj_id(game, "Grizzly Bears"), ability: "granted:sap_herald:printed:0:0" }
    expect(described_class::Text.new(game).option(option)).to eq("Tap Grizzly Bears for mana ({T}: Add {G}.)")
  end

  it "shows a permanent's keywords as it has them now, granted ones included (CR 613.1f)" do
    banner = { "name" => "Twin Banner", "mana_cost" => "{2}", "types" => ["artifact"],
               "abilities" => [{ "static" => { "affects" => { "each" => "creature", "controller" => "you" },
                                               "keywords" => %w[double_strike] } }] }
    game = build_game(catalog_with(banner)) do
      turn 2, active: "alice", step: :precombat_main
      player("alice") { battlefield "Twin Banner", "Grizzly Bears" }
      player("bob")
    end
    expect(described_class::Text.new(game).board(game.view_for("alice"))).to include("Grizzly Bears · 2/2 · double strike")
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
      { type: "discard", object: mountain } => "Discard Mountain", { type: "future" } => '{type: "future"}',
      { type: "pay" } => "Pay", { type: "pay", option: 1, cost: "{2}" } => "Pay: {2}"
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
    %w[draw play_land cast resolve mulligan sba_lethal_damage sba_toughness sba_loyalty destroy countered
       mulligan_bottom].each do |reason|
      text.zone_changed("type" => "zone_changed", "card" => "forest", "owner" => "alice", "from" => "hand",
                        "to" => "battlefield", "reason" => reason)
    end
    expect(text.result("winner" => nil, "reason" => "life")).to eq("draw (life)")
    expect(text.event("type" => "brand_new")).to start_with("brand_new")
  end
end
