# frozen_string_literal: true

RSpec.describe "Core effects: exile, bounce, tap/untap, mill, scry, surveil, discard (CR 701)" do
  def spell(name, effects, targets = [])
    { "name" => name, "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? } }] }
  end

  let(:catalog) do
    catalog_with(
      spell("Banish Ray", [{ "exile" => { "to" => { "target" => 0 } } }], ["creature"]),
      spell("Recall Gust", [{ "return_to_hand" => { "to" => { "target" => 0 } } }], ["creature"]),
      spell("Freeze Bolt", [{ "tap" => { "to" => { "target" => 0 } } }], ["creature"]),
      spell("Mind Leak", [{ "mill" => { "amount" => 3, "to" => "each_opponent" } }]),
      spell("Glimpse", [{ "scry" => { "amount" => 2 } }]),
      spell("Ponder Path", [{ "surveil" => { "amount" => 2 } }]),
      spell("Mind Twist Lite", [{ "discard" => { "amount" => 2, "to" => "each_opponent" } }])
    )
  end

  def game_with(card, bob_board: [], bob_hand: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand card
        battlefield "Mountain"
        library "Forest", "Island", "Swamp", "Plains"
      end
      player("bob") do
        bob_board.each { battlefield it }
        bob_hand.each { hand it }
        library "Forest", count: 5
      end
    end
  end

  def cast(game, target = nil)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: target) if target
    game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
    game.submit(type: "pay_mana", mana: "R")
    2.times { game.submit(type: "pass") }
  end

  def names(game, player, zone) = ids_in(game, player, zone).map { game.state.object(it).card }

  it "exiles a creature (CR 406, 701.13)" do
    game = game_with("Banish Ray", bob_board: ["Grizzly Bears"])
    cast(game, obj_id(game, "Grizzly Bears"))
    expect(game.state.exile.map { game.state.object(it).card }).to eq(["grizzly_bears"])
  end

  it "returns a creature to its owner's hand (CR 400.6)" do
    game = game_with("Recall Gust", bob_board: ["Grizzly Bears"])
    cast(game, obj_id(game, "Grizzly Bears"))
    expect(names(game, "bob", :hand)).to eq(["grizzly_bears"])
  end

  it "taps a creature (CR 701.26a)" do
    game = game_with("Freeze Bolt", bob_board: ["Grizzly Bears"])
    bears = obj_id(game, "Grizzly Bears")
    cast(game, bears)
    expect(game.state.object(bears).tapped).to be(true)
  end

  it "mills the top cards into the graveyard (CR 701.17a)" do
    game = game_with("Mind Leak")
    cast(game)
    expect(names(game, "bob", :graveyard)).to eq(%w[forest forest forest])
    expect(names(game, "bob", :library).size).to eq(2)
  end

  it "scry: each card top or bottom, then the kept cards are ordered (CR 701.22a)" do
    game = game_with("Glimpse")
    cast(game)
    expect(game.pending_decision).to have_attributes(kind: "effect_choice", player: "alice")
    first, second = ids_in(game, "alice", :library).first(2)
    expect(game.legal_options).to eq([{ type: "top", object: first }, { type: "bottom", object: first }])
    game.submit(type: "top", object: first)
    game.submit(type: "top", object: second)
    expect(game.legal_options.map { it[:object] }).to contain_exactly(first, second) # order the two kept on top
    game.submit(type: "order", object: second)
    expect(ids_in(game, "alice", :library).first(2)).to eq([second, first])
    expect(game.pending_decision.kind).to eq("priority")
  end

  it "scry to the bottom, and opponents don't learn which card (hidden information)" do
    game = game_with("Glimpse")
    cast(game)
    first, second = ids_in(game, "alice", :library).first(2)
    game.submit(type: "bottom", object: first)
    game.submit(type: "top", object: second)
    library = ids_in(game, "alice", :library)
    expect(library.first).to eq(second)
    expect(library.last).to eq(first)
    seen_by_bob = game.history_for("bob").select { it["kind"] == "effect_choice" }.map { it["option"] }
    expect(seen_by_bob).to all(satisfy { !it.key?("object") })
  end

  it "surveil puts cards into the graveyard (CR 701.25a)" do
    game = game_with("Ponder Path")
    cast(game)
    first, second = ids_in(game, "alice", :library).first(2)
    game.submit(type: "graveyard", object: first)
    game.submit(type: "graveyard", object: second)
    expect(names(game, "alice", :graveyard)).to include("forest", "island")
    expect(names(game, "alice", :library)).to eq(%w[swamp plains])
  end

  it "discard: the discarding player chooses, one card per decision (CR 701.9b)" do
    game = game_with("Mind Twist Lite", bob_hand: ["Lightning Bolt", "Forest", "Island"])
    cast(game)
    expect(game.pending_decision).to have_attributes(kind: "effect_choice", player: "bob")
    expect(game.legal_options.size).to eq(3)
    game.submit(game.legal_options.last)
    game.submit(game.legal_options.first)
    expect(names(game, "bob", :hand)).to eq(["forest"])
    expect(names(game, "bob", :graveyard)).to contain_exactly("lightning_bolt", "island")
  end

  it "discard with too few cards discards what there is" do
    game = game_with("Mind Twist Lite", bob_hand: ["Forest"])
    cast(game)
    game.submit(game.legal_options.first)
    expect(game.pending_decision.kind).to eq("priority")
    expect(names(game, "bob", :hand)).to be_empty
  end

  it "survives export/import in the middle of a scry" do
    game = game_with("Glimpse")
    cast(game)
    game.submit(game.legal_options.first)
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.pending_decision).to eq(game.pending_decision)
    copy.submit(copy.legal_options.first)
    game.submit(game.legal_options.first)
    expect(copy.state.to_h).to eq(game.state.to_h)
  end
end
