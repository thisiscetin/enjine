# frozen_string_literal: true

# Real cards whose statics, grants and combat rules were known gaps, written by hand in the card DSL
# (spec/fixtures/cards/real/known_gaps_statics_combat.json): granted costs that tap the granting permanent,
# choices bound into granted abilities, "can't become untapped", chosen card names, riot granted by a static
# (CR 614.12), attacking alone and attack/block restrictions by flying. Plain stand-in cards are defined below.
RSpec.describe "Real cards: known gaps in statics and combat" do
  let(:stand_ins) do
    [
      { "name" => "Test Bear", "mana_cost" => "{1}{G}", "types" => ["creature"], "subtypes" => ["bear"], "power" => 2, "toughness" => 2 },
      { "name" => "Test Wall", "mana_cost" => "{1}{W}", "types" => ["creature"], "subtypes" => ["wall"], "power" => 0,
        "toughness" => 4, "keywords" => ["defender"] },
      { "name" => "Test Bird", "mana_cost" => "{1}{W}", "types" => ["creature"], "subtypes" => ["bird"], "power" => 1,
        "toughness" => 1, "keywords" => ["flying"] },
      { "name" => "Test Spider", "mana_cost" => "{1}{G}", "types" => ["creature"], "subtypes" => ["spider"], "power" => 1,
        "toughness" => 2 },
      { "name" => "Test Shock", "mana_cost" => "{R}", "types" => ["instant"],
        "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                       "effects" => [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }] } }] },
      { "name" => "Test Frost", "mana_cost" => "{U}", "types" => ["instant"],
        "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [{ "tap" => { "to" => { "target" => 0 } } }] } }] },
      { "name" => "Test Wakeup", "mana_cost" => "{W}", "types" => ["instant"],
        "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [{ "untap" => { "to" => { "target" => 0 } } }] } }] },
      { "name" => "Test Relic", "mana_cost" => "{1}", "types" => ["artifact"],
        "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{1}" }], "effects" => [{ "gain_life" => { "amount" => 1 } }] } },
                        { "mana" => { "cost" => ["tap"], "produce" => "{C}" } }] },
      { "name" => "Test Cycler", "mana_cost" => "{3}", "types" => ["artifact"], "abilities" => [{ "cycling" => { "cost" => "{1}" } }] },
      { "name" => "Test Gate", "types" => ["land"],
        "abilities" => [{ "activated" => { "cost" => ["tap"], "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
    ]
  end

  let(:cards) { CardFixtures.real("known_gaps_statics_combat") }
  let(:basics) { CardFixtures.real("newest_sets").select { %w[Plains Island Swamp Mountain Forest].include?(it["name"]) } }
  let(:catalog) { Enjine::Catalog.from_definitions(cards + basics + stand_ins) }

  # Alice's turn 3 (precombat main unless `step`). Permanents are names or [name, options].
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

  # Submits `action`, answers further decisions with `answers` (options or blocks taking the game), pays mana
  # from the pool and, with `resolve`, passes until the stack is empty.
  def play(game, action, *answers, resolve: true)
    game.submit(action) if action
    until game.over? || ((decision = game.pending_decision).kind == "priority" && (!resolve || game.state.stack.empty?))
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" # colorless first, so colored mana stays for later costs
        pays = game.legal_options.select { it[:type] == "pay_mana" }
        game.submit(pays.find { it[:mana].to_s == "C" } || pays.first || raise("can't pay"))
      else
        answer = answers.shift or raise "no answer for #{decision.kind}: #{game.legal_options}"
        game.submit(answer.respond_to?(:call) ? answer.call(game) : answer)
      end
    end
    expect(answers).to be_empty
    game
  end

  def cast(game, card, *, **) = play(game, { type: "cast", object: obj_id(game, card, zone: :hand, player: "alice") }, *, **)

  def activations(game, id) = game.legal_options.select { it[:type] == "activate" && it[:object] == id }

  def activate(game, id, *answers, index: 0)
    play(game, activations(game, id).fetch(index) { raise "can't activate: #{game.legal_options}" }, *answers)
  end

  def pick(type, **details)
    lambda do |game|
      game.legal_options.find { |o| o[:type] == type && details.all? { |k, v| o[k] == v } } or
        raise "no #{type} among #{game.legal_options}"
    end
  end

  def aim(card) = ->(game) { { type: "target", target: obj_id(game, card) } }
  def engine(game) = game.instance_variable_get(:@engine)
  def chars(game, id) = engine(game).chars(id)
  def obj(game, id) = game.state.object(id)
  def life(game, player) = game.state.players[game.names.index(player)].life
  def bob = "player:bob"

  it "every card validates and keeps its rarity and printing" do
    cards.each { expect(Enjine::CardDefinition.from_h(it).to_h).to include("printing", "rarity") }
  end

  it "plays random DeckBuilder decks from this pool through the fuzzer, rules monitor on" do
    builder = Enjine::DeckBuilder.new(cards + CardFixtures.cards) # the invented pool fills the decks around them
    players = [1, 2].map { Enjine::Player.new(name: "p#{it}", deck: builder.build(seed: it)) }
    result = Enjine::Fuzz.run(Enjine::Setup.new(*players), games: 2, seed: 7, roundtrip_every: 97)
    expect(result.outcomes.values.sum).to eq(2)
  end

  describe "Fishing Pole (CR 602.2b, 607.1a)" do
    def equipped(mana: { C: 5 }, **)
      game = board(battlefield: ["Fishing Pole", "Test Bear"], mana: mana, **)
      pole = obj_id(game, "Fishing Pole")
      activate(game, pole, aim("Test Bear"))
      game
    end

    it "the equipped creature's granted ability taps it and the Pole, and puts a bait counter on the Pole" do
      game = equipped
      bear = obj_id(game, "Test Bear")
      pole = obj_id(game, "Fishing Pole")
      activate(game, bear)
      expect([obj(game, bear).tapped, obj(game, pole).tapped, obj(game, pole).counters]).to eq([true, true, { "bait" => 1 }])
    end

    it "when the creature untaps, a bait counter becomes a Fish; it can't be activated while the Pole is tapped" do
      game = equipped(hand: ["Test Wakeup", "Test Wakeup"], mana: { C: 5, W: 2 })
      bear = obj_id(game, "Test Bear")
      pole = obj_id(game, "Fishing Pole")
      activate(game, bear)
      cast(game, "Test Wakeup", aim("Test Bear"))
      expect([obj(game, bear).tapped, obj(game, pole).tapped, obj(game, pole).counters["bait"].to_i]).to eq([false, true, 0])
      expect(game.state.battlefield.count { chars(game, it).name == "Fish" }).to eq(1)
      expect(activations(game, bear)).to be_empty
      game.state.object(bear).tapped = true
      cast(game, "Test Wakeup", aim("Test Bear")) # no bait counter left: no Fish
      expect(game.state.battlefield.count { chars(game, it).name == "Fish" }).to eq(1)
    end

    it "with two Poles, each granted ability taps its own Pole" do
      game = board(battlefield: ["Fishing Pole", "Fishing Pole", "Test Bear"], mana: { C: 9 })
      poles = game.state.battlefield.select { obj(game, it).card == "fishing_pole" }
      poles.each { activate(game, it, aim("Test Bear")) }
      bear = obj_id(game, "Test Bear")
      refs = activations(game, bear).map { it[:ability] }
      expect(refs.map { it[/@(.*)\z/, 1] }).to match_array(poles)
      play(game, activations(game, bear).find { it[:ability].end_with?("@#{poles.last}") })
      expect(poles.map { obj(game, it).tapped }).to eq([false, true])
      expect(poles.map { obj(game, it).counters["bait"].to_i }).to eq([0, 1])
    end
  end

  describe "Mondo Gecko (CR 607.2d)" do
    it "becomes the chosen color and gains hexproof from it; each activation keeps its own color" do
      game = board(hand: %w[Island Island], battlefield: ["Mondo Gecko"], mana: { C: 2 })
      gecko = obj_id(game, "Mondo Gecko")
      activate(game, gecko, pick("cost"), pick("color", color: "R"))
      expect(chars(game, gecko).colors).to eq([:R])
      activate(game, gecko, pick("cost"), pick("color", color: "G"))
      expect(chars(game, gecko).colors).to eq([:G])
      hexproof = chars(game, gecko).abilities.map(&:ability).select { it.kind == :hexproof_from }
      expect(hexproof.map { it.quality.colors }).to contain_exactly([:R], [:G])
      skip_to(game, :upkeep, turn: 4)
      expect(chars(game, gecko).colors).to eq([:U])
      expect(chars(game, gecko).abilities.map(&:ability).none? { it.kind == :hexproof_from }).to be(true)
    end

    it "an opponent's red spell can't target it after it chose red" do
      game = board(hand: ["Island"], battlefield: ["Mondo Gecko", "Test Bear"], mana: { C: 1 })
      gecko = obj_id(game, "Mondo Gecko")
      activate(game, gecko, pick("cost"), pick("color", color: "R"))
      e = engine(game)
      shock = e.create_object("test_shock", 1, :stack)
      frost = e.create_object("test_frost", 1, :stack)
      expect(e.targetable?(gecko, 1, targeter: shock.id)).to be(false)
      expect(e.targetable?(gecko, 1, targeter: frost.id)).to be(true)
      expect(e.targetable?(gecko, 0, targeter: shock.id)).to be(true) # only opponents' (CR 702.11d)
    end

    it "draws a card for each color among permanents you control when it deals combat damage to a player" do
      game = board(battlefield: ["Mondo Gecko", "Test Bear", "Test Wall"], step: :beginning_of_combat)
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      play(game, { type: "attack", object: obj_id(game, "Mondo Gecko"), target: bob }, pick("done"), resolve: false)
      skip_to(game, :end_of_combat)
      expect(ids_in(game, "alice", :hand).size).to eq(3) # blue, green, white
    end
  end

  describe "Spider-Woman, Secret Agent" do
    it "taps an opponent's creature, which can't become untapped while you control her" do
      game = board(hand: ["Spider-Woman, Secret Agent", "Test Wakeup"], theirs: ["Test Bear"], mana: { W: 5 })
      cast(game, "Spider-Woman, Secret Agent", aim("Test Bear"))
      bear = obj_id(game, "Test Bear")
      expect(obj(game, bear).tapped).to be(true)
      cast(game, "Test Wakeup", aim("Test Bear"))
      expect(obj(game, bear).tapped).to be(true)
      skip_to(game, :precombat_main, turn: 4)
      expect(obj(game, bear).tapped).to be(true)
    end

    it "the creature untaps normally once she leaves" do
      game = board(hand: ["Spider-Woman, Secret Agent"], theirs: ["Test Bear"], mana: { W: 4 })
      cast(game, "Spider-Woman, Secret Agent", aim("Test Bear"))
      bear = obj_id(game, "Test Bear")
      engine(game).move!(obj_id(game, "Spider-Woman, Secret Agent"), :graveyard, reason: "test")
      skip_to(game, :precombat_main, turn: 4)
      expect(obj(game, bear).tapped).to be(false)
    end
  end

  describe "Interface Ace" do
    it "untaps the first time it becomes tapped during your turn, only once each turn" do
      game = board(hand: ["Test Frost", "Test Frost"], battlefield: ["Interface Ace"], mana: { U: 2 })
      ace = obj_id(game, "Interface Ace")
      cast(game, "Test Frost", aim("Interface Ace"))
      expect(obj(game, ace).tapped).to be(false)
      cast(game, "Test Frost", aim("Interface Ace"))
      expect(obj(game, ace).tapped).to be(true)
    end

    it "doesn't untap when tapped during an opponent's turn, and that doesn't use up its once each turn" do
      game = board(battlefield: ["Interface Ace"], their_hand: ["Test Frost"], their_mana: { U: 1 }, active: "bob")
      ace = obj_id(game, "Interface Ace")
      play(game, { type: "cast", object: obj_id(game, "Test Frost", zone: :hand, player: "bob") }, aim("Interface Ace"))
      expect(obj(game, ace).tapped).to be(true)
    end

    it "crews using its toughness" do
      game = board(battlefield: ["Interface Ace"])
      ace = game.state.object(obj_id(game, "Interface Ace"))
      expect(Enjine::Mechanics::Abilities::TappingPower.of(engine(game), ace, :crew)).to eq(4)
    end
  end

  describe "Ghalta the Immovable (CR 510.1a)" do
    it "lets a defender attack and assigns combat damage equal to toughness" do
      game = board(battlefield: ["Ghalta the Immovable", "Test Wall"], step: :beginning_of_combat)
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      wall = obj_id(game, "Test Wall")
      play(game, { type: "attack", object: wall, target: bob }, pick("done"), resolve: false)
      skip_to(game, :end_of_combat)
      expect(life(game, "bob")).to eq(16)
    end

    it "a blocking creature with greater toughness assigns its toughness too (CR 510.1d)" do
      game = board(battlefield: ["Ghalta the Immovable", "Test Wall"], theirs: [["Test Bear"], ["Test Bear"]],
                   step: :beginning_of_combat, active: "bob")
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      bear = game.state.battlefield.find { obj(game, it).card == "test_bear" }
      play(game, { type: "attack", object: bear, target: "player:alice" }, pick("done"), resolve: false)
      game.submit(type: "pass") until game.pending_decision.kind == "declare_blockers"
      game.submit(type: "block", object: obj_id(game, "Test Wall"), attacker: bear)
      game.submit(type: "done") while game.pending_decision.kind == "declare_blockers"
      skip_to(game, :end_of_combat)
      expect(game.state.battlefield).not_to include(bear)
    end

    it "costs less by the greatest toughness among your creatures" do
      game = board(hand: ["Ghalta the Immovable"], battlefield: ["Test Wall"], mana: { W: 5 })
      expect(option_types(game)).to include("cast")
      cast(game, "Ghalta the Immovable")
      expect(obj_id(game, "Ghalta the Immovable")).not_to be_nil
    end
  end

  describe "Abzan Monument" do
    it "finds a basic Plains, Swamp or Forest, then makes an X/X Spirit for the greatest toughness" do
      game = board(hand: ["Abzan Monument"], library: %w[Island Forest Island], battlefield: ["Test Wall"], mana: { C: 2 })
      cast(game, "Abzan Monument", pick("find"))
      expect(ids_in(game, "alice", :hand).map { obj(game, it).card }).to eq(["forest"])
      game = board(battlefield: ["Abzan Monument", "Test Wall", "Test Bear"], mana: { C: 1, W: 1, B: 1, G: 1 })
      activate(game, obj_id(game, "Abzan Monument"))
      spirit = game.state.battlefield.find { chars(game, it).name == "Spirit" }
      expect(engine(game).power_toughness(obj(game, spirit))).to eq([4, 4])
    end
  end

  describe "Seifer Almasy (CR 506.5)" do
    def attack_with(game, *names)
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      names.each { game.submit(type: "attack", object: obj_id(game, it), target: bob) }
      game.submit(type: "done") if option_types(game).include?("done")
      game
    end

    it "a creature attacking alone gains double strike" do
      game = attack_with(board(battlefield: ["Seifer Almasy", "Test Bear"], step: :beginning_of_combat), "Test Bear")
      play(game, nil, resolve: true)
      expect(chars(game, obj_id(game, "Test Bear")).keyword?(:double_strike)).to be(true)
    end

    it "two attackers don't trigger it" do
      game = attack_with(board(battlefield: ["Seifer Almasy", "Test Bear"], step: :beginning_of_combat), "Test Bear",
                         "Seifer Almasy")
      expect(game.state.stack).to be_empty
      expect(chars(game, obj_id(game, "Test Bear")).keyword?(:double_strike)).to be(false)
    end

    it "Fire Cross casts an instant from the graveyard for free, then exiles it" do
      game = attack_with(board(battlefield: ["Seifer Almasy", "Test Bear"], graveyard: ["Test Shock"],
                               step: :beginning_of_combat), "Test Bear", "Seifer Almasy")
      game.submit(type: "pass") until game.pending_decision.kind == "choose_target"
      shock = obj_id(game, "Test Shock", zone: :graveyard, player: "alice")
      play(game, { type: "target", target: shock }, pick("cast"), pick("target", target: bob))
      expect(life(game, "bob")).to eq(20 - 3 - 2 - 2)
      expect(game.state.exile.map { obj(game, it).card }).to eq(["test_shock"])
    end
  end

  describe "Sorcerous Spyglass (CR 201.4, 602.5)" do
    it "looks at an opponent's hand, then stops abilities of the named source in any zone, except mana abilities" do
      game = board(hand: ["Sorcerous Spyglass"], mana: { C: 2 }, theirs: ["Test Relic"], their_hand: ["Test Cycler"],
                   their_mana: { C: 3 })
      cast(game, "Sorcerous Spyglass", pick("name", name: "Test Relic"))
      looked = game.history_for("alice").flat_map { it["events"] }.select { it["type"] == "looked_at" }
      expect(looked.flat_map { it["cards"] }).to eq(["test_cycler"])
      relic = obj_id(game, "Test Relic")
      e = engine(game)
      expect(e.activatable?(1, relic, "printed:0")).to be(false)
      expect(game.state.object(relic).tapped).to be(false)
      expect(e.chars(relic).mana_abilities).not_to be_empty
      cycler = obj_id(game, "Test Cycler", zone: :hand, player: "bob")
      expect(e.activatable?(1, cycler, e.chars(cycler).abilities.find { it.ability.kind == :activated }.ref)).to be(true)
    end

    it "naming a card stops its activated abilities in the hand too (cycling)" do
      game = board(hand: ["Sorcerous Spyglass"], mana: { C: 2 }, their_hand: ["Test Cycler"], their_mana: { C: 3 })
      cast(game, "Sorcerous Spyglass", pick("name", name: "Test Cycler"))
      e = engine(game)
      cycler = obj_id(game, "Test Cycler", zone: :hand, player: "bob")
      expect(e.activatable?(1, cycler, e.chars(cycler).abilities.find { it.ability.kind == :activated }.ref)).to be(false)
    end
  end

  describe "Petrified Hamlet (CR 607.2d)" do
    it "names a land card as it enters: those lands tap for {C} and their other abilities can't be activated" do
      game = board(hand: ["Petrified Hamlet"], theirs: ["Test Gate"])
      play(game, { type: "play_land", object: obj_id(game, "Petrified Hamlet", zone: :hand, player: "alice") },
           pick("card_name", card_name: "Test Gate"))
      gate = obj_id(game, "Test Gate")
      e = engine(game)
      expect(e.activatable?(1, gate, "printed:0")).to be(false)
      expect(e.chars(gate).mana_abilities.size).to eq(1)
      expect(game.state.object(obj_id(game, "Petrified Hamlet")).memory["chosen_name"]).to eq("Test Gate")
    end

    it "only land card names are offered" do
      game = board(hand: ["Petrified Hamlet"], theirs: ["Test Gate", "Test Relic"])
      game.submit(type: "play_land", object: obj_id(game, "Petrified Hamlet", zone: :hand, player: "alice"))
      game.submit(type: "pass") until game.pending_decision.kind != "priority"
      names = game.legal_options.map { it[:card_name] }
      expect(Enjine::CLI::Text.new(game).option(game.legal_options.first)).to start_with("Name ")
      expect(names).to include("Test Gate", "Petrified Hamlet", "Island")
      expect(names).not_to include("Test Relic")
    end
  end

  describe "Spider-Punk (CR 614.12, 702.136)" do
    it "another Spider entering gets riot's choice from Spider-Punk's static ability" do
      game = board(hand: ["Test Spider"], battlefield: ["Spider-Punk"], mana: { G: 2 })
      cast(game, "Test Spider", pick("option", option: "counter"))
      spider = obj_id(game, "Test Spider")
      expect(counters_of = obj(game, spider).counters).to eq("+1/+1" => 1)
      expect(counters_of).not_to be_empty
    end

    it "haste chosen with riot stays after Spider-Punk leaves" do
      game = board(hand: ["Test Spider"], battlefield: ["Spider-Punk"], mana: { G: 2 })
      cast(game, "Test Spider", pick("option", option: "haste"))
      spider = obj_id(game, "Test Spider")
      expect(chars(game, spider).keyword?(:haste)).to be(true)
      engine(game).move!(obj_id(game, "Spider-Punk"), :graveyard, reason: "test")
      expect(chars(game, spider).keyword?(:riot)).to be(false)
      expect(chars(game, spider).keyword?(:haste)).to be(true)
    end

    it "a non-Spider gets no choice; a Spider with riot of its own chooses for each instance (CR 702.136b)" do
      game = board(hand: ["Test Bear", "Spider-Punk"], battlefield: ["Spider-Punk"], mana: { G: 2 })
      cast(game, "Test Bear")
      expect(obj(game, obj_id(game, "Test Bear")).counters).to be_empty
      e = engine(game)
      punk = obj_id(game, "Spider-Punk", zone: :hand, player: "alice")
      expect(e.entering_choices(punk).size).to eq(2)
      e.move!(obj_id(game, "Spider-Punk"), :graveyard, reason: "test")
      expect(e.entering_choices(punk).size).to eq(1)
    end

    it "makes damage unpreventable and spells uncounterable" do
      game = board(battlefield: ["Spider-Punk"])
      e = engine(game)
      expect(e.unpreventable?(false)).to be(true)
      expect(e.player_rule?(1, "spells_cant_be_countered")).to be(true)
    end
  end

  describe "Storm, Windrider (CR 508.1c, 509.1b)" do
    it "creatures with flying can't attack you, but can attack your planeswalkers" do
      game = board(battlefield: ["Storm, Windrider", ["Chandra, Flameshaper", { loyalty: 6 }]],
                   theirs: ["Test Bird", "Test Bear"], step: :beginning_of_combat, active: "bob")
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      bird = obj_id(game, "Test Bird")
      bear = obj_id(game, "Test Bear")
      targets = ->(id) { game.legal_options.select { it[:object] == id }.map { it[:target] } }
      expect(targets.call(bird)).to eq([obj_id(game, "Chandra, Flameshaper")])
      expect(targets.call(bear)).to include("player:alice")
    end

    it "a flier with nothing it may attack isn't offered" do
      game = board(battlefield: ["Storm, Windrider"], theirs: ["Test Bird"], step: :beginning_of_combat, active: "bob")
      expect(engine(game).eligible_attackers).to be_empty
    end

    it "creatures with flying can't block your creatures" do
      game = board(battlefield: ["Storm, Windrider", "Test Bear"], theirs: ["Test Bird", "Test Spider"],
                   step: :beginning_of_combat)
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      bear = obj_id(game, "Test Bear")
      play(game, { type: "attack", object: bear, target: bob }, pick("done"), resolve: false)
      game.submit(type: "pass") until game.pending_decision.kind == "declare_blockers"
      blockers = game.legal_options.select { it[:type] == "block" }.map { it[:object] }
      expect(blockers).to eq([obj_id(game, "Test Spider")])
    end

    it "creatures your spells target gain flying" do
      game = board(hand: ["Test Frost"], battlefield: ["Storm, Windrider"], theirs: ["Test Bear"], mana: { U: 1 })
      cast(game, "Test Frost", aim("Test Bear"))
      expect(chars(game, obj_id(game, "Test Bear")).keyword?(:flying)).to be(true)
    end
  end

  describe "tapping_power granted by become" do
    it "a creature that becomes one that crews using its toughness" do
      grant = { "name" => "Test Crew Lesson", "mana_cost" => "{W}", "types" => ["instant"],
                "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [{ "become" => {
                  "abilities" => [{ "tapping_power" => { "for" => ["crew"], "use" => "toughness" } }], "to" => { "target" => 0 }
                } }] } }] }
      game = build_game(Enjine::Catalog.from_definitions(cards + basics + stand_ins + [grant])) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { W: 1 }) do
          hand "Test Crew Lesson"
          battlefield "Test Wall"
          library "Island", count: 3
        end
        player("bob") { library "Island", count: 3 }
      end
      cast(game, "Test Crew Lesson", aim("Test Wall"))
      wall = game.state.object(obj_id(game, "Test Wall"))
      expect(Enjine::Mechanics::Abilities::TappingPower.of(engine(game), wall, :crew)).to eq(4)
    end
  end

  describe "Chandra, Flameshaper" do
    it "+2: adds {R}{R}{R}, exiles three and lets you play the one you choose" do
      game = board(battlefield: ["Chandra, Flameshaper"], library: %w[Mountain Island Forest Swamp])
      chandra = obj_id(game, "Chandra, Flameshaper")
      activate(game, chandra, ->(g) { { type: "choose", object: g.state.exile.first } })
      expect(game.state.players[0].mana_pool[:R]).to eq(3)
      expect(game.state.exile.size).to eq(3)
      expect(option_types(game)).to include("play_land")
    end

    it "+1: a hasty token copy that is sacrificed at the end step" do
      game = board(battlefield: ["Chandra, Flameshaper", "Test Bear"])
      activate(game, obj_id(game, "Chandra, Flameshaper"), aim("Test Bear"), index: 1)
      copies = game.state.battlefield.select { obj(game, it).card == "test_bear" }
      token = copies.find { engine(game).token?(obj(game, it)) }
      expect(chars(game, token).keyword?(:haste)).to be(true)
      skip_to(game, :end)
      play(game, nil)
      expect(game.state.battlefield).not_to include(token)
      expect(copies - [token]).to all(satisfy { game.state.battlefield.include?(it) })
    end

    it "-4: 8 damage divided among creatures and planeswalkers" do
      game = board(battlefield: [["Chandra, Flameshaper", { loyalty: 6 }]], theirs: ["Test Bear", "Test Wall"])
      chandra = obj_id(game, "Chandra, Flameshaper")
      bear = obj_id(game, "Test Bear")
      wall = obj_id(game, "Test Wall")
      minus = activations(game, chandra).find { it[:ability] == "printed:2" }
      play(game, minus, { type: "count", count: 2 }, { type: "target", target: bear }, { type: "target", target: wall },
           *Array.new(4) { { type: "assign", target: wall } }, *Array.new(2) { { type: "assign", target: bear } })
      expect(game.state.battlefield).not_to include(bear)
      expect(game.state.battlefield).not_to include(wall)
      expect(game.state.object(chandra).counters["loyalty"]).to eq(2)
    end
  end
end
