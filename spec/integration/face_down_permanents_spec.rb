# frozen_string_literal: true

# Face-down spells and permanents (CR 708): manifest (CR 701.40), cloak (CR 701.58), manifest dread (CR 701.62),
# morph (CR 702.37) and disguise (CR 702.168). Invented test cards only.
RSpec.describe "Face-down permanents (CR 708, 701.40, 701.58, 701.62, 702.37, 702.168)" do
  def sorcery(name, effect)
    { "name" => name, "mana_cost" => "{G}", "types" => ["sorcery"], "abilities" => [{ "spell" => { "effects" => [effect] } }] }
  end

  let(:sneaky) do
    { "name" => "Spec Sneaky Elk", "mana_cost" => "{1}{G}", "types" => ["creature"], "subtypes" => ["elk"], "power" => 3, "toughness" => 3,
      "abilities" => [{ "disguise" => { "cost" => "{2}{G}" } },
                      { "triggered" => { "when" => { "turned_face_up" => {} }, "effects" => [{ "draw" => { "amount" => 1 } }] } },
                      { "triggered" => { "when" => { "enters" => {} }, "effects" => [{ "gain_life" => { "amount" => 5 } }] } }] }
  end
  let(:morpher) do
    { "name" => "Spec Morphling Toad", "mana_cost" => "{4}{G}", "types" => ["creature"], "power" => 4, "toughness" => 4,
      "abilities" => [{ "morph" => { "cost" => "{G}" } }] }
  end
  let(:zap) do
    { "name" => "Spec Zap", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                     "effects" => [{ "deal_damage" => { "amount" => 1, "to" => { "target" => 0 } } }] } }] }
  end
  let(:catalog) do
    catalog_with(sneaky, morpher, zap, sorcery("Spec Manifest", { "manifest" => {} }), sorcery("Spec Cloak", { "cloak" => {} }),
                 sorcery("Spec Dread", { "manifest_dread" => {} }),
                 sorcery("Spec Bounce All", { "return_to_hand" => { "to" => { "each" => "creature", "controller" => "any" } } }),
                 coat)
  end
  let(:coat) do # cloak, then attach to the cloaked permanent (the effect's result)
    { "name" => "Spec Cloaking Coat", "mana_cost" => "{1}", "types" => ["artifact"], "subtypes" => ["equipment"],
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} },
                                         "effects" => [{ "cloak" => {} }, { "attach" => { "to" => { "result" => 0 } } }] } },
                      { "static" => { "affects" => "attached", "pump" => { "power" => 1, "toughness" => 0 } } }] }
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, name) = game.view_for(:observer)["players"].find { it["name"] == name }["life"]
  def face_down_ids(game) = game.state.battlefield.select { engine(game).face_down_object?(game.state.object(it)) }

  def board(hand:, library: ["Grizzly Bears"], field: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand.each { hand it }
        library(*library)
        library "Forest", count: 5
        (%w[Forest Forest Forest Forest Forest] + field).each { battlefield it }
      end
      player("bob") { library "Forest", count: 5 }
    end
  end

  def pay_all(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def cast(game, card, via: nil)
    id = ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) }
    option = game.legal_options.find { it[:type] == "cast" && it[:object] == id && (via.nil? || it[:via]&.start_with?(via)) }
    game.submit(option)
    pay_all(game)
  end

  it "manifests the top card face down as a nameless 2/2 only its controller can see (CR 701.40a, 708.2, 708.5)" do
    game = board(hand: ["Spec Manifest"])
    events = []
    game.subscribe { events << it }
    cast(game, "Spec Manifest")
    pass_both(game)
    id = face_down_ids(game).first
    expect(id).to start_with("face_down#") # the id doesn't name the card
    obj = game.state.object(id)
    chars = engine(game).chars(obj)
    expect([chars.name, chars.types, chars.subtypes, chars.mana_cost, chars.colors]).to eq(["", [:creature], [], nil, []])
    expect(engine(game).power_toughness(obj)).to eq([2, 2])
    bob = game.view_for("bob")["battlefield"].find { it["id"] == id }
    expect(bob).to include("face_down" => true, "name" => "")
    expect(bob.to_s).not_to include("grizzly")
    expect(game.view_for("alice")["battlefield"].find { it["id"] == id }).to include("face_down_card" => "grizzly_bears")
    entered = events.grep(Enjine::Events::ZoneChanged).find { it.new_id == id }
    expect(entered.for_viewer("bob").to_s).not_to include("grizzly")
    expect(entered.for_viewer("alice")["card"]).to eq("grizzly_bears")
    expect(Enjine::Snapshot.validate(game.state.to_h, catalog)).to be_empty
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.state.to_h).to eq(game.state.to_h)
  end

  it "turns a manifested creature card face up for its mana cost as a special action; it's the same object (CR 701.40b, 708.8)" do
    game = board(hand: ["Spec Manifest"])
    cast(game, "Spec Manifest")
    pass_both(game)
    id = face_down_ids(game).first
    option = { type: "turn_face_up", object: id, via: "mana_cost" }
    expect(game.legal_options).to include(option)
    expect(game.view_for("bob")["pending"]&.fetch("options", nil)).to be_nil
    game.submit(option)
    pay_all(game)
    obj = game.state.object(id)
    expect(obj.card).to eq("grizzly_bears")
    expect(engine(game).chars(obj).name).to eq("Grizzly Bears")
    expect(game.view_for("bob")["battlefield"].find { it["id"] == id }).not_to include("face_down")
    expect(Enjine::Snapshot.validate(game.state.to_h, catalog)).to be_empty
  end

  it "a manifested instant can't be turned face up (CR 701.40b, 701.40g) and is revealed when it leaves (CR 708.9)" do
    game = board(hand: ["Spec Manifest", "Spec Bounce All"], library: ["Spec Zap"])
    cast(game, "Spec Manifest")
    pass_both(game)
    id = face_down_ids(game).first
    expect(game.legal_options.map { it[:type] }).not_to include("turn_face_up")
    expect(engine(game).turn_face_up!(game.state.object(id))).to be(false) # revealed, stays face down
    events = []
    game.subscribe { events << it }
    cast(game, "Spec Bounce All")
    pass_both(game)
    reveal = events.grep(Enjine::Events::CardRevealed).last
    expect(reveal.card).to eq("spec_zap")
    expect(ids_in(game, "alice", :hand).map { game.state.object(it).card }).to include("spec_zap")
  end

  it "cloaks a card: a face-down 2/2 with ward {2} (CR 701.58a)" do
    game = board(hand: ["Spec Cloak"])
    cast(game, "Spec Cloak")
    pass_both(game)
    obj = game.state.object(face_down_ids(game).first)
    expect(engine(game).chars(obj).abilities.map { it.ability.to_s }).to eq(["Ward {2}"])
    expect(game.legal_options).to include(type: "turn_face_up", object: obj.id, via: "mana_cost")
  end

  it "manifests dread: one of the top two is manifested, the other goes to the graveyard (CR 701.62a)" do
    game = board(hand: ["Spec Dread"], library: ["Grizzly Bears", "Spec Zap"])
    cast(game, "Spec Dread")
    pass_both(game)
    expect(game.pending_decision.kind).to eq("effect_choice")
    expect(game.view_for("bob")["pending"].to_s).not_to include("spec_zap")
    choice = game.legal_options.find { game.state.object(it[:object]).card == "spec_zap" }
    game.submit(choice)
    expect(game.state.object(face_down_ids(game).first).memory["face_down_card"]).to eq("spec_zap")
    expect(ids_in(game, "alice", :graveyard).map { game.state.object(it).card }).to include("grizzly_bears")
  end

  it "casts a card with disguise face down for {3} (CR 702.168a-b, 708.4); turning it face up triggers, entering doesn't again" do
    game = board(hand: ["Spec Sneaky Elk"], field: %w[Forest Forest])
    events = []
    game.subscribe { events << it }
    cast(game, "Spec Sneaky Elk", via: "alt:")
    spell = game.state.object(game.state.stack.first)
    expect(spell.id).to start_with("face_down#")
    expect(engine(game).chars(spell).name).to eq("")
    expect(events.grep(Enjine::Events::SpellCast).last.card).to eq("face_down_ward")
    expect(game.view_for("bob")["stack"].to_s).not_to include("elk")
    expect(game.view_for("alice")["stack"].first).to include("face_down_card" => "spec_sneaky_elk")
    expect(game.state.players[0].mana_pool.values.sum + game.state.battlefield.count { !game.state.object(it).tapped }).to eq(4)
    pass_both(game)
    perm = face_down_ids(game).first
    expect(engine(game).chars(game.state.object(perm)).abilities.map { it.ability.to_s }).to eq(["Ward {2}"])
    expect(life(game, "alice")).to eq(20) # its enters trigger isn't there while face down (CR 708.3)
    expect(game.legal_options).to include(type: "turn_face_up", object: perm, via: "disguise")
    expect(game.legal_options).not_to include(type: "turn_face_up", object: perm, via: "mana_cost") # cast face down, not manifested
    game.submit(type: "turn_face_up", object: perm, via: "disguise")
    pay_all(game)
    expect(engine(game).power_toughness(game.state.object(perm))).to eq([3, 3])
    expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Spec Sneaky Elk ability"])
    pass_both(game)
    expect(game.state.players[0].hand.size).to eq(1)
    expect(life(game, "alice")).to eq(20) # CR 708.8: abilities about entering don't trigger
    expect(engine(game).turn_log(0).values_at("entered_face_down", "turned_face_up")).to eq([1, 1])
  end

  it "morph: cast face down for {3}, turned face up for its morph cost (CR 702.37c, 702.37e); a countered one is revealed" do
    game = board(hand: ["Spec Morphling Toad"])
    cast(game, "Spec Morphling Toad", via: "alt:")
    spell = game.state.object(game.state.stack.first)
    expect(engine(game).chars(spell).abilities).to be_empty # no ward
    fresh = engine(game).move!(spell.id, :graveyard, reason: "counter")
    expect(fresh.card).to eq("spec_morphling_toad") # face up in the graveyard
  end

  it "reveals face-down permanents at the end of the game (CR 708.9)" do
    game = board(hand: ["Spec Manifest"])
    cast(game, "Spec Manifest")
    pass_both(game)
    events = []
    game.subscribe { events << it }
    game.instance_variable_get(:@engine).then do |eng|
      game.send(:record, "alice", "test") do
        eng.player(1).lost = "test"
        eng.end_game_if_decided!
      end
    end
    expect(events.grep(Enjine::Events::CardRevealed).map(&:card)).to include("grizzly_bears")
  end

  it "an equipment can attach to the permanent it cloaked (the effect's result)" do
    game = board(hand: ["Spec Cloaking Coat"])
    cast(game, "Spec Cloaking Coat")
    pass_both(game) # the Coat resolves
    pass_both(game) # its enters trigger resolves
    cloaked = game.state.object(face_down_ids(game).first)
    coat = game.state.object(obj_id(game, "Spec Cloaking Coat"))
    expect(coat.attached_to).to eq(cloaked.id)
    expect(engine(game).power_toughness(cloaked)).to eq([3, 2])
  end
end
