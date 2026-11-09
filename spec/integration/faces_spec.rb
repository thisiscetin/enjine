# frozen_string_literal: true

# Cards with more than one face: double-faced cards (CR 712, 701.27), adventurer cards (CR 716), omen
# cards (CR 721) and preparation cards (CR 723). All card names are invented.
RSpec.describe "Multi-face cards (CR 712, 716, 721, 723)" do
  let(:apprentice) do
    { "name" => "Moonlit Apprentice // Howling Adept", "layout" => "transform", "faces" => [
      { "name" => "Moonlit Apprentice", "mana_cost" => "{1}{G}", "types" => ["creature"], "subtypes" => ["human"],
        "power" => 2, "toughness" => 2,
        "abilities" => [
          { "activated" => { "cost" => [{ "mana" => "{2}" }], "effects" => [{ "transform" => {} }] } },
          { "triggered" => { "when" => { "any_of" => [{ "enters" => {} }, { "transforms" => {} }] },
                             "effects" => [{ "gain_life" => { "amount" => 1 } }] } }
        ] },
      { "name" => "Howling Adept", "colors" => ["G"], "types" => ["creature"], "subtypes" => ["wolf"],
        "keywords" => ["trample"], "power" => 4, "toughness" => 4,
        "abilities" => [
          { "triggered" => { "when" => { "transforms" => {} }, "effects" => [{ "draw" => { "amount" => 1 } }] } },
          { "activated" => { "cost" => [{ "mana" => "{G}" }], "effects" => [{ "transform" => { "to" => "self" } }] } }
        ] }
    ] }
  end
  let(:rite) do # a sorcery front that puts itself onto the battlefield transformed (CR 712.11a)
    { "name" => "Rite of Waking // Woken Grove", "layout" => "transform", "faces" => [
      { "name" => "Rite of Waking", "mana_cost" => "{G}", "types" => ["sorcery"],
        "abilities" => [{ "spell" => { "effects" => [{ "gain_life" => { "amount" => 2 } }] } }] },
      { "name" => "Woken Grove", "colors" => ["G"], "types" => ["enchantment"] }
    ] }
  end
  let(:phaser) do # "exile it, then return it to the battlefield transformed"
    { "name" => "Phasing Scholar // Phased Sage", "layout" => "transform", "faces" => [
      { "name" => "Phasing Scholar", "mana_cost" => "{U}", "types" => ["creature"], "power" => 1, "toughness" => 1,
        "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{1}" }], "effects" => [
          { "exile" => { "to" => "self" } },
          { "return_to_battlefield" => { "to" => { "result" => 0 }, "transformed" => true } }
        ] } }] },
      { "name" => "Phased Sage", "colors" => ["U"], "types" => ["creature"], "power" => 3, "toughness" => 3,
        "abilities" => [{ "triggered" => { "when" => { "dies" => {} }, "effects" => [{ "gain_life" => { "amount" => 3 } }] } }] }
    ] }
  end
  let(:mdfc) do
    { "name" => "Tinker Lad // Tinker Titan", "layout" => "modal", "faces" => [
      { "name" => "Tinker Lad", "mana_cost" => "{G}", "types" => ["creature"], "power" => 1, "toughness" => 1 },
      { "name" => "Tinker Titan", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 5, "toughness" => 5 }
    ] }
  end
  let(:mdfc_land) do
    { "name" => "Verdant Choice // Verdant Hollow", "layout" => "modal", "faces" => [
      { "name" => "Verdant Choice", "mana_cost" => "{1}{G}", "types" => ["sorcery"],
        "abilities" => [{ "spell" => { "effects" => [{ "gain_life" => { "amount" => 3 } }] } }] },
      { "name" => "Verdant Hollow", "types" => ["land"], "abilities" => [
        "enters_tapped", { "mana" => { "cost" => ["tap"], "produce" => "{G}" } }
      ] }
    ] }
  end
  let(:knight) do
    { "name" => "Brambleknight // Prick the Path", "layout" => "adventure", "faces" => [
      { "name" => "Brambleknight", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 3, "toughness" => 3 },
      { "name" => "Prick the Path", "mana_cost" => "{G}", "types" => ["sorcery"], "subtypes" => ["adventure"],
        "abilities" => [{ "spell" => { "effects" => [{ "gain_life" => { "amount" => 2 } }] } }] }
    ] }
  end
  let(:drake) do
    { "name" => "Stormwing Drake // Gust Omen", "layout" => "omen", "faces" => [
      { "name" => "Stormwing Drake", "mana_cost" => "{3}{G}", "types" => ["creature"], "power" => 4, "toughness" => 4 },
      { "name" => "Gust Omen", "mana_cost" => "{G}", "types" => ["instant"], "subtypes" => ["omen"],
        "abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
    ] }
  end
  let(:initiate) do
    { "name" => "Lorekeeper Initiate // Recall Notes", "layout" => "prepare", "faces" => [
      { "name" => "Lorekeeper Initiate", "mana_cost" => "{G}", "types" => ["creature"], "power" => 1, "toughness" => 3,
        "abilities" => ["enters_prepared",
                        { "activated" => { "cost" => [{ "mana" => "{1}" }], "effects" => [{ "unprepare" => {} }] } }] },
      { "name" => "Recall Notes", "mana_cost" => "{G}", "types" => ["sorcery"],
        "abilities" => [{ "spell" => { "effects" => [{ "gain_life" => { "amount" => 4 } }] } }] }
    ] }
  end
  let(:duelist) do
    { "name" => "Studious Duelist // Quick Riposte", "layout" => "prepare", "faces" => [
      { "name" => "Studious Duelist", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 2, "toughness" => 2,
        "abilities" => [{ "activated" => { "cost" => ["tap"], "effects" => [{ "prepare" => {} }] } }] },
      { "name" => "Quick Riposte", "mana_cost" => "{G}", "types" => ["instant"],
        "abilities" => [{ "spell" => { "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
    ] }
  end
  let(:mirror) do
    { "name" => "Glassy Mimic", "mana_cost" => "{G}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [
        { "create_token_copy" => { "of" => { "target" => 0 } } }
      ] } }] }
  end
  let(:catalog) { catalog_with(apprentice, rite, phaser, mdfc, mdfc_land, knight, drake, initiate, duelist, mirror) }

  def board(hand: [], battlefield: [], forests: 4, library: 5)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand(*hand) unless hand.empty?
        battlefield(*battlefield) unless battlefield.empty?
        battlefield "Forest", count: forests
        library "Forest", count: library
      end
      player("bob") { library "Forest", count: 5 }
    end
  end

  def pay_all(game)
    while game.pending_decision&.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)
  # The game caches its legal options; direct engine calls in a spec change the state behind its back.
  def refresh(game) = game.instance_variable_set(:@version, game.instance_variable_get(:@version) + 1)
  def face_on_battlefield(game, card) = game.state.battlefield.find { game.state.object(it).card == card } || raise("no #{card}")
  def card_id(game, name) = obj_id(game, name, zone: :hand, player: "alice")
  def life(game, name = "alice") = game.view_for(:observer)["players"].find { it["name"] == name }["life"]
  def resolve(game, times = 1) = pass_both(game, times)

  def activate(game, id, index = 0)
    ref = game.legal_options.find { it[:type] == "activate" && it[:object] == id && it[:ability].end_with?(":#{index}") }
    game.submit(ref || raise("no activation #{index} of #{id}"))
    pay_all(game)
  end

  describe "transforming double-faced cards (CR 712.2, 701.27)" do
    it "has only its front face's characteristics outside the battlefield (CR 712.6a)" do
      game = board(hand: ["Moonlit Apprentice"])
      id = card_id(game, "moonlit_apprentice")
      expect(engine(game).chars(id).name).to eq("Moonlit Apprentice")
      expect(game.legal_options).not_to include(a_hash_including(object: id, face: 1)) # CR 712.8: front face only
    end

    it "transforms into its back face, keeps effects and triggers 'transforms into' (CR 701.27a, 701.27c, 701.27f)" do
      game = board(battlefield: ["Moonlit Apprentice"])
      id = obj_id(game, "moonlit_apprentice")
      activate(game, id)
      resolve(game) # the transform ability resolves
      expect(game.state.object(id).card).to eq("moonlit_apprentice/1")
      expect(engine(game).chars(id).name).to eq("Howling Adept")
      expect(engine(game).power_toughness(game.state.object(id))).to eq([4, 4])
      expect(engine(game).transformed?(game.state.object(id))).to be(true)
      expect(view_of(game, id)).to include("transformed" => true, "name" => "Howling Adept")
      expect(game.history.flat_map(&:events).map(&:type)).to include("transformed")
      hand = game.state.players[0].hand.size
      resolve(game) # the back face's "transforms" trigger
      expect(game.state.players[0].hand.size).to eq(hand + 1)
    end

    it "triggers the front face's 'enters or transforms into' when it transforms back (CR 701.27f)" do
      game = board(battlefield: ["Moonlit Apprentice"])
      id = obj_id(game, "moonlit_apprentice")
      activate(game, id)
      resolve(game, 2) # transforms, then the back face's trigger
      activate(game, id, 1)
      resolve(game)
      expect(engine(game).chars(id).name).to eq("Moonlit Apprentice")
      resolve(game)
      expect(life(game)).to eq(21)
    end

    it "is turned front face up by a zone change (CR 712.6a, 400.7)" do
      game = board(battlefield: ["Moonlit Apprentice"])
      id = obj_id(game, "moonlit_apprentice")
      engine(game).transform!(game.state.object(id))
      fresh = engine(game).move!(id, :hand, reason: "test")
      expect(fresh.card).to eq("moonlit_apprentice")
    end

    it "ignores a second transform from an ability put on the stack before it transformed (CR 701.27g)" do
      game = board(battlefield: ["Moonlit Apprentice"])
      id = obj_id(game, "moonlit_apprentice")
      activate(game, id)
      game.submit(type: "pass") # bob gets priority; alice holds none
      engine(game).transform!(game.state.object(id)) # it transforms first
      expect(engine(game).chars(id).name).to eq("Howling Adept")
      game.submit(type: "pass")
      expect(engine(game).chars(id).name).to eq("Howling Adept")
    end

    it "doesn't transform a permanent that isn't double-faced, or into an instant or sorcery face (CR 701.27d-e)" do
      game = board(battlefield: ["Grizzly Bears"])
      bear = game.state.object(obj_id(game, "grizzly_bears"))
      expect(engine(game).transform!(bear)).to be(false)
      expect(engine(game).transformed?(bear)).to be(false)
    end

    it "returns to the battlefield transformed (CR 712.11a) and stays put if it can't (CR 712.11b)" do
      game = board(battlefield: ["Phasing Scholar"])
      id = obj_id(game, "phasing_scholar")
      activate(game, id)
      resolve(game)
      sage = face_on_battlefield(game, "phasing_scholar/1")
      expect(engine(game).chars(sage).name).to eq("Phased Sage")
      expect(view_of(game, sage)).to include("power" => 3)
    end

    it "triggers the back face's leaves-the-battlefield ability as it last existed (CR 603.10a)" do
      game = board(battlefield: ["Phasing Scholar"])
      activate(game, obj_id(game, "phasing_scholar"))
      resolve(game)
      sage = face_on_battlefield(game, "phasing_scholar/1")
      engine(game).move!(sage, :graveyard, reason: "destroy")
      expect(game.state.object(game.state.players[0].graveyard.first).card).to eq("phasing_scholar")
      refresh(game)
      game.submit(type: "pass") # the dies trigger goes on the stack first
      resolve(game)
      expect(life(game)).to eq(23)
    end

    it "copies the face that's up; a token copy is double-faced and can transform (CR 707.8, 707.8a)" do
      game = board(hand: ["Glassy Mimic"], battlefield: ["Moonlit Apprentice"])
      id = obj_id(game, "moonlit_apprentice")
      engine(game).transform!(game.state.object(id))
      refresh(game)
      game.submit(type: "cast", object: card_id(game, "glassy_mimic"))
      game.submit(type: "target", target: id)
      pay_all(game)
      resolve(game, 2) # the transform trigger, then the copy spell
      token = game.state.battlefield.find { game.state.object(it).memory["token"] }
      expect(engine(game).chars(token).name).to eq("Howling Adept")
      expect(engine(game).transform!(game.state.object(token))).to be(true)
      expect(engine(game).chars(token).name).to eq("Moonlit Apprentice")
    end

    it "doesn't transform a non-double-faced permanent copying a back face (CR 701.27d)" do
      game = board(battlefield: ["Grizzly Bears"])
      bear = game.state.object(obj_id(game, "grizzly_bears"))
      engine(game).become_copy!(bear, ["moonlit_apprentice/1", {}])
      expect(engine(game).chars(bear).name).to eq("Howling Adept")
      expect(engine(game).transform!(bear)).to be(false)
    end

    it "transforms a double-faced card that is copying something else under the copy effect (CR 701.27d example)" do
      game = board(battlefield: ["Moonlit Apprentice"])
      obj = game.state.object(obj_id(game, "moonlit_apprentice"))
      engine(game).become_copy!(obj, ["grizzly_bears", {}], duration: "end_of_turn")
      expect(engine(game).transform!(obj)).to be(true)
      expect(engine(game).chars(obj).name).to eq("Grizzly Bears")
      engine(game).end_copy_effects!
      expect(engine(game).chars(obj).name).to eq("Howling Adept")
    end

    it "puts a sorcery front's own permanent onto the battlefield transformed via an effect" do
      game = board(hand: ["Rite of Waking"])
      rite = card_id(game, "rite_of_waking")
      game.submit(type: "cast", object: rite)
      pay_all(game)
      resolve(game)
      grave = game.state.players[0].graveyard.find { game.state.object(it).card == "rite_of_waking" }
      expect(grave).not_to be_nil # a resolved transforming card goes to the graveyard front face up
      engine(game).enter_battlefield!({}, [[grave, 0, { "face" => 1 }]], reason: "test")
      expect(face_on_battlefield(game, "rite_of_waking/1")).not_to be_nil
    end
  end

  describe "modal double-faced cards (CR 712.3, 712.8b, 712.9)" do
    it "offers each face to cast and puts the chosen face on the stack and battlefield (CR 712.8b, 712.10)" do
      game = board(hand: ["Tinker Lad"])
      id = card_id(game, "tinker_lad")
      expect(game.legal_options).to include({ type: "cast", object: id }, { type: "cast", object: id, face: 1 })
      game.submit(type: "cast", object: id, face: 1)
      expect(game.view_for(:observer)["stack"].first["name"]).to eq("Tinker Titan")
      pay_all(game)
      resolve(game)
      titan = face_on_battlefield(game, "tinker_lad/1")
      expect(view_of(game, titan)).to include("power" => 5)
      expect(engine(game).transformed?(game.state.object(titan))).to be(true)
    end

    it "evaluates only the chosen face's cost (CR 712.8c)" do
      game = board(hand: ["Tinker Lad"], forests: 1)
      id = card_id(game, "tinker_lad")
      expect(game.legal_options).to include({ type: "cast", object: id })
      expect(game.legal_options).not_to include(a_hash_including(object: id, face: 1))
    end

    it "goes back to the hand front face up when the cast is cancelled (CR 734.1)" do
      game = board(hand: ["Tinker Lad"])
      game.submit(type: "cast", object: card_id(game, "tinker_lad"), face: 1)
      game.submit(type: "cancel")
      expect(game.state.object(card_id(game, "tinker_lad")).card).to eq("tinker_lad")
    end

    it "plays a land face, with that face's own entering replacement (CR 712.9, 614.12)" do
      game = board(hand: ["Verdant Choice"])
      id = card_id(game, "verdant_choice")
      expect(game.legal_options).to include({ type: "play_land", object: id, face: 1 })
      game.submit(type: "play_land", object: id, face: 1)
      land = face_on_battlefield(game, "verdant_choice/1")
      expect(game.state.object(land).tapped).to be(true)
      expect(engine(game).chars(land).land?).to be(true)
    end

    it "casts the sorcery face normally" do
      game = board(hand: ["Verdant Choice"])
      game.submit(type: "cast", object: card_id(game, "verdant_choice"))
      pay_all(game)
      resolve(game)
      expect(life(game)).to eq(23)
    end
  end

  describe "adventurer cards (CR 716)" do
    it "casts the Adventure, exiles it on resolution and lets its owner cast the creature later (CR 716.3, 716.3d)" do
      game = board(hand: ["Brambleknight"])
      id = card_id(game, "brambleknight")
      game.submit(type: "cast", object: id, face: 1)
      expect(game.view_for(:observer)["stack"].first["name"]).to eq("Prick the Path")
      pay_all(game)
      resolve(game)
      expect(life(game)).to eq(22)
      exiled = game.state.exile.first
      expect(game.state.object(exiled).card).to eq("brambleknight")
      options = game.legal_options.select { it[:object] == exiled }
      expect(options).to contain_exactly(a_hash_including(type: "cast", via: start_with("effect:")))
      game.submit(options.first)
      pay_all(game)
      resolve(game)
      expect(obj_id(game, "brambleknight")).not_to be_nil
    end

    it "goes to the graveyard when the Adventure doesn't resolve (CR 716.3d, 608.2b)" do
      game = board(hand: ["Brambleknight"])
      game.submit(type: "cast", object: card_id(game, "brambleknight"), face: 1)
      pay_all(game)
      spell = game.state.stack.first
      engine(game).move!(spell, :graveyard, reason: "countered")
      expect(game.state.object(game.state.players[0].graveyard.first).card).to eq("brambleknight")
    end
  end

  describe "omen cards (CR 721)" do
    it "shuffles a resolved Omen into its owner's library (CR 721.3d)" do
      game = board(hand: ["Stormwing Drake"])
      game.submit(type: "cast", object: card_id(game, "stormwing_drake"), face: 1)
      pay_all(game)
      library = game.state.players[0].library.size
      resolve(game)
      expect(game.state.players[0].library.size).to eq(library) # drew one, the Omen went in
      expect(game.state.players[0].library.map { game.state.object(it).card }).to include("stormwing_drake")
      expect(game.history.flat_map(&:events).map(&:type)).to include("library_shuffled")
    end
  end

  describe "preparation cards (CR 723)" do
    it "enters prepared, and its controller may cast a copy of the prepare spell (CR 723.3a, 723.3c)" do
      game = board(hand: ["Lorekeeper Initiate"])
      game.submit(type: "cast", object: card_id(game, "lorekeeper_initiate"))
      pay_all(game)
      resolve(game)
      perm = game.state.object(obj_id(game, "lorekeeper_initiate"))
      expect(engine(game).prepared?(perm)).to be(true)
      expect(view_of(game, perm.id)).to include("prepared" => true)
      copy = game.state.exile.first
      expect(engine(game).chars(copy).name).to eq("Recall Notes")
      cast = game.legal_options.find { it[:type] == "cast" && it[:object] == copy }
      game.submit(cast)
      expect(engine(game).prepared?(perm)).to be(true) # not until it becomes cast
      pay_all(game)
      expect(engine(game).prepared?(perm)).to be(false) # CR 723.3c: unprepared as it becomes cast
      resolve(game)
      expect(life(game)).to eq(24)
      engine(game).check_state_based_actions!
      expect(game.state.players[0].graveyard).to be_empty # the copy ceased to exist (CR 707.12)
    end

    it "keeps it prepared when the cast of the copy is cancelled" do
      game = board(battlefield: ["Studious Duelist"])
      perm = game.state.object(obj_id(game, "studious_duelist"))
      engine(game).prepare!(perm)
      refresh(game)
      copy = game.state.exile.first
      game.submit(game.legal_options.find { it[:type] == "cast" && it[:object] == copy })
      game.submit(type: "cancel")
      engine(game).check_state_based_actions!
      expect(game.state.exile).to eq([copy])
      expect(engine(game).prepared?(perm)).to be(true)
    end

    it "loses the copy when it becomes unprepared or leaves the battlefield (CR 723.3b, 723.3c)" do
      game = board(battlefield: ["Studious Duelist"])
      perm = game.state.object(obj_id(game, "studious_duelist"))
      activate(game, perm.id)
      resolve(game)
      expect(game.state.exile.size).to eq(1)
      expect(engine(game).prepare!(perm)).to be(false) # already prepared (CR 723.3a)
      engine(game).unprepare!(perm)
      engine(game).check_state_based_actions!
      expect(game.state.exile).to be_empty
      expect(engine(game).unprepare!(perm)).to be(false)
      engine(game).prepare!(perm)
      engine(game).move!(perm.id, :graveyard, reason: "test")
      engine(game).check_state_based_actions!
      expect(game.state.exile).to be_empty
    end

    it "can't prepare a permanent without a prepare spell (CR 723.3a)" do
      game = board(battlefield: ["Grizzly Bears"])
      expect(engine(game).prepare!(game.state.object(obj_id(game, "grizzly_bears")))).to be(false)
    end

    it "round-trips faces and the prepared designation through a snapshot" do
      game = board(battlefield: ["Studious Duelist", "Moonlit Apprentice"])
      engine(game).prepare!(game.state.object(obj_id(game, "studious_duelist")))
      engine(game).transform!(game.state.object(obj_id(game, "moonlit_apprentice")))
      copy = Enjine::Game.import(game.to_h, catalog: catalog)
      expect(copy.state.to_h).to eq(game.state.to_h)
      expect(engine(copy).prepared?(copy.state.object(obj_id(copy, "studious_duelist")))).to be(true)
    end
  end

  describe "filters" do
    it "matches transformed and prepared permanents (CR 701.27h, 723.3a)" do
      game = board(battlefield: ["Studious Duelist", "Moonlit Apprentice"])
      duelist = obj_id(game, "studious_duelist")
      apprentice = obj_id(game, "moonlit_apprentice")
      engine(game).prepare!(game.state.object(duelist))
      engine(game).transform!(game.state.object(apprentice))
      errors = []
      prepared = Enjine::Mechanics.build_entry(:filter, { "creature" => { "prepared" => true } }, errors, "f")
      unprepared = Enjine::Mechanics.build_entry(:filter, { "creature" => { "prepared" => false } }, errors, "f")
      transformed = Enjine::Mechanics.build_entry(:filter, { "creature" => { "transformed" => true } }, errors, "f")
      expect(errors).to be_empty
      expect(prepared.candidates(engine(game), 0)).to eq([duelist])
      expect(unprepared.candidates(engine(game), 0)).to eq([apprentice])
      expect(transformed.candidates(engine(game), 0)).to eq([apprentice])
      expect([prepared, unprepared, transformed].map(&:to_s)).to eq(["prepared creature", "unprepared creature",
                                                                     "transformed creature"])
    end
  end
end
