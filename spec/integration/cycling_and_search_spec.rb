# frozen_string_literal: true

RSpec.describe "Cycling, typecycling and library search (CR 702.29, 701.23)" do
  let(:hulk) do
    { "name" => "Dune Hulk", "mana_cost" => "{5}{G}", "types" => ["creature"], "power" => 6, "toughness" => 6,
      "abilities" => [{ "cycling" => { "cost" => "{2}", "for" => { "supertypes" => ["basic"], "types" => ["land"] } } }] }
  end
  let(:scrap) do
    { "name" => "Scrap Sifter", "mana_cost" => "{2}{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 2 } }] } }, { "cycling" => { "cost" => "{R}" } }] }
  end
  let(:bog) do
    { "name" => "Bog Lurker", "mana_cost" => "{4}{B}", "types" => ["creature"], "power" => 4, "toughness" => 4,
      "abilities" => [{ "cycling" => { "cost" => "{1}", "for" => { "subtypes" => ["swamp"] } } }] }
  end
  let(:trailmap) do
    { "name" => "Trail Map", "mana_cost" => "{1}{G}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "search_library" => {
        "for" => { "any_of" => [{ "supertypes" => ["basic"], "types" => ["land"] }, { "subtypes" => ["planet"] }] },
        "put" => "battlefield", "tapped" => true
      } }] } }] }
  end
  let(:tutor) do
    { "name" => "Quiet Tutor", "mana_cost" => "{G}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "search_library" => { "count" => 2 } }] } }] }
  end
  let(:courier) do
    { "name" => "Twin Courier", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} }, "effects" => [{ "search_library" => {
        "for" => { "name" => "Twin Courier" }, "count" => "any", "reveal" => true
      } }] } }] }
  end
  let(:desperate) do
    { "name" => "Desperate Dig", "mana_cost" => "{G}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "search_library" => {
        "for" => { "types" => ["land"] }, "put" => "battlefield", "reveal" => true, "if" => { "life" => "you", "at_most" => 5 }
      } }] } }] }
  end
  let(:catalog) { catalog_with(hulk, scrap, bog, trailmap, tutor, courier, desperate) }

  def game_with(hand, battlefield: %w[Forest Forest], library: ["Island", "Forest", "Mountain", "Grizzly Bears", "Forest"])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand(*hand)
        battlefield(*battlefield)
        library(*library)
      end
      player("bob") do
        hand "Forest"
        library "Forest", count: 5
      end
    end
  end

  def tap_forests(game, count)
    ids = game.state.battlefield.select { game.state.object(it).card == "forest" && !game.state.object(it).tapped }
    ids.first(count).each do |id|
      game.submit(type: "activate_mana", object: id, ability: "intrinsic:forest")
      game.submit(type: "pay_mana", mana: "G")
    end
  end

  it "cycling is offered from the hand only and draws a card (CR 702.29a, 113.6m)" do
    game = game_with(["Scrap Sifter"], battlefield: ["Mountain"])
    card = ids_in(game, "alice", :hand).first
    expect(game.legal_options).to include({ type: "activate", object: card, ability: "printed:1" })
    entry = game.submit(type: "activate", object: card, ability: "printed:1")
    expect(entry.events.map(&:type)).to include("card_revealed") # CR 602.2a: activated from a hidden zone
    game.submit(type: "activate_mana", object: obj_id(game, "Mountain"), ability: "intrinsic:mountain")
    entry = game.submit(type: "pay_mana", mana: "R")
    discard = entry.events.grep(Enjine::Events::ZoneChanged).find { it.reason == "discard" }
    expect(discard).to have_attributes(old_id: card, from: "hand", to: "graveyard")
    top = ids_in(game, "alice", :library).first
    pass_both(game)
    drawn = game.history.last.events.grep(Enjine::Events::ZoneChanged).find { it.old_id == top }
    expect(drawn).to have_attributes(to: "hand", reason: "draw")
    expect(ids_in(game, "alice", :hand)).to eq([drawn.new_id])
    expect(game.state.players[0].graveyard.map { game.state.object(it).card }).to eq(["scrap_sifter"])
  end

  it "cycling isn't offered without the mana, nor for a permanent on the battlefield (CR 702.29a)" do
    game = game_with(["Dune Hulk"], battlefield: ["Forest"])
    expect(option_types(game)).not_to include("activate")
    game = game_with([], battlefield: ["Dune Hulk", "Forest", "Forest"])
    expect(option_types(game)).not_to include("activate")
  end

  it "cancelling a cycling activation leaves the card in hand (CR 602.2, 734)" do
    game = game_with(["Dune Hulk"])
    card = ids_in(game, "alice", :hand).first
    game.submit(type: "activate", object: card, ability: "printed:0")
    game.submit(type: "cancel")
    expect(ids_in(game, "alice", :hand)).to eq([card])
    expect(game.state.stack).to be_empty
  end

  it "basic landcycling: find a basic land, reveal it, put it into the hand, then shuffle (CR 702.29e, 701.23)" do
    game = game_with(["Dune Hulk"])
    game.submit(type: "activate", object: ids_in(game, "alice", :hand).first, ability: "printed:0")
    tap_forests(game, 2)
    pass_both(game)
    decision = game.pending_decision
    expect(decision).to have_attributes(kind: "effect_choice", player: "alice")
    cards = game.legal_options.map { it[:object] && game.state.object(it[:object]).card }
    expect(cards).to contain_exactly("island", "forest", "mountain", nil) # one option per distinct card, plus done
    expect(game.view_for("bob")["pending"]).not_to have_key("choices")
    island = game.legal_options.find { it[:object] && game.state.object(it[:object]).card == "island" }
    entry = game.submit(island)
    types = entry.events.map(&:type)
    expect(types).to include("card_revealed", "zone_changed", "library_shuffled")
    expect(types.index("card_revealed")).to be < types.index("library_shuffled")
    expect(ids_in(game, "alice", :hand).map { game.state.object(it).card }).to eq(["island"])
    expect(ids_in(game, "alice", :library).size).to eq(4)
    bob_view = game.history_for("bob").last
    expect(bob_view["option"]).to eq("type" => "find")
    expect(bob_view["events"].find { it["type"] == "card_revealed" }["card"]).to eq("island")
  end

  it "a search with a stated quality may fail to find (CR 701.23b)" do
    game = game_with(["Bog Lurker"], library: %w[Island Swamp])
    game.submit(type: "activate", object: ids_in(game, "alice", :hand).first, ability: "printed:0")
    tap_forests(game, 1)
    pass_both(game)
    expect(game.legal_options.map { it[:type] }).to contain_exactly("find", "done")
    entry = game.submit(type: "done")
    expect(entry.events.map(&:type)).to include("library_shuffled")
    expect(entry.events.map(&:type)).not_to include("card_revealed")
    expect(ids_in(game, "alice", :hand)).to be_empty
  end

  it "with no matching card the search still shuffles and asks nothing (CR 701.23b, 701.24a)" do
    game = game_with(["Bog Lurker"], library: %w[Island Forest])
    game.submit(type: "activate", object: ids_in(game, "alice", :hand).first, ability: "printed:0")
    tap_forests(game, 1)
    game.submit(type: "pass")
    entry = game.submit(type: "pass")
    expect(entry.events.map(&:type)).to include("library_shuffled")
    expect(game.pending_decision.kind).to eq("priority")
  end

  it "put onto the battlefield tapped; either spec of any_of matches (CR 701.23a)" do
    game = game_with(["Trail Map"], library: ["Grizzly Bears", "Mountain"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    tap_forests(game, 2)
    pass_both(game)
    mountain = ids_in(game, "alice", :library).find { game.state.object(it).card == "mountain" }
    expect(game.legal_options).to eq([{ type: "find", object: mountain }, { type: "done" }])
    entry = game.submit(type: "find", object: mountain)
    land = entry.events.grep(Enjine::Events::ZoneChanged).find { it.old_id == mountain }
    expect(land).to have_attributes(to: "battlefield", reason: "search")
    expect(game.state.object(land.new_id).tapped).to be(true)
    expect(entry.events.map(&:type)).not_to include("tapped") # it entered tapped
  end

  it "a search for just cards must find them, and stops at its count (CR 701.23d)" do
    game = game_with(["Quiet Tutor"], library: %w[Island Mountain Mountain])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    tap_forests(game, 1)
    pass_both(game)
    expect(game.legal_options.map { it[:type] }).to eq(%w[find find]) # no "done": it must find
    game.submit(game.legal_options.find { game.state.object(it[:object]).card == "island" })
    expect(game.legal_options.map { game.state.object(it[:object]).card }).to eq(["mountain"]) # copies are one choice
    game.submit(game.legal_options.first)
    expect(ids_in(game, "alice", :hand).size).to eq(2)
    expect(game.pending_decision.kind).to eq("priority")
  end

  it "a search mid-resolution survives export and import" do
    game = game_with(["Quiet Tutor"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    tap_forests(game, 1)
    pass_both(game)
    game.submit(game.legal_options.first)
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.legal_options).to eq(game.legal_options)
  end

  it "any number of cards with a name: keep finding until done (CR 701.23b)" do
    game = game_with(["Twin Courier"], library: ["Twin Courier", "Twin Courier", "Forest"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    tap_forests(game, 1)
    pass_both(game) # the artifact resolves; its enters trigger goes on the stack
    pass_both(game)
    2.times do
      expect(game.legal_options.map { it[:type] }).to eq(%w[find done])
      game.submit(game.legal_options.first)
    end
    expect(ids_in(game, "alice", :hand).map { game.state.object(it).card }).to eq(%w[twin_courier twin_courier])
    expect(game.history.last.events.count { it.type == "card_revealed" }).to eq(2)
  end

  it "a false \"if\" skips the search entirely (CR 608.2c)" do
    game = game_with(["Desperate Dig"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    tap_forests(game, 1)
    game.submit(type: "pass")
    entry = game.submit(type: "pass")
    expect(entry.events.map(&:type)).not_to include("library_shuffled")
    expect(game.pending_decision.kind).to eq("priority")
  end
end
