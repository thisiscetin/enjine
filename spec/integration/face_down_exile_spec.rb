# frozen_string_literal: true

# Cards exiled face down (CR 406.3, 406.3a-b): no characteristics, hidden from everyone but the players
# allowed to look, playable through a permission (turned face up as they're played), and "mana of any
# type can be spent to cast them" (CR 609.4b).
RSpec.describe "Face-down exile, look permission and mana of any type (CR 406.3, 609.4b)" do
  let(:exchange) do
    { "name" => "Spec Mind Exchange", "mana_cost" => "{U}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => ["opponent"], "effects" => [
        { "exile_top" => { "amount" => 1, "face_down" => true, "looker" => { "target" => 0 } } },
        { "exile_top" => { "amount" => 2, "to" => { "target" => 0 }, "face_down" => true } },
        { "play_permission" => { "to" => { "result" => 0 }, "to_player" => { "target" => 0 }, "duration" => "while_exiled",
                                 "any_mana_type" => true } },
        { "play_permission" => { "to" => { "result" => 1 }, "duration" => "while_exiled", "any_mana_type" => true } }
      ] } }] }
  end
  let(:catalog) { catalog_with(exchange) }

  # Alice casts the Exchange: Bob gets Alice's top card (a Hill Giant), Alice gets Bob's top two.
  def exchanged(alice_field: %w[Island Island], bob_library: ["Lightning Bolt", "Mountain"])
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Spec Mind Exchange"
        battlefield(*alice_field)
        library "Hill Giant", count: 3
      end
      player("bob") do
        battlefield "Mountain"
        library(*bob_library)
        library "Forest", count: 3
      end
    end
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: "player:bob")
    game.submit(game.legal_options.find { it[:type] == "activate_mana" })
    game.submit(type: "pay_mana", mana: "U")
    pass_both(game)
    game
  end

  def exiled(game, owner) = game.state.exile.select { game.state.object(it).owner == game.names.index(owner) }
  def engine(game) = Enjine::Engine.new(game.catalog, game.state) { nil }

  def face_up_name(game, id)
    eng = engine(game)
    eng.face_up(id) { eng.chars(eng.object(id)).name }
  end

  it "exiles face down with ids that don't name the cards; they have no characteristics (CR 406.3a)" do
    game = exchanged
    expect(game.state.exile.size).to eq(3)
    expect(game.state.exile).to all(start_with("face_down#"))
    card = game.state.object(exiled(game, "alice").first)
    expect(card.memory).to include("face_down" => true, "may_look" => [1])
    expect(engine(game).chars(card).name).to eq("")
    expect(engine(game).chars(card).types).to be_empty
  end

  it "only the players allowed to look see which cards they are, in views and events" do
    game = exchanged
    alice = game.view_for("alice")["exile"]
    expect(alice.select { it["name"] }.map { it["name"] }).to contain_exactly("Lightning Bolt", "Mountain")
    expect(alice.find { it["owner"] == "alice" }).to eq("id" => exiled(game, "alice").first, "face_down" => true, "owner" => "alice")
    bob = game.view_for("bob")["exile"]
    expect(bob.filter_map { it["name"] }).to eq(["Hill Giant"])
    expect(game.view_for(:observer)["exile"].map { it["name"] }).to all(be_a(String))

    bob_events = game.history_for("bob").flat_map { it["events"] }.select { it["type"] == "zone_changed" && it["to"] == "exile" }
    expect(bob_events.size).to eq(3)
    expect(bob_events.count { it.key?("card") }).to eq(1) # his own Hill Giant pick
    expect(bob_events.reject { it.key?("card") }).to all(include("face_down" => true))
    expect(bob_events.map { it["old_id"] }.compact.size).to eq(1)
  end

  it "the permission lets a player who may look cast it, spending mana of any type (CR 406.3b, 609.4b)" do
    game = exchanged(alice_field: %w[Island Island Island])
    bolt = exiled(game, "bob").find { face_up_name(game, it) == "Lightning Bolt" }
    option = game.legal_options.find { it[:type] == "cast" && it[:object] == bolt }
    expect(option).not_to be_nil
    expect(game.legal_options).not_to include(hash_including(type: "cast", object: exiled(game, "alice").first))
    game.submit(option)
    game.submit(type: "target", target: "player:bob")
    game.submit(game.legal_options.find { it[:type] == "activate_mana" })
    expect(game.legal_options).to include({ type: "pay_mana", mana: "U" })
    game.submit(type: "pay_mana", mana: "U")
    expect(game.view_for("bob")["stack"].first["name"]).to eq("Lightning Bolt") # face up on the stack
    pass_both(game)
    expect(game.state.players[1].life).to eq(17)
  end

  it "a land is played face up from exile with a play permission" do
    game = exchanged
    mountain = exiled(game, "bob").find { face_up_name(game, it) == "Mountain" }
    option = game.legal_options.find { it[:type] == "play_land" && it[:object] == mountain }
    expect(option).not_to be_nil
    game.submit(option)
    land = game.state.battlefield.map { game.state.object(it) }.find { it.card == "mountain" && it.owner == 1 && it.controller == 0 }
    expect(land).not_to be_nil # CR 305.1: played by Alice, so she controls Bob's Mountain
    expect(land.id).to start_with("mountain#")
  end

  it "a cancelled cast puts the card back face down (CR 734.1)" do
    game = exchanged(alice_field: %w[Island Island Island])
    bolt = game.legal_options.find { it[:type] == "cast" && game.state.object(it[:object]).zone == :exile }[:object]
    game.submit(game.legal_options.find { it[:type] == "cast" && it[:object] == bolt })
    game.submit(type: "cancel")
    expect(game.state.object(bolt).memory).to include("face_down" => true, "may_look" => [0])
    expect(game.view_for("bob")["exile"].find { it["id"] == bolt }).not_to have_key("name")
  end

  it "round-trips through a snapshot, and the validator rejects a face-down id outside exile" do
    game = exchanged
    data = game.state.to_h
    reloaded = Enjine::Game.import({ "state" => data }, catalog: catalog)
    expect(reloaded.state.exile).to eq(game.state.exile)
    obj = data["objects"].find { it["id"].start_with?("face_down#") }
    obj["memory"] = {}
    expect { Enjine::Game.import({ "state" => data }, catalog: catalog) }.to raise_error(Enjine::InvalidSnapshot, /malformed/)
  end

  it "validates face_down, looker, player and any_mana_type" do
    errors = lambda do |effect|
      Enjine::CardDefinition.from_h("name" => "Spec Bad Exile", "mana_cost" => "{U}", "types" => ["sorcery"],
                                    "abilities" => [{ "spell" => { "effects" => [effect] } }])
      []
    rescue Enjine::InvalidCardDefinition => e
      e.errors
    end
    expect(errors.call("exile_top" => { "amount" => 1, "looker" => "you" }).first).to include("looker: needs face_down")
    expect(errors.call("exile_top" => { "amount" => 1, "face_down" => "yes" }).first).to include("face_down: must be")
    expect(errors.call("play_permission" => { "to" => "you", "any_mana_type" => 1 }).first).to include("any_mana_type: must be")
    defn = Enjine::CardDefinition.from_h(exchange)
    texts = defn.spell_ability.effects.map(&:to_s)
    expect(texts.first).to include("face down")
    expect(texts[2]).to include("mana of any type")
  end
end
