# frozen_string_literal: true

# Searching a library (CR 701.23) and putting the found card into the graveyard, or shuffling and putting it
# on top (CR 701.24a); a computed bound in what is searched for, worked out as the effect resolves (CR 608.2h).
RSpec.describe "Search destinations: graveyard, top of the library; computed bounds" do
  let(:entomb) do
    { "name" => "Spec Bury the Find", "mana_cost" => "{B}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "effects" => [
        { "search_library" => { "for" => { "types" => ["creature"] }, "put" => "graveyard" } }
      ] } }] }
  end
  let(:tutor) do
    { "name" => "Spec Whispered Lesson", "mana_cost" => "{U}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [
        { "search_library" => { "for" => { "types" => ["creature"] }, "put" => "library_top", "reveal" => true } }
      ] } }] }
  end
  let(:bay) do
    { "name" => "Spec Refitting Dock", "mana_cost" => "{2}{U}", "types" => ["artifact"],
      "abilities" => [{ "activated" => {
        "timing" => "sorcery", "cost" => ["tap", { "sacrifice_permanent" => { "filter" => "artifact", "other" => true } }],
        "effects" => [{ "search_library" => {
          "for" => { "types" => ["artifact"], "mana_value" => { "equal" => { "plus" => [{ "sacrificed" => "mana_value" }, 1] } } },
          "put" => "battlefield"
        } }]
      } }] }
  end
  let(:engine3) { { "name" => "Spec Three-Cog Engine", "mana_cost" => "{3}", "types" => ["artifact"] } }
  let(:catalog) { catalog_with(entomb, tutor, bay, engine3) }

  def player(game, name) = game.state.players[game.names.index(name)]
  def card(game, id) = game.state.object(id).card

  def board(hand: [], battlefield: [], library: [], mana: {})
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: mana) do
        battlefield.each { battlefield it }
        hand(*hand)
        library(*library)
      end
      player("bob") { library "Forest", count: 3 }
    end
  end

  # Passes priority and pays until the stack is empty; answers searches with the first card named `find`.
  def resolve(game, action, find:)
    game.submit(action)
    until (decision = game.pending_decision).kind == "priority" && game.state.stack.empty?
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { it[:type] == "pay_mana" } || raise("can't pay"))
      else
        cost = game.legal_options.find { it[:type] == "cost" } and next game.submit(cost) # the artifact to sacrifice
        yield game.legal_options if block_given?
        game.submit(game.legal_options.find { it[:object] && card(game, it[:object]) == Enjine::CardDefinition.slug(find) } ||
                    raise("no #{find} in #{game.legal_options}"))
      end
    end
    game
  end

  def cast(game, name, find:, &)
    id = ids_in(game, "alice", :hand).find { card(game, it) == Enjine::CardDefinition.slug(name) }
    resolve(game, { type: "cast", object: id }, find: find, &)
  end

  it "puts the found card into the graveyard and shuffles (CR 701.23a, 701.24b)" do
    game = board(hand: ["Spec Bury the Find"], library: ["Forest", "Craw Wurm", "Forest"], mana: { B: 1 })
    events = []
    game.subscribe { events << it }
    cast(game, "Spec Bury the Find", find: "Craw Wurm")
    expect(player(game, "alice").graveyard.map { card(game, it) }).to include("craw_wurm")
    expect(player(game, "alice").library.size).to eq(2)
    expect(events.map { it.type.to_s }).to include("library_shuffled")
  end

  it "shuffles, then puts the found card on top (CR 701.24a), revealed" do
    library = (["Forest"] * 6) + ["Grizzly Bears"]
    game = board(hand: ["Spec Whispered Lesson"], library: library, mana: { U: 1 })
    events = []
    game.subscribe { events << it }
    cast(game, "Spec Whispered Lesson", find: "Grizzly Bears")
    expect(card(game, player(game, "alice").library.first)).to eq("grizzly_bears")
    expect(player(game, "alice").library.size).to eq(7)
    expect(events.map { it.type.to_s }).to include("card_revealed", "library_shuffled")
    expect(events.map { it.type.to_s }.index("card_revealed")).to be < events.map { it.type.to_s }.index("library_shuffled")
  end

  it "offers only cards matching a bound computed from the sacrificed artifact (CR 601.2h, 608.2h)" do
    game = board(battlefield: ["Spec Refitting Dock", "Arc Lantern"], library: ["Spec Three-Cog Engine", "Arc Lantern", "Forest"])
    dock = obj_id(game, "Spec Refitting Dock")
    offered = nil
    resolve(game, { type: "activate", object: dock, ability: "printed:0" }, find: "Spec Three-Cog Engine") do |options|
      offered ||= options.filter_map { it[:object] && card(game, it[:object]) }
    end
    expect(offered).to eq(["spec_three_cog_engine"]) # Arc Lantern's mana value is 2: 3 is wanted
    expect(game.state.battlefield.map { card(game, it) }).to include("spec_three_cog_engine")
    expect(game.state.battlefield.map { card(game, it) }).not_to include("arc_lantern")
  end

  it "takes one card for library_top" do
    bad = tutor.merge("name" => "Spec Bad Lesson", "abilities" => [{ "spell" => { "effects" => [
                        { "search_library" => { "put" => "library_top", "count" => 2 } }
                      ] } }])
    expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition, /count: put library_top takes one card/)
  end
end
