# frozen_string_literal: true

# Real cards from Secrets of Strixhaven (sos), Reality Fracture (fra) and Star Trek (trk), written by hand in
# the card DSL (spec/fixtures/cards/real/newest-sets.json): each one is cast, played or activated and its
# effect checked. Pet Sehlat (a vanilla 4/3) and Stone Docent (a 3/1) stand in as plain creatures.
RSpec.describe "Real cards: Secrets of Strixhaven, Reality Fracture, Star Trek" do
  let(:cards) { CardFixtures.real("newest-sets") }
  let(:catalog) { Enjine::Catalog.from_definitions(cards) }

  # Alice's turn 3 (precombat main unless `step`). Permanents are names or [name, options]; `mana` and
  # `their_mana` are the players' mana pools.
  def board(hand: [], battlefield: [], graveyard: [], library: ["Island"] * 10, theirs: [], their_hand: [],
            mana: {}, their_mana: {}, step: :precombat_main, active: "alice")
    build_game(catalog) do
      turn 3, active: active, step: step
      player("alice", mana_pool: mana) do
        hand(*hand)
        graveyard(*graveyard)
        library(*library)
        battlefield.each { |card, opts| battlefield card, **(opts || {}) }
      end
      player("bob", mana_pool: their_mana) do
        hand(*their_hand)
        library "Swamp", count: 10
        theirs.each { |card, opts| battlefield card, **(opts || {}) }
      end
    end
  end

  # Submits `action` (if any), answers each further decision with the next of `answers` (an option, or a
  # block taking the game), pays costs from the mana pool and, with `resolve`, passes until the stack is empty.
  def play(game, action, *answers, resolve: true)
    game.submit(action) if action
    until game.over? || ((decision = game.pending_decision).kind == "priority" && (!resolve || game.state.stack.empty?))
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { it[:type] == "pay_mana" } || raise("can't pay"))
      else
        answer = answers.shift or raise "no answer for #{decision.kind}: #{game.legal_options}"
        game.submit(answer.respond_to?(:call) ? answer.call(game) : answer)
      end
    end
    expect(answers).to be_empty
    game
  end

  def cast(game, card, *, **) = play(game, { type: "cast", object: hand_id(game, card) }, *, **)

  # Casts the card from another zone (flashback, beam me up, a prepare spell's copy in exile, ...).
  def cast_from(game, zone_ids, *, **)
    option = game.legal_options.find { it[:type] == "cast" && zone_ids.include?(it[:object]) } or raise "nothing to cast"
    play(game, option, *, **)
  end

  def cast_prepared(game, *) = cast_from(game, game.state.exile, *)

  # Activates the nth non-mana ability offered for the card (on the battlefield, or in a hand or graveyard).
  def activate(game, card, *answers, index: 0)
    ids = game.state.battlefield + ids_in(game, "alice", :hand) + ids_in(game, "alice", :graveyard)
    id = ids.find { game.state.object(it).card == slug(card) }
    options = game.legal_options.select { it[:type] == "activate" && it[:object] == id }
    play(game, options.fetch(index) { raise "can't activate #{card}: #{game.legal_options}" }, *answers)
  end

  def play_land(game, card, *) = play(game, { type: "play_land", object: hand_id(game, card) }, *)

  def tap_for_mana(game, id, mana = nil)
    game.submit({ type: "activate_mana", object: id, ability: mana_ref(game, id), mana: mana }.compact)
  end

  # Passes (answering any other decision with its first option) until `step` of `turn`.
  def advance(game, step, turn:)
    until game.step == step && game.turn == turn && game.pending_decision.kind == "priority"
      game.submit(option_types(game).include?("pass") ? { type: "pass" } : game.legal_options.first)
    end
    game
  end

  # Moves on to declaring attackers and attacks bob with the card.
  def attack(game, card, *)
    game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
    play(game, { type: "attack", object: obj_id(game, card), target: bob }, *)
  end

  def hand_id(game, card, player: "alice") = obj_id(game, card, zone: :hand, player: player)
  def stack_id(game, card) = game.state.stack.find { game.state.object(it).card == slug(card) }
  def target(id) = { type: "target", target: id }
  def aim(card) = ->(game) { target(obj_id(game, card)) }
  def cost(card) = ->(game) { { type: "cost", object: obj_id(game, card) } }
  def bob = "player:bob"
  def alice = "player:alice"
  def mode(index) = { type: "mode", mode: index }
  def x_is(value) = { type: "x", value: value }

  # The first option of a decision with this type (and these details).
  def pick(type, **details)
    lambda do |game|
      game.legal_options.find { |o| o[:type] == type && details.all? { |k, v| o[k] == v } } or
        raise "no #{type} among #{game.legal_options}"
    end
  end

  def slug(card) = Enjine::CardDefinition.slug(card)
  def engine(game) = game.instance_variable_get(:@engine)
  def chars(game, id) = engine(game).chars(id)
  def power(game, id) = engine(game).power(engine(game).object(id))
  def toughness(game, id) = engine(game).toughness(engine(game).object(id))
  def counters(game, id) = game.state.object(id).counters
  def keyword?(game, id, keyword) = chars(game, id).keyword?(keyword)
  def prepared?(game, card) = engine(game).prepared?(game.state.object(obj_id(game, card)))
  def named(game, name) = game.state.battlefield.select { chars(game, it).name == name }
  def zone(game, player, zone) = ids_in(game, player, zone).map { game.state.object(it).card }
  def life(game, player) = game.state.players[game.names.index(player)].life
  def pool(game, player = "alice") = game.state.players[game.names.index(player)].mana_pool
  def jace_loyalty(game) = named(game, "Jace").sum { counters(game, it)["loyalty"].to_i }

  it "every card validates and keeps its rarity and printing" do
    cards.each { expect(Enjine::CardDefinition.from_h(it).to_h).to include("printing", "rarity") }
    expect(cards.map { it.dig("printing", "set") }.uniq).to contain_exactly("sos", "fra", "trk")
  end

  it "plays random DeckBuilder decks from this pool through the fuzzer, rules monitor on" do
    builder = Enjine::DeckBuilder.new(cards)
    players = [1, 2].map { Enjine::Player.new(name: "p#{it}", deck: builder.build(seed: it)) }
    result = Enjine::Fuzz.run(Enjine::Setup.new(*players), games: 2, seed: 7, roundtrip_every: 97)
    expect(result.outcomes.values.sum).to eq(2)
  end

  describe "lands" do
    it "basic lands tap for their color" do
      game = board(battlefield: %w[Plains Island Swamp Mountain Forest])
      game.state.battlefield.each { tap_for_mana(game, it) }
      expect(pool(game).slice(:W, :U, :B, :R, :G).values).to eq([1, 1, 1, 1, 1])
    end

    it "Deathcap Glade and Deserted Beach enter tapped unless two other lands are out" do
      game = play_land(board(hand: ["Deathcap Glade"], battlefield: ["Swamp"]), "Deathcap Glade")
      expect(game.state.object(obj_id(game, "Deathcap Glade")).tapped).to be(true)
      game = play_land(board(hand: ["Deserted Beach"], battlefield: %w[Plains Island]), "Deserted Beach")
      beach = obj_id(game, "Deserted Beach")
      expect(game.state.object(beach).tapped).to be(false)
      tap_for_mana(game, beach, "{U}")
      expect(pool(game)[:U]).to eq(1)
    end

    it "Fatehold Annex enters untapped only alongside a planeswalker" do
      game = play_land(board(hand: ["Fatehold Annex"]), "Fatehold Annex")
      expect(game.state.object(obj_id(game, "Fatehold Annex")).tapped).to be(true)
      game = play_land(board(hand: ["Fatehold Annex"], battlefield: ["The Theorist, Jace Beleren"]), "Fatehold Annex")
      expect(game.state.object(obj_id(game, "Fatehold Annex")).tapped).to be(false)
    end

    it "Sacred Foundry enters untapped for 2 life, or tapped" do
      game = play_land(board(hand: ["Sacred Foundry"]), "Sacred Foundry", pick("pay_life"))
      expect([life(game, "alice"), game.state.object(obj_id(game, "Sacred Foundry")).tapped]).to eq([18, false])
      game = play_land(board(hand: ["Sacred Foundry"]), "Sacred Foundry", pick("enter_tapped"))
      expect([life(game, "alice"), game.state.object(obj_id(game, "Sacred Foundry")).tapped]).to eq([20, true])
    end

    it "Forum of Amity enters tapped and surveils for mana" do
      game = play_land(board(hand: ["Forum of Amity"]), "Forum of Amity")
      expect(game.state.object(obj_id(game, "Forum of Amity")).tapped).to be(true)
      game = board(battlefield: ["Forum of Amity"], mana: { W: 2, B: 2 })
      activate(game, "Forum of Amity", pick("graveyard"))
      expect(zone(game, "alice", :graveyard)).to eq(["island"])
    end

    it "Skycoach Waypoint prepares a creature" do
      game = board(battlefield: ["Skycoach Waypoint", "Cheerful Osteomancer"], mana: { C: 3 })
      expect(prepared?(game, "Cheerful Osteomancer")).to be(false)
      activate(game, "Skycoach Waypoint", aim("Cheerful Osteomancer"))
      expect(prepared?(game, "Cheerful Osteomancer")).to be(true)
    end

    it "Bajor enters tapped and gains 1 life" do
      game = play_land(board(hand: ["Bajor"]), "Bajor")
      expect([life(game, "alice"), game.state.object(obj_id(game, "Bajor")).tapped]).to eq([21, true])
    end

    it "Quark's Bar entering untapped offers damage or surveil" do
      game = play_land(board(hand: ["Quark's Bar"], battlefield: %w[Mountain Mountain]), "Quark's Bar", mode(0))
      expect(life(game, "bob")).to eq(19)
    end
  end

  describe "creatures" do
    it "Rancorous Archaic enters with a +1/+1 counter per color spent (converge)" do
      game = cast(board(hand: ["Rancorous Archaic"], mana: { W: 1, U: 1, B: 1, R: 1, G: 1 }), "Rancorous Archaic")
      expect(counters(game, obj_id(game, "Rancorous Archaic"))).to eq("+1/+1" => 5)
    end

    it "Honorbound Page enters prepared; casting Forum's Favor from exile unprepares it" do
      game = cast(board(hand: ["Honorbound Page"], mana: { W: 5 }), "Honorbound Page")
      expect(prepared?(game, "Honorbound Page")).to be(true)
      cast_prepared(game, aim("Honorbound Page"))
      page = obj_id(game, "Honorbound Page")
      expect([power(game, page), keyword?(game, page, :flying), prepared?(game, "Honorbound Page")]).to eq([4, true, false])
    end

    it "Exhibition Tidecaller mills three after a cheap instant or sorcery (opus)" do
      game = cast(board(hand: ["Academic Ascent"], battlefield: ["Exhibition Tidecaller"], mana: { W: 2 }),
                  "Academic Ascent", aim("Exhibition Tidecaller"), target(bob))
      expect(zone(game, "bob", :graveyard).size).to eq(3)
    end

    it "Eager Glyphmage makes a flying Inkling" do
      game = cast(board(hand: ["Eager Glyphmage"], mana: { W: 4 }), "Eager Glyphmage")
      inkling = named(game, "Inkling").first
      expect([chars(game, inkling).colors, keyword?(game, inkling, :flying)]).to eq([%i[W B], true])
    end

    it "Stone Docent exiles itself from the graveyard to gain 2 life and surveil" do
      game = activate(board(graveyard: ["Stone Docent"], mana: { W: 1 }), "Stone Docent", pick("top"))
      expect([life(game, "alice"), zone(game, "alice", :graveyard)]).to eq([22, []])
    end

    it "Summoned Dromedary returns from the graveyard to hand" do
      game = activate(board(graveyard: ["Summoned Dromedary"], mana: { W: 2 }), "Summoned Dromedary")
      expect(zone(game, "alice", :hand)).to eq(["summoned_dromedary"])
    end

    it "Campus Composer's Aqueous Aria makes a flying 3/3 Elemental" do
      game = cast(board(hand: ["Campus Composer // Aqueous Aria"], mana: { U: 9 }), "Campus Composer")
      cast_prepared(game)
      expect(named(game, "Elemental").map { power(game, it) }).to eq([3])
    end

    it "Pensive Professor grows and draws when more mana than its power is spent (increment)" do
      game = cast(board(hand: ["Unsummon"], battlefield: ["Pensive Professor"], theirs: ["Pet Sehlat"], mana: { U: 1 }),
                  "Unsummon", aim("Pet Sehlat"))
      expect([counters(game, obj_id(game, "Pensive Professor")), zone(game, "alice", :hand)]).to eq([{ "+1/+1" => 1 }, ["island"]])
    end

    it "Cheerful Osteomancer's Raise Dead returns a creature card" do
      game = cast(board(hand: ["Cheerful Osteomancer"], graveyard: ["Pet Sehlat"], mana: { B: 5 }), "Cheerful Osteomancer")
      cast_prepared(game, ->(g) { target(ids_in(g, "alice", :graveyard).first) })
      expect(zone(game, "alice", :hand)).to eq(["pet_sehlat"])
    end

    it "Ulna Alley Shopkeep gets +2/+0 once you gained life this turn (infusion)" do
      game = board(hand: ["Silverquill Charm"], battlefield: ["Ulna Alley Shopkeep"], mana: { W: 1, B: 1 })
      expect(power(game, obj_id(game, "Ulna Alley Shopkeep"))).to eq(2)
      cast(game, "Silverquill Charm", mode(2))
      expect(power(game, obj_id(game, "Ulna Alley Shopkeep"))).to eq(4)
    end

    it "Blazing Firesinger's Seething Song adds five red" do
      game = cast(board(hand: ["Blazing Firesinger"], mana: { R: 6 }), "Blazing Firesinger")
      cast_prepared(game)
      expect(pool(game)[:R]).to eq(5)
    end

    it "Thunderdrum Soloist pings each opponent after an instant or sorcery (opus)" do
      game = cast(board(hand: ["Unsummon"], battlefield: ["Thunderdrum Soloist"], theirs: ["Pet Sehlat"], mana: { U: 1 }),
                  "Unsummon", aim("Pet Sehlat"))
      expect(life(game, "bob")).to eq(19)
    end

    it "Goblin Glasswright's Craft with Pride makes a Treasure" do
      game = cast(board(hand: ["Goblin Glasswright"], mana: { R: 3 }), "Goblin Glasswright")
      cast_prepared(game)
      expect(named(game, "Treasure").size).to eq(1)
    end

    it "Pestbrood Sloth leaves two Pests that gain life when they attack" do
      game = cast(board(hand: ["Ajani's Response"], battlefield: [["Pestbrood Sloth", { tapped: true }]], mana: { W: 2 }),
                  "Ajani's Response", aim("Pestbrood Sloth"))
      pests = named(game, "Pest")
      expect(pests.size).to eq(2)
      expect(chars(game, pests.first).colors).to eq(%i[B G])
    end

    it "Studious First-Year's Rampant Growth puts a basic land onto the battlefield tapped" do
      game = cast(board(hand: ["Studious First-Year"], mana: { G: 3 }), "Studious First-Year")
      cast_prepared(game, pick("find"))
      expect(game.state.object(obj_id(game, "Island")).tapped).to be(true)
    end

    it "Teacher's Pest returns from the graveyard tapped" do
      game = activate(board(graveyard: ["Teacher's Pest"], mana: { B: 1, G: 1 }), "Teacher's Pest")
      expect(game.state.object(obj_id(game, "Teacher's Pest")).tapped).to be(true)
    end

    it "Unflinching Hortimancer grows when you gain life" do
      game = cast(board(hand: ["Silverquill Charm"], battlefield: ["Unflinching Hortimancer"], mana: { W: 1, B: 1 }),
                  "Silverquill Charm", mode(2))
      expect(counters(game, obj_id(game, "Unflinching Hortimancer"))).to eq("+1/+1" => 1)
    end

    it "Campus Crier exiles itself from the graveyard to empower Jace 2" do
      game = activate(board(graveyard: ["Campus Crier"], mana: { W: 1 }), "Campus Crier")
      expect(jace_loyalty(game)).to eq(2)
    end

    it "Cryotheory Adept exiles itself from the graveyard to tap and stun a creature" do
      game = activate(board(graveyard: ["Cryotheory Adept"], theirs: ["Pet Sehlat"], mana: { U: 4 }), "Cryotheory Adept",
                      aim("Pet Sehlat"))
      sehlat = obj_id(game, "Pet Sehlat")
      expect([game.state.object(sehlat).tapped, counters(game, sehlat)]).to eq([true, { "stun" => 1 }])
    end

    it "Diviner of Victory's Unwind History bounces a creature, and the surveil pumps the Diviner" do
      game = cast(board(hand: ["Diviner of Victory"], theirs: ["Stone Docent"], mana: { U: 3 }), "Diviner of Victory")
      cast_prepared(game, aim("Stone Docent"), pick("top"))
      expect([zone(game, "bob", :hand), power(game, obj_id(game, "Diviner of Victory"))]).to eq([["stone_docent"], 2])
    end

    it "Divining Duelist taps a creature as it enters" do
      game = cast(board(hand: ["Divining Duelist"], theirs: ["Pet Sehlat"], mana: { U: 3 }), "Divining Duelist", mode(0), aim("Pet Sehlat"))
      expect(game.state.object(obj_id(game, "Pet Sehlat")).tapped).to be(true)
    end

    it "Mindseeker Oculus empowers Jace 4" do
      game = cast(board(hand: ["Mindseeker Oculus"], mana: { U: 3 }), "Mindseeker Oculus")
      expect(jace_loyalty(game)).to eq(4)
    end

    it "Apex Witchstalker gains 2 life as it enters, and basic landcycles" do
      game = cast(board(hand: ["Apex Witchstalker"], mana: { B: 6 }), "Apex Witchstalker")
      expect(life(game, "alice")).to eq(22)
      game = activate(board(hand: ["Apex Witchstalker"], mana: { B: 2 }), "Apex Witchstalker", pick("find"))
      expect(zone(game, "alice", :hand)).to eq(["island"])
    end

    it "Rank Rat makes each opponent discard" do
      game = cast(board(hand: ["Rank Rat"], their_hand: ["Swamp"], mana: { B: 2 }), "Rank Rat", pick("discard"))
      expect(zone(game, "bob", :graveyard)).to eq(["swamp"])
    end

    it "Void Extrapolator's Omit Variables mills three, turning on threshold" do
      game = cast(board(hand: ["Void Extrapolator"], graveyard: ["Swamp"] * 4, mana: { B: 3 }), "Void Extrapolator")
      expect(power(game, obj_id(game, "Void Extrapolator"))).to eq(2)
      cast_prepared(game)
      expect(power(game, obj_id(game, "Void Extrapolator"))).to eq(3)
    end

    it "Chandra's Emberling grows on noncreature spells" do
      game = cast(board(hand: ["Unsummon"], battlefield: ["Chandra's Emberling"], theirs: ["Pet Sehlat"], mana: { U: 1 }),
                  "Unsummon", aim("Pet Sehlat"))
      expect(counters(game, obj_id(game, "Chandra's Emberling"))).to eq("+1/+1" => 1)
    end

    it "Heartstring Puller makes a 2/2 Cadet" do
      game = cast(board(hand: ["Heartstring Puller"], mana: { R: 4 }), "Heartstring Puller")
      expect(named(game, "Cadet").map { power(game, it) }).to eq([2])
    end

    it "Greenhouse Propagator gains 1 life when another creature enters, and taps for green" do
      game = cast(board(hand: ["Pet Sehlat"], battlefield: ["Greenhouse Propagator"], mana: { W: 3 }), "Pet Sehlat")
      expect(life(game, "alice")).to eq(21)
      tap_for_mana(game, obj_id(game, "Greenhouse Propagator"))
      expect(pool(game)[:G]).to eq(1)
    end

    it "Sureshot Sower discards itself to destroy a flier" do
      game = board(hand: ["Academic Ascent", "Sureshot Sower"], theirs: ["Pet Sehlat"], mana: { W: 2, G: 4 })
      cast(game, "Academic Ascent", aim("Pet Sehlat"))
      activate(game, "Sureshot Sower", aim("Pet Sehlat"))
      expect(zone(game, "bob", :graveyard)).to eq(["pet_sehlat"])
    end

    it "Konstrari Improviser's Soul Tether makes a Heartwood that taps for red or green" do
      game = cast(board(hand: ["Konstrari Improviser"], mana: { R: 5 }), "Konstrari Improviser")
      cast_prepared(game)
      tap_for_mana(game, named(game, "Heartwood").first, "{G}")
      expect(pool(game)[:G]).to eq(1)
    end

    it "Living Library sacrifices itself to shuffle a creature into its owner's library" do
      game = activate(board(battlefield: ["Living Library"], theirs: ["Pet Sehlat"], mana: { C: 6 }), "Living Library", aim("Pet Sehlat"))
      expect(game.state.battlefield).to be_empty
      expect(zone(game, "bob", :library)).to include("pet_sehlat")
    end

    it "Thalia, the Survivor makes opponents' noncreature spells cost {1} more" do
      game = board(battlefield: ["Thalia, the Survivor"], their_hand: ["Unsummon"], their_mana: { U: 1 }, active: "bob")
      expect(game.legal_options).not_to include(type: "cast", object: hand_id(game, "Unsummon", player: "bob"))
    end

    it "Kiora of Fire and Ashes makes a 5/5 flying Dragon" do
      game = cast(board(hand: ["Kiora of Fire and Ashes"], mana: { R: 6 }), "Kiora of Fire and Ashes")
      dragon = named(game, "Dragon").first
      expect([power(game, dragon), keyword?(game, dragon, :flying)]).to eq([5, true])
    end

    it "Samut, Hazoret's Champion gives your creatures haste" do
      game = cast(board(hand: ["Pet Sehlat"], battlefield: ["Samut, Hazoret's Champion"], mana: { W: 3 }), "Pet Sehlat")
      expect(keyword?(game, obj_id(game, "Pet Sehlat"), :haste)).to be(true)
    end

    it "Ghalta the Unstoppable costs less by the greatest power and gives others trample" do
      game = cast(board(hand: ["Ghalta the Unstoppable"], battlefield: ["Pet Sehlat"], mana: { G: 5 }), "Ghalta the Unstoppable")
      expect(keyword?(game, obj_id(game, "Pet Sehlat"), :trample)).to be(true)
    end

    it "Tinybones makes each opponent discard, then punishes the discard" do
      game = cast(board(hand: ["Tinybones, Pocket Nuisance"], their_hand: ["Swamp"], mana: { B: 3 }), "Tinybones, Pocket Nuisance",
                  pick("discard"))
      expect(life(game, "bob")).to eq(19)
    end

    it "Vraska, the Cutting Glare destroys a permanent with six lands out, leaving a Treasure" do
      game = cast(board(hand: ["Vraska, the Cutting Glare"], battlefield: ["Swamp"] * 6, theirs: ["Pet Sehlat"], mana: { B: 2, G: 1 }),
                  "Vraska, the Cutting Glare", aim("Pet Sehlat"))
      expect(named(game, "Treasure").map { game.state.object(it).controller }).to eq([1])
    end

    it "Assembly Specialist makes a Borg artifact creature" do
      game = cast(board(hand: ["Assembly Specialist"], mana: { W: 2 }), "Assembly Specialist")
      expect(chars(game, named(game, "Borg").first).types).to eq(%i[artifact creature])
    end

    it "Pet Sehlat can't attack alone" do
      game = board(battlefield: ["Pet Sehlat", "Stone Docent"], step: :beginning_of_combat)
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      game.submit(type: "attack", object: obj_id(game, "Pet Sehlat"), target: bob)
      expect(option_types(game)).not_to include("done")
      game.submit(type: "attack", object: obj_id(game, "Stone Docent"), target: bob)
      expect(engine(game).attackers.keys).to contain_exactly(obj_id(game, "Pet Sehlat"), obj_id(game, "Stone Docent"))
    end

    it "Humpback Whales basic landcycles" do
      game = activate(board(hand: ["Humpback Whales"], mana: { U: 2 }), "Humpback Whales", pick("find"))
      expect(zone(game, "alice", :hand)).to eq(["island"])
    end

    it "Mr. Spock makes each draw two" do
      game = cast(board(hand: ["Open Communications"], battlefield: ["Mr. Spock, Science Officer"], mana: { U: 1 }), "Open Communications")
      expect(zone(game, "alice", :hand).size).to eq(2)
    end

    it "Collective Drone's power is the number of artifact creatures you control" do
      game = cast(board(hand: ["Assembly Specialist"], battlefield: ["Collective Drone"], mana: { W: 2 }), "Assembly Specialist")
      expect(power(game, obj_id(game, "Collective Drone"))).to eq(3)
    end

    it "Xindi Surveyors grows on landfall" do
      game = play_land(board(hand: ["Forest"], battlefield: ["Xindi Surveyors"]), "Forest")
      expect(counters(game, obj_id(game, "Xindi Surveyors"))).to eq("+1/+1" => 1)
    end
  end

  describe "instants and sorceries" do
    it "Together as One draws, burns and gains X, X the colors spent (converge)" do
      game = cast(board(hand: ["Together as One"], mana: { W: 1, U: 1, B: 1, R: 2, G: 1 }), "Together as One", target(alice), target(bob))
      expect([zone(game, "alice", :hand).size, life(game, "bob"), life(game, "alice")]).to eq([5, 15, 25])
    end

    it "Ajani's Response costs {3} less against a tapped creature" do
      game = cast(board(hand: ["Ajani's Response"], theirs: [["Pet Sehlat", { tapped: true }]], mana: { W: 2 }), "Ajani's Response",
                  aim("Pet Sehlat"))
      expect(zone(game, "bob", :graveyard)).to eq(["pet_sehlat"])
    end

    it "Daydream flickers a creature with a +1/+1 counter, and has flashback" do
      game = cast(board(hand: ["Daydream"], battlefield: ["Pet Sehlat"], mana: { W: 1 }), "Daydream", aim("Pet Sehlat"))
      expect(counters(game, obj_id(game, "Pet Sehlat"))).to eq("+1/+1" => 1)
      game = board(graveyard: ["Daydream"], battlefield: ["Pet Sehlat"], mana: { W: 3 })
      cast_from(game, ids_in(game, "alice", :graveyard), aim("Pet Sehlat"))
      expect([zone(game, "alice", :graveyard), game.state.exile.size]).to eq([[], 1])
    end

    it "Harsh Annotation destroys a creature and gives its controller an Inkling" do
      game = cast(board(hand: ["Harsh Annotation"], theirs: ["Pet Sehlat"], mana: { W: 2 }), "Harsh Annotation", aim("Pet Sehlat"))
      expect(named(game, "Inkling").map { game.state.object(it).controller }).to eq([1])
    end

    it "Rapier Wit taps and stuns on your turn, and draws" do
      game = cast(board(hand: ["Rapier Wit"], theirs: ["Pet Sehlat"], mana: { W: 2 }), "Rapier Wit", aim("Pet Sehlat"))
      expect([counters(game, obj_id(game, "Pet Sehlat")), zone(game, "alice", :hand)]).to eq([{ "stun" => 1 }, ["island"]])
    end

    it "Essence Scatter counters a creature spell" do
      game = board(hand: ["Pet Sehlat", "Essence Scatter"], mana: { W: 3, U: 2 })
      play(game, { type: "cast", object: hand_id(game, "Pet Sehlat") }, resolve: false)
      cast(game, "Essence Scatter", ->(g) { target(stack_id(g, "Pet Sehlat")) })
      expect(zone(game, "alice", :graveyard)).to contain_exactly("pet_sehlat", "essence_scatter")
    end

    it "Fractal Anomaly makes a Fractal with a counter per card drawn this turn" do
      game = cast(board(hand: ["Open Communications", "Fractal Anomaly"], mana: { U: 2 }), "Open Communications")
      cast(game, "Fractal Anomaly")
      expect(named(game, "Fractal").map { power(game, it) }).to eq([1])
    end

    it "Foolish Fate also drains 3 once you gained life this turn (infusion)" do
      game = cast(board(hand: ["Silverquill Charm", "Foolish Fate"], theirs: ["Pet Sehlat"], mana: { W: 1, B: 4 }),
                  "Silverquill Charm", mode(2))
      cast(game, "Foolish Fate", aim("Pet Sehlat"))
      expect([life(game, "bob"), zone(game, "bob", :graveyard)]).to eq([14, ["pet_sehlat"]])
    end

    it "Withering Curse shrinks every creature, or destroys them all after you gained life" do
      game = cast(board(hand: ["Withering Curse"], battlefield: ["Pet Sehlat"], theirs: ["Stone Docent"], mana: { B: 3 }),
                  "Withering Curse")
      expect([power(game, obj_id(game, "Pet Sehlat")), zone(game, "bob", :graveyard)]).to eq([2, ["stone_docent"]])
      game = cast(board(hand: ["Silverquill Charm", "Withering Curse"], battlefield: ["Pet Sehlat"], mana: { W: 1, B: 4 }),
                  "Silverquill Charm", mode(2))
      cast(game, "Withering Curse")
      expect(game.state.battlefield).to be_empty
    end

    it "Duel Tactics pings a creature that then can't block" do
      game = cast(board(hand: ["Duel Tactics"], theirs: ["Pet Sehlat"], mana: { R: 1 }), "Duel Tactics", aim("Pet Sehlat"))
      sehlat = obj_id(game, "Pet Sehlat")
      expect([game.state.object(sehlat).damage, keyword?(game, sehlat, :cant_block)]).to eq([1, true])
    end

    it "Artistic Process sweeps the opponent's small creatures, or makes a hasty flier" do
      game = cast(board(hand: ["Artistic Process"], battlefield: ["Stone Docent"], theirs: ["Stone Docent"], mana: { R: 5 }),
                  "Artistic Process", mode(1))
      expect([zone(game, "bob", :graveyard), named(game, "Stone Docent").size]).to eq([["stone_docent"], 1])
      game = cast(board(hand: ["Artistic Process"], mana: { R: 5 }), "Artistic Process", mode(2))
      expect(keyword?(game, named(game, "Elemental").first, :haste)).to be(true)
    end

    it "Snarl Song makes two Fractals with X counters and gains X life (converge)" do
      game = cast(board(hand: ["Snarl Song"], mana: { W: 1, U: 1, B: 1, R: 1, G: 2 }), "Snarl Song")
      expect([named(game, "Fractal").map { power(game, it) }, life(game, "alice")]).to eq([[5, 5], 25])
    end

    it "Wild Hypothesis makes an X/X Fractal, then surveils 2" do
      game = cast(board(hand: ["Wild Hypothesis"], mana: { G: 4 }), "Wild Hypothesis", x_is(3), pick("top"), pick("top"), pick("order"))
      expect(named(game, "Fractal").map { power(game, it) }).to eq([3])
    end

    it "Chelonian Tackle toughens a creature, which then fights" do
      game = cast(board(hand: ["Chelonian Tackle"], battlefield: ["Stone Docent"], theirs: ["Pet Sehlat"], mana: { G: 3 }),
                  "Chelonian Tackle", aim("Stone Docent"), aim("Pet Sehlat"))
      expect([named(game, "Stone Docent").size, zone(game, "bob", :graveyard)]).to eq([1, ["pet_sehlat"]])
    end

    it "Silverquill Charm puts two +1/+1 counters on a creature" do
      game = cast(board(hand: ["Silverquill Charm"], battlefield: ["Pet Sehlat"], mana: { W: 1, B: 1 }), "Silverquill Charm",
                  mode(0), aim("Pet Sehlat"))
      expect(counters(game, obj_id(game, "Pet Sehlat"))).to eq("+1/+1" => 2)
    end

    it "Witherbloom Charm sacrifices a permanent to draw two, or destroys a cheap permanent" do
      game = cast(board(hand: ["Witherbloom Charm"], battlefield: ["Pet Sehlat"], mana: { B: 1, G: 1 }), "Witherbloom Charm",
                  mode(0), pick("yes"))
      expect([zone(game, "alice", :graveyard).sort, zone(game, "alice", :hand).size]).to eq([%w[pet_sehlat witherbloom_charm], 2])
      game = cast(board(hand: ["Witherbloom Charm"], theirs: ["Stone Docent"], mana: { B: 1, G: 1 }), "Witherbloom Charm",
                  mode(2), aim("Stone Docent"))
      expect(zone(game, "bob", :graveyard)).to eq(["stone_docent"])
    end

    it "Traumatic Critique deals X damage, then draws two and discards one" do
      game = cast(board(hand: ["Traumatic Critique"], mana: { U: 2, R: 2 }), "Traumatic Critique", x_is(2), target(bob), pick("discard"))
      expect([life(game, "bob"), zone(game, "alice", :hand).size]).to eq([18, 1])
    end

    it "Academic Ascent pumps, grants flying and empowers Jace 2" do
      game = cast(board(hand: ["Academic Ascent"], battlefield: ["Pet Sehlat"], mana: { W: 2 }), "Academic Ascent", aim("Pet Sehlat"))
      sehlat = obj_id(game, "Pet Sehlat")
      expect([power(game, sehlat), keyword?(game, sehlat, :flying), jace_loyalty(game)]).to eq([6, true, 2])
    end

    it "Generous Revival returns a cheap creature card with an extra counter" do
      game = cast(board(hand: ["Generous Revival"], graveyard: ["Stone Docent"], mana: { W: 3 }), "Generous Revival",
                  ->(g) { target(ids_in(g, "alice", :graveyard).first) })
      expect(counters(game, obj_id(game, "Stone Docent"))).to eq("+1/+1" => 1)
    end

    it "Hexhaven Battalion makes three Cadets and empowers Jace 2" do
      game = cast(board(hand: ["Hexhaven Battalion"], mana: { W: 6 }), "Hexhaven Battalion")
      expect([named(game, "Cadet").size, jace_loyalty(game)]).to eq([3, 2])
    end

    it "Surgical Precision draws a card and gains 2 life" do
      game = cast(board(hand: ["Surgical Precision"], mana: { W: 2 }), "Surgical Precision", mode(1))
      expect([zone(game, "alice", :hand).size, life(game, "alice")]).to eq([1, 22])
    end

    it "Your Fate Ends Here destroys a creature with mana value 3 or more, then surveils" do
      game = cast(board(hand: ["Your Fate Ends Here"], theirs: ["Pet Sehlat"], mana: { W: 3 }), "Your Fate Ends Here",
                  aim("Pet Sehlat"), pick("graveyard"))
      expect(zone(game, "bob", :graveyard)).to eq(["pet_sehlat"])
    end

    it "Perfected Theory sets base power and toughness to 4/5" do
      game = cast(board(hand: ["Perfected Theory"], battlefield: ["Stone Docent"], mana: { U: 1 }), "Perfected Theory",
                  mode(1), aim("Stone Docent"))
      docent = obj_id(game, "Stone Docent")
      expect([power(game, docent), toughness(game, docent)]).to eq([4, 5])
    end

    it "Unsummon returns a creature to its owner's hand" do
      game = cast(board(hand: ["Unsummon"], theirs: ["Pet Sehlat"], mana: { U: 1 }), "Unsummon", aim("Pet Sehlat"))
      expect(zone(game, "bob", :hand)).to eq(["pet_sehlat"])
    end

    it "Cast Away Doubt draws two and deals 2 damage to each player" do
      game = cast(board(hand: ["Cast Away Doubt"], mana: { B: 3 }), "Cast Away Doubt")
      expect([zone(game, "alice", :hand).size, life(game, "alice"), life(game, "bob")]).to eq([2, 18, 18])
    end

    it "Extended Absence exiles a creature and drains 1" do
      game = cast(board(hand: ["Extended Absence"], theirs: ["Pet Sehlat"], mana: { B: 4 }), "Extended Absence", aim("Pet Sehlat"))
      expect([game.state.exile.size, life(game, "bob"), life(game, "alice")]).to eq([1, 19, 21])
    end

    it "Rewrite Regrets reanimates a creature card and empowers Jace 2" do
      game = cast(board(hand: ["Rewrite Regrets"], graveyard: ["Pet Sehlat"], mana: { B: 4 }), "Rewrite Regrets",
                  ->(g) { target(ids_in(g, "alice", :graveyard).first) })
      expect([named(game, "Pet Sehlat").size, jace_loyalty(game)]).to eq([1, 2])
    end

    it "Vraska's Final Mercy destroys a creature for 2 life" do
      game = cast(board(hand: ["Vraska's Final Mercy"], theirs: ["Pet Sehlat"], mana: { B: 2 }), "Vraska's Final Mercy",
                  mode(0), aim("Pet Sehlat"))
      expect([life(game, "alice"), zone(game, "bob", :graveyard)]).to eq([18, ["pet_sehlat"]])
    end

    it "Blazing Crescendo pumps and lets you play the exiled top card" do
      game = cast(board(hand: ["Blazing Crescendo"], battlefield: ["Pet Sehlat"], mana: { R: 2 }), "Blazing Crescendo", aim("Pet Sehlat"))
      expect(power(game, obj_id(game, "Pet Sehlat"))).to eq(7)
      expect(game.legal_options).to include(include(type: "play_land", object: game.state.exile.first))
    end

    it "Wrath of the Bloodmane costs {1} less with a legendary creature" do
      game = cast(board(hand: ["Wrath of the Bloodmane"], battlefield: ["Samut, Hazoret's Champion"], theirs: ["Pet Sehlat"],
                        mana: { R: 2 }), "Wrath of the Bloodmane", aim("Pet Sehlat"))
      expect(zone(game, "bob", :graveyard)).to eq(["pet_sehlat"])
    end

    it "Bestial Incursion is cast with flashback for a 4/4 trampling Beast" do
      game = board(graveyard: ["Bestial Incursion"], mana: { G: 6 })
      cast_from(game, ids_in(game, "alice", :graveyard))
      expect([named(game, "Beast").map { power(game, it) }, game.state.exile.size]).to eq([[4], 1])
    end

    it "Something Worth Saving mills four, keeps a permanent card and gains 1 life" do
      game = cast(board(hand: ["Something Worth Saving"], mana: { G: 2 }), "Something Worth Saving", pick("choose"))
      expect([zone(game, "alice", :hand), zone(game, "alice", :graveyard).size, life(game, "alice")]).to eq([["island"], 4, 21])
    end

    it "Charge the Sanctum gives a creature +2/+0, first strike and a counter" do
      game = cast(board(hand: ["Charge the Sanctum"], battlefield: ["Stone Docent"], mana: { W: 3 }), "Charge the Sanctum",
                  mode(1), aim("Stone Docent"))
      docent = obj_id(game, "Stone Docent")
      expect([power(game, docent), keyword?(game, docent, :first_strike)]).to eq([6, true])
    end

    it "Stingerquill Charm deals 3 damage" do
      game = cast(board(hand: ["Stingerquill Charm"], mana: { B: 1, R: 1 }), "Stingerquill Charm", mode(0), target(bob))
      expect(life(game, "bob")).to eq(17)
    end

    it "Terminal Criticism destroys a blue or red creature" do
      game = cast(board(hand: ["Terminal Criticism"], theirs: ["Chandra's Emberling"], mana: { B: 2 }), "Terminal Criticism",
                  aim("Chandra's Emberling"))
      expect([zone(game, "bob", :graveyard), life(game, "alice")]).to eq([["chandras_emberling"], 21])
    end

    it "Consider the Prime Directive taps and stuns a creature, and draws" do
      game = cast(board(hand: ["Consider the Prime Directive"], theirs: ["Pet Sehlat"], mana: { U: 3 }), "Consider the Prime Directive",
                  mode(1), aim("Pet Sehlat"))
      expect([counters(game, obj_id(game, "Pet Sehlat")), zone(game, "alice", :hand).size]).to eq([{ "stun" => 1 }, 1])
    end

    it "Highly Illogical counters a spell with mana value 2 or less" do
      game = board(hand: ["Stone Docent", "Highly Illogical"], mana: { W: 2, U: 2 })
      play(game, { type: "cast", object: hand_id(game, "Stone Docent") }, resolve: false)
      cast(game, "Highly Illogical", pick("no_kick"), ->(g) { target(stack_id(g, "Stone Docent")) })
      expect(zone(game, "alice", :graveyard)).to contain_exactly("stone_docent", "highly_illogical")
    end

    it "Open Communications draws, then beams up from the graveyard" do
      game = cast(board(hand: ["Open Communications"], battlefield: ["Pet Sehlat"], mana: { U: 4 }), "Open Communications")
      cast_from(game, ids_in(game, "alice", :graveyard), cost("Pet Sehlat"))
      expect(zone(game, "alice", :hand)).to contain_exactly("island", "island", "pet_sehlat")
    end

    it "Eject the Warp Core gives -6/-6 when kicked by sacrificing" do
      game = cast(board(hand: ["Eject the Warp Core"], battlefield: ["Stone Docent"], theirs: ["Pet Sehlat"], mana: { B: 2 }),
                  "Eject the Warp Core", pick("kick"), aim("Pet Sehlat"), cost("Stone Docent"))
      expect(zone(game, "alice", :graveyard)).to contain_exactly("eject_the_warp_core", "stone_docent")
      expect(zone(game, "bob", :graveyard)).to eq(["pet_sehlat"])
    end

    it "A Good Day to Die draws a card when the creature dies this turn" do
      game = cast(board(hand: ["A Good Day to Die", "Duel Tactics"], battlefield: ["Stone Docent"], mana: { B: 1, R: 1 }),
                  "A Good Day to Die", aim("Stone Docent"))
      cast(game, "Duel Tactics", aim("Stone Docent"))
      expect(zone(game, "alice", :hand)).to eq(["island"])
    end

    it "Khaaaaaaaaaaaannn! deals twice X damage and exiles the creature" do
      game = cast(board(hand: ["Khaaaaaaaaaaaannn!"], theirs: ["Pet Sehlat"], mana: { R: 3 }), "Khaaaaaaaaaaaannn!",
                  x_is(2), aim("Pet Sehlat"))
      expect([zone(game, "bob", :graveyard), game.state.exile.size]).to eq([[], 1])
    end
  end

  describe "artifacts" do
    it "Strixhaven Skycoach finds a basic land and is crewed into a flier" do
      game = cast(board(hand: ["Strixhaven Skycoach"], battlefield: ["Pet Sehlat"], mana: { C: 3 }), "Strixhaven Skycoach",
                  pick("search"), pick("find"))
      expect(zone(game, "alice", :hand)).to eq(["island"])
      activate(game, "Strixhaven Skycoach", cost("Pet Sehlat"))
      expect(chars(game, obj_id(game, "Strixhaven Skycoach")).creature?).to be(true)
    end

    it "Diary of Dreams collects page counters and draws for less" do
      game = cast(board(hand: ["Unsummon"], battlefield: [["Diary of Dreams", { counters: { "page" => 2 } }], "Pet Sehlat"],
                        mana: { U: 3 }), "Unsummon", aim("Pet Sehlat"))
      activate(game, "Diary of Dreams")
      expect(zone(game, "alice", :hand)).to contain_exactly("island", "pet_sehlat")
    end

    it "Potioner's Trove taps for any color, and gains 2 life after an instant or sorcery" do
      game = board(hand: ["Unsummon"], battlefield: ["Potioner's Trove", "Pet Sehlat"], mana: { U: 1 })
      expect(game.legal_options.select { it[:type] == "activate" }).to be_empty
      cast(game, "Unsummon", aim("Pet Sehlat"))
      activate(game, "Potioner's Trove")
      expect(life(game, "alice")).to eq(22)
    end

    it "Medic's Kitesail equips: +1/+0, flying, and life on attack" do
      game = activate(board(battlefield: ["Medic's Kitesail", "Stone Docent"], mana: { C: 2 }), "Medic's Kitesail", aim("Stone Docent"))
      docent = obj_id(game, "Stone Docent")
      expect([power(game, docent), keyword?(game, docent, :flying)]).to eq([4, true])
      attack(game, "Stone Docent")
      expect(life(game, "alice")).to eq(21)
    end

    it "Eye of Jace surveils each upkeep and pays off at seven cards in the graveyard" do
      game = advance(board(battlefield: ["Eye of Jace"], graveyard: ["Swamp"] * 6, active: "bob", step: :end), :upkeep, turn: 4)
      play(game, nil, pick("graveyard"))
      expect([life(game, "bob"), life(game, "alice"), game.state.battlefield]).to eq([18, 22, []])
    end

    it "Bat'leth shrinks a creature as it enters and equips for +2/+0" do
      game = cast(board(hand: ["Bat'leth"], battlefield: ["Pet Sehlat"], theirs: ["Stone Docent"], mana: { B: 5 }), "Bat'leth",
                  aim("Stone Docent"))
      expect(zone(game, "bob", :graveyard)).to eq(["stone_docent"])
      activate(game, "Bat'leth", aim("Pet Sehlat"))
      expect(power(game, obj_id(game, "Pet Sehlat"))).to eq(6)
    end

    it "Oberth-Class Starship finds a basic Plains and flies once stationed to 6" do
      game = cast(board(hand: ["Oberth-Class Starship"], library: %w[Island Plains], mana: { W: 2 }), "Oberth-Class Starship", pick("find"))
      expect(zone(game, "alice", :hand)).to eq(["plains"])
      game = board(battlefield: [["Oberth-Class Starship", { counters: { "charge" => 6 } }]])
      ship = obj_id(game, "Oberth-Class Starship")
      expect([chars(game, ship).creature?, keyword?(game, ship, :flying)]).to eq([true, true])
    end

    it "Suurok-Class Science Vessel draws as it enters and becomes a 3/2 flier at 5 charge" do
      game = cast(board(hand: ["Suurok-Class Science Vessel"], mana: { U: 3 }), "Suurok-Class Science Vessel")
      expect(zone(game, "alice", :hand)).to eq(["island"])
      game = board(battlefield: [["Suurok-Class Science Vessel", { counters: { "charge" => 1 } }], "Pet Sehlat"])
      activate(game, "Suurok-Class Science Vessel", aim("Pet Sehlat").then { ->(g) { { type: "cost", object: obj_id(g, "Pet Sehlat") } } })
      expect(power(game, obj_id(game, "Suurok-Class Science Vessel"))).to eq(3)
    end

    it "Malfunctioning Holodeck exiles a nonland permanent until it leaves" do
      game = cast(board(hand: ["Malfunctioning Holodeck", "Witherbloom Charm"], theirs: ["Pet Sehlat"], mana: { W: 3, B: 1, G: 1 }),
                  "Malfunctioning Holodeck", aim("Pet Sehlat"))
      expect(named(game, "Pet Sehlat")).to be_empty
      cast(game, "Witherbloom Charm", mode(0), pick("yes"))
      expect(named(game, "Pet Sehlat").size).to eq(1)
    end

    it "Engineered Explosives gets a charge counter per color spent and destroys that mana value" do
      game = cast(board(hand: ["Engineered Explosives"], battlefield: ["Stone Docent"], theirs: ["Pet Sehlat"], mana: { W: 1, U: 1, C: 2 }),
                  "Engineered Explosives", x_is(2))
      expect(counters(game, obj_id(game, "Engineered Explosives"))).to eq("charge" => 2)
      activate(game, "Engineered Explosives")
      expect(game.state.battlefield.map { game.state.object(it).card }).to eq(["pet_sehlat"])
    end

    it "Tricorder equips for +1/+1 and surveils when the creature attacks" do
      game = activate(board(battlefield: ["Tricorder", "Stone Docent"], mana: { C: 1 }), "Tricorder", aim("Stone Docent"))
      expect(power(game, obj_id(game, "Stone Docent"))).to eq(4)
      attack(game, "Stone Docent", pick("graveyard"))
      expect(zone(game, "alice", :graveyard)).to eq(["island"])
    end

    it "Tea, Earl Grey, Hot draws as it enters, then sacrifices to burn" do
      game = cast(board(hand: ["Tea, Earl Grey, Hot"], mana: { C: 4 }), "Tea, Earl Grey, Hot")
      expect(zone(game, "alice", :hand)).to eq(["island"])
      activate(game, "Tea, Earl Grey, Hot", mode(0), target(bob))
      expect(life(game, "bob")).to eq(18)
    end

    it "Class-F Shuttlecraft taps for any color" do
      game = board(battlefield: ["Class-F Shuttlecraft"])
      tap_for_mana(game, obj_id(game, "Class-F Shuttlecraft"), "{B}")
      expect(pool(game)[:B]).to eq(1)
    end
  end

  describe "enchantments" do
    it "Memory Trap exiles a nonland permanent an opponent controls" do
      game = cast(board(hand: ["Memory Trap"], theirs: ["Pet Sehlat"], mana: { W: 3 }), "Memory Trap", aim("Pet Sehlat"))
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["pet_sehlat"])
    end

    it "Those Old Scientists draws two and discards two (chapter I)" do
      game = cast(board(hand: ["Those Old Scientists"], mana: { U: 3 }), "Those Old Scientists", pick("discard"), pick("discard"))
      expect([zone(game, "alice", :graveyard).size, counters(game, obj_id(game, "Those Old Scientists"))]).to eq([2, { "lore" => 1 }])
    end

    it "Comforting Counsel gives +3/+3 at five growth counters" do
      game = cast(board(hand: ["Silverquill Charm"], battlefield: [["Comforting Counsel", { counters: { "growth" => 4 } }], "Stone Docent"],
                        mana: { W: 1, B: 1 }), "Silverquill Charm", mode(2))
      expect(power(game, obj_id(game, "Stone Docent"))).to eq(6)
    end

    it "Ajani's Anguish deals X damage as it enters and gives trample" do
      game = cast(board(hand: ["Ajani's Anguish"], battlefield: ["Pet Sehlat"], mana: { R: 4 }), "Ajani's Anguish", x_is(3), target(bob))
      expect([life(game, "bob"), keyword?(game, obj_id(game, "Pet Sehlat"), :trample)]).to eq([17, true])
    end

    it "Captain's Tutelage gives +2/+0 and first strike" do
      game = cast(board(hand: ["Captain's Tutelage"], battlefield: ["Pet Sehlat"], mana: { R: 2 }), "Captain's Tutelage", aim("Pet Sehlat"))
      sehlat = obj_id(game, "Pet Sehlat")
      expect([power(game, sehlat), keyword?(game, sehlat, :first_strike)]).to eq([6, true])
    end

    it "Amok Time makes your creature fight (chapter I)" do
      game = cast(board(hand: ["Amok Time"], battlefield: ["Pet Sehlat"], theirs: ["Stone Docent"], mana: { G: 3 }), "Amok Time",
                  aim("Pet Sehlat"), aim("Stone Docent"))
      expect(zone(game, "bob", :graveyard)).to eq(["stone_docent"])
    end

    it "The Measure of a Man exiles a creature (chapter I)" do
      game = cast(board(hand: ["The Measure of a Man"], theirs: ["Pet Sehlat"], mana: { W: 3 }), "The Measure of a Man", aim("Pet Sehlat"))
      expect(named(game, "Pet Sehlat")).to be_empty
    end
  end

  describe "planeswalkers" do
    it "The Theorist, Jace Beleren makes an Illusion (+1) and draws on each opponent's draw step" do
      game = board(battlefield: ["The Theorist, Jace Beleren"])
      activate(game, "The Theorist, Jace Beleren")
      expect([named(game, "Illusion").size, counters(game, obj_id(game, "The Theorist, Jace Beleren"))["loyalty"]]).to eq([1, 4])
      game = board(battlefield: ["The Theorist, Jace Beleren"], active: "bob", step: :upkeep)
      skip_to(game, :precombat_main, turn: 3)
      expect(zone(game, "alice", :hand)).to eq(["island"])
    end
  end
end
