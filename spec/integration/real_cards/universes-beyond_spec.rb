# frozen_string_literal: true

require "enjine/deck_builder"

# Real Standard cards from the Universes Beyond sets (Avatar: The Last Airbender, Spider-Man, Marvel Super
# Heroes, Teenage Mutant Ninja Turtles, The Hobbit), written by hand in the card DSL
# (spec/fixtures/cards/real/universes-beyond.json). Every card is cast or played and its own effect is
# checked; random decks the DeckBuilder makes from the pool are then fuzzed with the rules monitor.
RSpec.describe "Real cards: Universes Beyond" do
  let(:cards) { CardFixtures.real("universes-beyond") }
  let(:catalog) { Enjine::Catalog.from_definitions(cards) }
  let(:plenty) { Enjine::Mana::TYPES.to_h { [it, 9] } }
  let(:yes) { { type: "yes" } }

  # Alice's precombat main phase on turn 3, nine mana of each type in her pool. A field entry is a name or
  # [name, options] (tapped:, counters:).
  def board(hand: [], mine: [], theirs: [], graveyard: [], library: %w[Island Squirrelanoids Mountain],
            step: :precombat_main, mana: plenty)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana) do
        hand(*hand) unless hand.empty?
        mine.each { |name, opts| battlefield(name, **opts.to_h) }
        graveyard(*graveyard) unless graveyard.empty?
        library(*library, count: 4)
      end
      player("bob") do
        theirs.each { |name, opts| battlefield(name, **opts.to_h) }
        hand "Island", "Mountain"
        library "Island", count: 12
      end
    end
  end

  # Answers decisions until a player holds priority with an empty stack. `picks` (option hashes, matched on
  # the keys they give) are used in order whenever one fits; otherwise it passes, pays from the pool or takes
  # the first option.
  def settle(game, *picks)
    300.times do
      return game if game.pending_decision.kind == "priority" && game.state.stack.empty?

      options = game.legal_options
      pick = picks.first && options.find { |o| picks.first.all? { |k, v| o[k] == v } }
      picks.shift if pick
      game.submit(pick || options.find { it[:type] == "pass" } || options.find { it[:type] == "pay_mana" } ||
                  options.find { it[:type] != "cancel" })
    end
    raise "never settled"
  end

  def engine(game) = game.instance_variable_get(:@engine)

  # The first object named `name` (the face that's up) in a zone; the hand, library and graveyard are `player`'s.
  def id(game, name, zone = :battlefield, player: "alice")
    ids = %i[battlefield exile].include?(zone) ? game.state.public_send(zone) : ids_in(game, player, zone)
    ids.find { engine(game).definition(game.state.object(it)).name == name } or raise "no #{name} in #{zone}"
  end

  # Casts `name` from alice's `zone` with the cast option matching `option` (via: /alt/, face: 1, ...).
  def cast(game, name, *picks, zone: :hand, **option)
    card = id(game, name, zone)
    choice = game.legal_options.find do |o|
      o[:type] == "cast" && o[:object] == card && option.all? { |k, v| v.is_a?(Regexp) ? o[k].to_s.match?(v) : o[k] == v }
    end
    raise "#{name} can't be cast with #{option}: #{game.legal_options}" unless choice

    game.submit(choice)
    settle(game, *picks)
  end

  # Casts `name` and pays for it, leaving it on the stack with alice holding priority.
  def cast_only(game, name, *targets)
    game.submit(type: "cast", object: id(game, name, :hand))
    targets.each { game.submit(type: "target", target: it) }
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
  end

  def activate(game, name, *picks, n: 0, zone: :battlefield)
    source = id(game, name, zone)
    choice = game.legal_options.select { it[:type] == "activate" && it[:object] == source }[n]
    raise "no ability #{n} of #{name}: #{game.legal_options}" unless choice

    game.submit(choice)
    settle(game, *picks)
  end

  def play(game, land, *picks)
    game.submit(type: "play_land", object: id(game, land, :hand))
    settle(game, *picks)
  end

  # Passes to the declare attackers step, attacks bob with `names`, then settles the attack triggers.
  def attack(game, *names, picks: [])
    until game.pending_decision.kind == "declare_attackers"
      game.submit(game.legal_options.find { it[:type] == "pass" } || game.legal_options.first)
    end
    names.each { game.submit(type: "attack", object: id(game, it), target: "player:bob") }
    game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
    settle(game, *picks)
  end

  # Passes (declaring nothing) to alice's next precombat main phase, then settles its triggers with `picks`.
  def next_main(game, *picks)
    turn = game.turn + 2
    until game.turn == turn && game.step == :precombat_main
      options = game.legal_options
      game.submit(options.find { it[:type] == "pass" } || options.find { it[:type] == "done" } || options.first)
    end
    settle(game, *picks)
  end

  # Puts mana in alice's pool (options are computed again).
  def fill(game, **mana)
    mana.each { |type, n| game.state.players[0].mana_pool[type] = n }
    game.instance_variable_set(:@pending_decision, nil)
  end

  # A creature attacking bob unblocked, during alice's declare blockers step (for sneak, CR 702.190a).
  def unblocked!(game, name)
    game.state.attackers[id(game, name)] = { "target" => "player:bob", "blocked" => false }
    game.instance_variable_set(:@pending_decision, nil)
  end

  def view(game) = game.view_for(:observer)
  def life(game, who) = view(game)["players"].find { it["name"] == who }["life"]
  def perms(game, name) = view(game)["battlefield"].select { it["name"] == name }
  def perm(game, name) = perms(game, name).first || raise("no #{name} on the battlefield")
  def pt(game, name) = perm(game, name).values_at("power", "toughness")
  def chars(game, name) = engine(game).chars(game.state.object(perm(game, name)["id"]))
  def keywords(game, name) = chars(game, name).keywords.map(&:to_s)
  def zone(game, who, zone) = ids_in(game, who, zone).map { engine(game).definition(game.state.object(it)).name }
  def target(game, name, who = "bob", zone = :battlefield) = { type: "target", target: id(game, name, zone, player: who) }
  def discard(game, name) = { type: "discard", object: id(game, name, :hand) }
  def army(game) = view(game)["battlefield"].find { it["type_line"].include?("Army") } || raise("no Army")

  it "casts every nonland card from hand, and plays every land and taps it for mana" do
    needs_a_spell = %w[Spider-Sense Negate]
    cards.each do |data|
      defn = Enjine::CardDefinition.from_h(data)
      game = board(hand: [defn.name], mine: ["Squirrelanoids", "Futurist Forge"], theirs: ["A.I.M. Scientists", "Web Up"],
                   graveyard: ["Common Crook"])
      if defn.land?
        play(game, defn.name)
        mana = game.legal_options.find { it[:type] == "activate_mana" && it[:object] == id(game, defn.name) }
        next expect(perm(game, defn.name)["tapped"] || defn.mana_abilities.empty?).to be(true), defn.name unless mana

        before = game.state.players[0].mana_pool.values.sum
        game.submit(mana)
        expect(game.state.players[0].mana_pool.values.sum).to eq(before + 1), defn.name
      elsif needs_a_spell.include?(defn.name)
        expect(game.legal_options.none? { it[:type] == "cast" }).to be(true), "#{defn.name} needs a spell to target"
      else
        cast(game, defn.name)
        expect(zone(game, "alice", :hand)).not_to include(defn.name)
        moved = perms(game, defn.name).any? || zone(game, "alice", :graveyard).include?(defn.name) ||
                game.state.exile.any? { game.state.object(it).card == defn.id }
        expect(moved).to be(true), "#{defn.name} went nowhere"
      end
    end
  end

  describe "Spider-Man (spm)" do
    it "Electro's Bolt deals 4 to a creature; discarded, it is cast again for its mayhem cost" do
      game = board(hand: ["Romantic Rendezvous", "Electro's Bolt"], theirs: ["A.I.M. Scientists"])
      cast(game, "Romantic Rendezvous", discard(game, "Electro's Bolt"))
      expect(zone(game, "alice", :hand).size).to eq(2)
      cast(game, "Electro's Bolt", target(game, "A.I.M. Scientists"), zone: :graveyard, via: /alt/)
      expect(perms(game, "A.I.M. Scientists")).to be_empty
    end

    it "Spider-Man, Web-Slinger: web-slinging costs {W} and returns a tapped creature" do
      game = board(hand: ["Spider-Man, Web-Slinger"], mine: [["Squirrelanoids", { tapped: true }]], mana: { W: 1 })
      cast(game, "Spider-Man, Web-Slinger", { type: "cost", object: id(game, "Squirrelanoids") }, via: /alt/)
      expect(pt(game, "Spider-Man, Web-Slinger")).to eq([3, 3])
      expect(zone(game, "alice", :hand)).to eq(["Squirrelanoids"])
    end

    it "Spider-Sense and Negate counter a spell; Amazing Acrobatics counters one and taps two creatures" do
      %w[Spider-Sense Negate].each do |counter|
        game = board(hand: ["Lightning Strike", counter])
        cast_only(game, "Lightning Strike", "player:bob")
        cast(game, counter, { type: "target", target: game.state.stack.first })
        expect(life(game, "bob")).to eq(20)
        expect(zone(game, "alice", :graveyard)).to include("Lightning Strike", counter)
      end
      game = board(hand: ["Giant Growth", "Amazing Acrobatics"], mine: ["Squirrelanoids"], theirs: ["A.I.M. Scientists", "Canyon Crawler"])
      cast_only(game, "Giant Growth", id(game, "Squirrelanoids"))
      cast(game, "Amazing Acrobatics", { type: "mode", mode: 0 }, { type: "mode", mode: 1 }, { type: "target", target: game.state.stack.first },
           target(game, "A.I.M. Scientists"), target(game, "Canyon Crawler"))
      expect(pt(game, "Squirrelanoids")).to eq([1, 1])
      expect([perm(game, "A.I.M. Scientists"), perm(game, "Canyon Crawler")].map { it["tapped"] }).to eq([true, true])
    end

    it "Common Crook leaves a Treasure when it dies; City Pigeon a Food when it leaves" do
      game = board(hand: ["Common Crook", "Bilbo's Deadly Slice", "City Pigeon", "Whoosh!"])
      cast(game, "Common Crook")
      cast(game, "Bilbo's Deadly Slice", target(game, "Common Crook", "alice"))
      cast(game, "City Pigeon")
      cast(game, "Whoosh!", { type: "no_kick" }, target(game, "City Pigeon", "alice"))
      expect([perms(game, "Treasure").size, perms(game, "Food").size]).to eq([1, 1])
      expect(zone(game, "alice", :hand)).to include("City Pigeon")
    end

    it "Doc Ock's Henchmen connives when it attacks" do
      game = board(mine: ["Doc Ock's Henchmen"], hand: ["Electro's Bolt"])
      attack(game, "Doc Ock's Henchmen", picks: [discard(game, "Electro's Bolt")])
      expect(perm(game, "Doc Ock's Henchmen")["counters"]).to eq("+1/+1" => 1)
      expect(zone(game, "alice", :graveyard)).to eq(["Electro's Bolt"])
    end

    it "Swarm, Being of Bees is cast from the graveyard for {B} after it is discarded" do
      game = board(hand: ["Romantic Rendezvous", "Swarm, Being of Bees"])
      cast(game, "Romantic Rendezvous", discard(game, "Swarm, Being of Bees"))
      cast(game, "Swarm, Being of Bees", zone: :graveyard, via: /alt/)
      expect(keywords(game, "Swarm, Being of Bees")).to include("flash", "flying")
    end

    it "Kapow! puts a counter on your creature, then it fights" do
      game = board(hand: ["Kapow!"], mine: ["A.I.M. Scientists"], theirs: ["Long Lake Nuisance"])
      cast(game, "Kapow!", target(game, "A.I.M. Scientists", "alice"), target(game, "Long Lake Nuisance"))
      expect(perms(game, "Long Lake Nuisance")).to be_empty
      expect(perm(game, "A.I.M. Scientists")).to include("counters" => { "+1/+1" => 1 }, "damage" => 3)
    end

    it "Daily Bugle Reporters: counters on up to two creatures, or a cheap creature card back to hand" do
      game = board(hand: ["Daily Bugle Reporters"], mine: ["Squirrelanoids", "A.I.M. Synthoids"])
      cast(game, "Daily Bugle Reporters", { type: "mode", mode: 0 }, { type: "count", count: 2 }, target(game, "Squirrelanoids", "alice"),
           target(game, "A.I.M. Synthoids", "alice"))
      expect([perm(game, "Squirrelanoids"), perm(game, "A.I.M. Synthoids")].map { it["counters"] }).to all(eq("+1/+1" => 1))
      game = board(hand: ["Daily Bugle Reporters"], graveyard: ["Common Crook"])
      cast(game, "Daily Bugle Reporters", { type: "mode", mode: 1 })
      expect(zone(game, "alice", :hand)).to eq(["Common Crook"])
    end

    it "News Helicopter makes a Human Citizen" do
      game = board(hand: ["News Helicopter"])
      cast(game, "News Helicopter")
      expect(perm(game, "Human Citizen")).to include("power" => 1, "toughness" => 1)
    end

    it "Web-Shooters: +1/+1 and reach, and the equipped creature taps a blocker-to-be when it attacks" do
      game = board(hand: ["Web-Shooters"], mine: ["Squirrelanoids"], theirs: ["A.I.M. Scientists"])
      cast(game, "Web-Shooters")
      activate(game, "Web-Shooters", target(game, "Squirrelanoids", "alice"))
      expect(pt(game, "Squirrelanoids")).to eq([2, 2])
      expect(keywords(game, "Squirrelanoids")).to include("reach")
      attack(game, "Squirrelanoids")
      expect(perm(game, "A.I.M. Scientists")["tapped"]).to be(true)
    end

    it "Web Up exiles an opponent's nonland permanent until it leaves" do
      game = board(hand: ["Web Up", "Whoosh!"], theirs: ["A.I.M. Scientists"])
      cast(game, "Web Up", target(game, "A.I.M. Scientists"))
      expect(perms(game, "A.I.M. Scientists")).to be_empty
      cast(game, "Whoosh!", { type: "no_kick" }, target(game, "Web Up", "alice"))
      expect(perms(game, "A.I.M. Scientists")).not_to be_empty
    end

    it "Origin of Spider-Man: a Spider token, then a legendary Spider Hero with a counter, then double strike" do
      game = board(hand: ["Origin of Spider-Man"], mine: ["Squirrelanoids"])
      cast(game, "Origin of Spider-Man")
      expect(perm(game, "Spider")).to include("power" => 2, "toughness" => 1, "keywords" => ["reach"])
      next_main(game, target(game, "Squirrelanoids", "alice"))
      expect(perm(game, "Squirrelanoids")["counters"]).to eq("+1/+1" => 1)
      expect([chars(game, "Squirrelanoids").supertypes, chars(game, "Squirrelanoids").subtypes]).to eq([[:legendary], %i[squirrel mutant spider hero]])
      next_main(game, target(game, "Squirrelanoids", "alice"))
      expect(keywords(game, "Squirrelanoids")).to include("double_strike")
    end

    it "Ominous Asylum surveils for {4}" do
      game = board(mine: ["Ominous Asylum"])
      activate(game, "Ominous Asylum", { type: "graveyard" })
      expect(zone(game, "alice", :graveyard).size).to eq(1)
    end

    it "Vibrant Cityscape and Escape Tunnel fetch a basic land tapped; Escape Tunnel also makes a small creature unblockable" do
      ["Vibrant Cityscape", "Escape Tunnel"].each do |land|
        game = board(mine: [land])
        activate(game, land)
        expect(perm(game, "Island")["tapped"]).to be(true)
        expect(perms(game, land)).to be_empty
      end
      game = board(mine: ["Escape Tunnel", "Squirrelanoids"])
      activate(game, "Escape Tunnel", target(game, "Squirrelanoids", "alice"), n: 1)
      expect(keywords(game, "Squirrelanoids")).to include("cant_be_blocked")
    end

    it "Whoosh! kicked bounces and draws" do
      game = board(hand: ["Whoosh!"], theirs: ["A.I.M. Scientists"])
      cast(game, "Whoosh!", { type: "kick" }, target(game, "A.I.M. Scientists"))
      expect(zone(game, "bob", :hand)).to include("A.I.M. Scientists")
      expect(zone(game, "alice", :hand).size).to eq(1)
    end

    it "Steel Wrecking Ball deals 5 to a creature, and is discarded from hand to destroy an artifact" do
      game = board(hand: ["Steel Wrecking Ball"], theirs: ["Canyon Crawler"])
      cast(game, "Steel Wrecking Ball", target(game, "Canyon Crawler"))
      expect(perm(game, "Canyon Crawler")["damage"]).to eq(5)
      game = board(hand: ["Steel Wrecking Ball"], theirs: ["Futurist Forge"])
      activate(game, "Steel Wrecking Ball", target(game, "Futurist Forge"), zone: :hand)
      expect(perms(game, "Futurist Forge")).to be_empty
      expect(zone(game, "alice", :graveyard)).to eq(["Steel Wrecking Ball"])
    end

    it "Passenger Ferry: crewed, it attacks, and paying {U} makes another attacker unblockable" do
      game = board(hand: ["Passenger Ferry"], mine: ["A.I.M. Scientists", "Squirrelanoids", "Island"])
      cast(game, "Passenger Ferry")
      game.state.object(id(game, "Passenger Ferry")).controlled_since = 0
      activate(game, "Passenger Ferry", { type: "cost", object: id(game, "A.I.M. Scientists") }, { type: "done" })
      expect(pt(game, "Passenger Ferry")).to eq([4, 3])
      attack(game, "Passenger Ferry", "Squirrelanoids", picks: [yes, target(game, "Squirrelanoids", "alice")])
      expect(keywords(game, "Squirrelanoids")).to include("cant_be_blocked")
    end

    it "Scarlet Spider, Kaine may discard for a +1/+1 counter" do
      game = board(hand: ["Scarlet Spider, Kaine", "Island"])
      cast(game, "Scarlet Spider, Kaine", yes)
      expect(perm(game, "Scarlet Spider, Kaine")["counters"]).to eq("+1/+1" => 1)
    end

    it "Merciless Enforcers pings each opponent" do
      game = board(hand: ["Merciless Enforcers"])
      cast(game, "Merciless Enforcers")
      activate(game, "Merciless Enforcers")
      expect(life(game, "bob")).to eq(19)
    end

    it "Thwip! pumps and grants flying, Air Nomad Legacy gives flyers +1/+1, and the rules monitor agrees" do
      game = board(hand: ["Air Nomad Legacy", "Thwip!"], mine: ["Squirrelanoids"])
      cast(game, "Air Nomad Legacy")
      expect(perms(game, "Clue").size).to eq(1)
      monitor = Enjine::RulesMonitor.new(game)
      cast_only(game, "Thwip!", id(game, "Squirrelanoids"))
      monitor.check!(game.submit(type: "pass"))
      expect(monitor.check!(game.submit(type: "pass"))).to eq([])
      expect(pt(game, "Squirrelanoids")).to eq([4, 4])
      expect(life(game, "alice")).to eq(20) # not a Spider
    end
  end

  describe "Avatar: The Last Airbender (tla)" do
    it "Firebending Student and Fire Sages add {R} as they attack; Fire Sages grows" do
      game = board(mine: ["Firebending Student", "Fire Sages"])
      activate(game, "Fire Sages")
      expect(pt(game, "Fire Sages")).to eq([3, 3])
      attack(game, "Firebending Student", "Fire Sages")
      expect(view(game)["players"][0]["restricted_mana"].map { it.values_at("mana", "until") }).to eq([%w[R end_of_combat]] * 2)
    end

    it "Lightning Strike, and Firebending Lesson for 2 or kicked for 5" do
      game = board(hand: ["Lightning Strike", "Firebending Lesson"], theirs: ["Canyon Crawler"])
      cast(game, "Lightning Strike", { type: "target", target: "player:bob" })
      expect(life(game, "bob")).to eq(17)
      cast(game, "Firebending Lesson", { type: "no_kick" }, target(game, "Canyon Crawler"))
      expect(perm(game, "Canyon Crawler")["damage"]).to eq(2)
      game = board(hand: ["Firebending Lesson"], theirs: ["Canyon Crawler"])
      cast(game, "Firebending Lesson", { type: "kick" }, target(game, "Canyon Crawler"))
      expect(perm(game, "Canyon Crawler")["damage"]).to eq(5)
    end

    it "Iroh's Demonstration: 1 to each opposing creature, or 4 to one" do
      game = board(hand: ["Iroh's Demonstration"], mine: ["Squirrelanoids"], theirs: ["A.I.M. Scientists", "Canyon Crawler"])
      cast(game, "Iroh's Demonstration", { type: "mode", mode: 0 })
      expect([perm(game, "A.I.M. Scientists"), perm(game, "Canyon Crawler")].map { it["damage"] }).to eq([1, 1])
      expect(perm(game, "Squirrelanoids")["damage"]).to eq(0)
      game = board(hand: ["Iroh's Demonstration"], theirs: ["A.I.M. Scientists"])
      cast(game, "Iroh's Demonstration", { type: "mode", mode: 1 }, target(game, "A.I.M. Scientists"))
      expect(perms(game, "A.I.M. Scientists")).to be_empty
    end

    it "Kyoshi Warriors make an Ally; Kyoshi Battle Fan makes one and equips it" do
      game = board(hand: ["Kyoshi Warriors", "Kyoshi Battle Fan"])
      cast(game, "Kyoshi Warriors")
      cast(game, "Kyoshi Battle Fan")
      allies = perms(game, "Ally")
      expect(allies.map { it.values_at("power", "toughness") }).to contain_exactly([1, 1], [2, 1])
      expect(perm(game, "Kyoshi Battle Fan")["attached_to"]).to eq(allies.find { it["power"] == 2 }["id"])
    end

    it "Compassionate Healer gains 1 life and scries as it becomes tapped" do
      game = board(mine: ["Compassionate Healer"])
      attack(game, "Compassionate Healer", picks: [{ type: "bottom" }])
      expect(life(game, "alice")).to eq(21)
    end

    it "Callous Inspector deals 1 to you and leaves a Clue when it dies" do
      game = board(hand: ["Callous Inspector", "Bilbo's Deadly Slice"])
      cast(game, "Callous Inspector")
      cast(game, "Bilbo's Deadly Slice", target(game, "Callous Inspector", "alice"))
      expect([life(game, "alice"), perms(game, "Clue").size]).to eq([19, 1])
    end

    it "Canyon Crawler makes a Food and swampcycles; Mongoose Lizard pings and mountaincycles" do
      game = board(hand: ["Canyon Crawler", "Mongoose Lizard"])
      cast(game, "Canyon Crawler")
      cast(game, "Mongoose Lizard", { type: "target", target: "player:bob" })
      expect([perms(game, "Food").size, life(game, "bob")]).to eq([1, 19])
      game = board(hand: ["Canyon Crawler", "Mongoose Lizard"], library: %w[Swamp Mountain Island])
      activate(game, "Canyon Crawler", zone: :hand)
      activate(game, "Mongoose Lizard", zone: :hand)
      expect(zone(game, "alice", :hand)).to contain_exactly("Swamp", "Mountain")
    end

    it "Mai, Jaded Edge gets a double strike counter, once" do
      game = board(mine: ["Mai, Jaded Edge"])
      activate(game, "Mai, Jaded Edge")
      expect(keywords(game, "Mai, Jaded Edge")).to include("double_strike")
      expect(game.legal_options.none? { it[:type] == "activate" }).to be(true)
    end

    it "Meteor Sword destroys a permanent (a Fire Nation Warship, which leaves a Clue) and gives +3/+3" do
      game = board(hand: ["Fire Nation Warship", "Meteor Sword"], mine: ["Squirrelanoids"])
      cast(game, "Fire Nation Warship")
      cast(game, "Meteor Sword", target(game, "Fire Nation Warship", "alice"))
      expect(perms(game, "Clue").size).to eq(1)
      activate(game, "Meteor Sword", target(game, "Squirrelanoids", "alice"))
      expect(pt(game, "Squirrelanoids")).to eq([4, 4])
    end

    it "Fire Nation Warship is a 4/4 reach creature once crewed" do
      game = board(mine: ["Fire Nation Warship", "A.I.M. Scientists"])
      activate(game, "Fire Nation Warship", { type: "cost", object: id(game, "A.I.M. Scientists") }, { type: "done" })
      expect(pt(game, "Fire Nation Warship")).to eq([4, 4])
      expect(keywords(game, "Fire Nation Warship")).to include("reach")
    end

    it "Airship Engine Room draws when sacrificed; Abandoned Air Temple enters untapped beside a basic and grows the team" do
      game = board(mine: ["Airship Engine Room"])
      activate(game, "Airship Engine Room")
      expect(zone(game, "alice", :hand).size).to eq(1)
      game = board(hand: ["Abandoned Air Temple"])
      play(game, "Abandoned Air Temple")
      expect(perm(game, "Abandoned Air Temple")["tapped"]).to be(true)
      game = board(hand: ["Abandoned Air Temple"], mine: %w[Plains Squirrelanoids])
      play(game, "Abandoned Air Temple")
      expect(perm(game, "Abandoned Air Temple")["tapped"]).to be(false)
      activate(game, "Abandoned Air Temple")
      expect(perm(game, "Squirrelanoids")["counters"]).to eq("+1/+1" => 1)
    end

    it "Leaves from the Vine: mill three and a Food, then counters, then a card for a creature in the graveyard" do
      game = board(hand: ["Leaves from the Vine"], mine: ["Squirrelanoids"], graveyard: ["Common Crook"])
      cast(game, "Leaves from the Vine")
      expect([zone(game, "alice", :graveyard).size, perms(game, "Food").size]).to eq([4, 1])
      next_main(game, { type: "count", count: 1 }, target(game, "Squirrelanoids", "alice"))
      expect(perm(game, "Squirrelanoids")["counters"]).to eq("+1/+1" => 1)
      hand = zone(game, "alice", :hand).size
      next_main(game)
      expect(zone(game, "alice", :hand).size).to eq(hand + 2) # the draw step and chapter III
    end

    it "Azula Always Lies shrinks one creature and grows another" do
      game = board(hand: ["Azula Always Lies"], mine: ["Squirrelanoids"], theirs: ["A.I.M. Scientists"])
      cast(game, "Azula Always Lies", { type: "mode", mode: 0 }, { type: "mode", mode: 1 }, target(game, "A.I.M. Scientists"),
           target(game, "Squirrelanoids", "alice"))
      expect([pt(game, "A.I.M. Scientists"), pt(game, "Squirrelanoids")]).to eq([[2, 2], [2, 2]])
    end

    it "Octopus Form untaps and protects your creature" do
      game = board(hand: ["Octopus Form"], mine: [["Squirrelanoids", { tapped: true }]])
      cast(game, "Octopus Form", target(game, "Squirrelanoids", "alice"))
      expect(perm(game, "Squirrelanoids")).to include("tapped" => false, "power" => 2)
      expect(keywords(game, "Squirrelanoids")).to include("hexproof")
    end

    it "Fire Nation Attacks makes two firebending Soldiers, and again with flashback" do
      game = board(hand: ["Fire Nation Attacks"])
      cast(game, "Fire Nation Attacks")
      cast(game, "Fire Nation Attacks", zone: :graveyard, via: /alt/)
      expect(perms(game, "Soldier").map { it.values_at("power", "toughness") }).to eq([[2, 2]] * 4)
      expect(game.state.exile.size).to eq(1)
    end

    it "Epic Downfall exiles a creature with mana value 3 or greater" do
      game = board(hand: ["Epic Downfall"], theirs: ["A.I.M. Scientists", "Squirrelanoids"])
      game.submit(type: "cast", object: id(game, "Epic Downfall", :hand))
      expect(game.legal_options.map { it[:target] }.compact).to eq([id(game, "A.I.M. Scientists", player: "bob")])
      settle(game)
      expect(perms(game, "A.I.M. Scientists")).to be_empty
    end

    it "The Legend of Roku: impulse draw, mana, then it becomes Avatar Roku, who makes Dragons" do
      game = board(hand: ["The Legend of Roku"])
      cast(game, "The Legend of Roku")
      expect(game.state.exile.size).to eq(3)
      expect(game.legal_options.count { it[:type] == "play_land" || (it[:type] == "cast" && game.state.exile.include?(it[:object])) }).to be_positive
      next_main(game)
      next_main(game)
      expect(pt(game, "Avatar Roku")).to eq([4, 4])
      fill(game, C: 8)
      activate(game, "Avatar Roku")
      expect(perm(game, "Dragon")).to include("power" => 4, "keywords" => ["flying"])
    end

    it "Earth Kingdom Jailer exiles an opponent's permanent with mana value 3 or greater until it leaves" do
      game = board(hand: ["Earth Kingdom Jailer"], theirs: ["A.I.M. Scientists"])
      cast(game, "Earth Kingdom Jailer", target(game, "A.I.M. Scientists"))
      expect(perms(game, "A.I.M. Scientists")).to be_empty
    end
  end

  describe "The Hobbit (hob)" do
    it "Rage into the Valley draws, costs 1 life and amasses Goblins 2; Goblin-town Flunkies amass 1 more" do
      game = board(hand: ["Rage into the Valley", "Goblin-town Flunkies"])
      cast(game, "Rage into the Valley")
      expect([life(game, "alice"), zone(game, "alice", :hand).size, army(game)["power"]]).to eq([19, 2, 2])
      cast(game, "Goblin-town Flunkies")
      expect(army(game)).to include("power" => 3, "type_line" => include("Goblin"))
    end

    it "Goblin Plate Mail amasses and equips the Army" do
      game = board(hand: ["Goblin Plate Mail"])
      cast(game, "Goblin Plate Mail")
      expect(army(game).values_at("power", "toughness")).to eq([2, 1])
      expect(perm(game, "Goblin Plate Mail")["attached_to"]).to eq(army(game)["id"])
    end

    it "Long Lake Nuisance recruits: a nonland discard makes a Human Soldier" do
      game = board(hand: ["Long Lake Nuisance", "Electro's Bolt"])
      cast(game, "Long Lake Nuisance", discard(game, "Electro's Bolt"))
      expect(perm(game, "Human Soldier").values_at("power", "toughness")).to eq([1, 1])
    end

    it "Plunder the Trollshaws draws one, and two with flashback; Tidings of War amasses 1, then 3 with flashback" do
      game = board(hand: ["Plunder the Trollshaws", "Tidings of War"])
      cast(game, "Plunder the Trollshaws")
      expect(zone(game, "alice", :hand).size).to eq(2)
      cast(game, "Plunder the Trollshaws", zone: :graveyard, via: /alt/)
      expect(zone(game, "alice", :hand).size).to eq(4)
      cast(game, "Tidings of War")
      cast(game, "Tidings of War", zone: :graveyard, via: /alt/)
      expect(army(game)["power"]).to eq(4)
    end

    it "Attercop gets +1/+1 when a land enters under your control" do
      game = board(mine: ["Attercop"], hand: ["Island"])
      play(game, "Island")
      expect(pt(game, "Attercop")).to eq([3, 2])
    end

    it "Gigantic Big Bear can't be countered" do
      game = board(hand: ["Gigantic Big Bear", "Amazing Acrobatics"])
      cast_only(game, "Gigantic Big Bear")
      cast(game, "Amazing Acrobatics", { type: "mode", mode: 0 }, { type: "done" }, { type: "target", target: game.state.stack.first })
      expect(pt(game, "Gigantic Big Bear")).to eq([10, 7])
      expect(keywords(game, "Gigantic Big Bear")).to include("hexproof", "haste")
    end

    it "Wood Elves put a Forest onto the battlefield untapped" do
      game = board(hand: ["Wood Elves"], library: %w[Forest Island Mountain])
      cast(game, "Wood Elves")
      expect(perm(game, "Forest")["tapped"]).to be(false)
    end

    it "Long-Bodied Grey Dog makes a tapped Treasure" do
      game = board(hand: ["Long-Bodied Grey Dog"])
      cast(game, "Long-Bodied Grey Dog")
      expect(perm(game, "Treasure")["tapped"]).to be(true)
    end

    it "Mirkwood Pathmaker is as big as your land count" do
      game = board(hand: ["Mirkwood Pathmaker"], mine: %w[Forest Island Plains])
      cast(game, "Mirkwood Pathmaker")
      expect(pt(game, "Mirkwood Pathmaker")).to eq([3, 3])
    end

    it "Well-Worn Spatula gains 2 life and gives +1/+1" do
      game = board(hand: ["Well-Worn Spatula"], mine: ["Squirrelanoids"])
      cast(game, "Well-Worn Spatula")
      activate(game, "Well-Worn Spatula", target(game, "Squirrelanoids", "alice"))
      expect([life(game, "alice"), pt(game, "Squirrelanoids")]).to eq([22, [2, 2]])
    end

    it "Thrór's Map finds a basic land, then loots" do
      game = board(hand: ["Thrór's Map"])
      cast(game, "Thrór's Map")
      expect(zone(game, "alice", :hand)).to eq(["Island"])
      activate(game, "Thrór's Map", discard(game, "Island"))
      expect(zone(game, "alice", :graveyard)).to eq(["Island"])
      expect(zone(game, "alice", :hand).size).to eq(1)
    end

    it "Giant's Boulder scries 2, taps for any color and destroys a permanent" do
      game = board(hand: ["Giant's Boulder"], theirs: ["A.I.M. Scientists"])
      cast(game, "Giant's Boulder", { type: "bottom" })
      expect(game.legal_options.select { it[:type] == "activate_mana" }.map { it[:mana] }).to include("{W}", "{G}")
      activate(game, "Giant's Boulder", target(game, "A.I.M. Scientists"))
      expect(perms(game, "A.I.M. Scientists")).to be_empty
    end

    it "Hobbit Hole fetches a basic land and halflingcycles" do
      game = board(hand: ["Hobbit Hole"], mine: ["Hobbit Hole"])
      activate(game, "Hobbit Hole")
      expect(perm(game, "Island")["tapped"]).to be(true)
      activate(game, "Hobbit Hole", zone: :hand)
      expect(zone(game, "alice", :graveyard)).to eq(["Hobbit Hole", "Hobbit Hole"])
    end

    it "Velvetwing Butterflies // Gaze in Wonder: the Adventure taps two creatures, then the Butterflies are cast from exile" do
      game = board(hand: ["Velvetwing Butterflies"], theirs: ["A.I.M. Scientists", "Canyon Crawler"])
      cast(game, "Velvetwing Butterflies", target(game, "A.I.M. Scientists"), target(game, "Canyon Crawler"), face: 1)
      expect([perm(game, "A.I.M. Scientists"), perm(game, "Canyon Crawler")].map { it["tapped"] }).to eq([true, true])
      cast(game, "Velvetwing Butterflies", zone: :exile)
      expect(keywords(game, "Velvetwing Butterflies")).to eq(["flying"])
    end

    it "Smaug, the Great Calamity // Spew Flame: 5 damage, then a 5/5 flying Dragon" do
      game = board(hand: ["Smaug, the Great Calamity"], theirs: ["Canyon Crawler"])
      cast(game, "Smaug, the Great Calamity", target(game, "Canyon Crawler"), face: 1)
      expect(perm(game, "Canyon Crawler")["damage"]).to eq(5)
      cast(game, "Smaug, the Great Calamity", zone: :exile)
      expect(pt(game, "Smaug, the Great Calamity")).to eq([5, 5])
    end

    it "Burn, Burn, Tree and Fern deals 6, destroys an artifact, then adds {R} twice" do
      game = board(hand: ["Burn, Burn, Tree and Fern"], theirs: ["Canyon Crawler", "Futurist Forge"])
      cast(game, "Burn, Burn, Tree and Fern", target(game, "Canyon Crawler"))
      expect(perms(game, "Canyon Crawler")).to be_empty
      next_main(game, target(game, "Futurist Forge"))
      expect(perms(game, "Futurist Forge")).to be_empty
      next_main(game)
      expect(game.state.players[0].mana_pool[:R]).to eq(1)
      next_main(game)
      expect(perms(game, "Burn, Burn, Tree and Fern")).to be_empty
    end

    it "Quarrel: your creature deals damage equal to its power, taking none back" do
      game = board(hand: ["Quarrel"], mine: ["A.I.M. Scientists"], theirs: ["Canyon Crawler"])
      cast(game, "Quarrel", target(game, "A.I.M. Scientists", "alice"), target(game, "Canyon Crawler"))
      expect([perm(game, "Canyon Crawler")["damage"], perm(game, "A.I.M. Scientists")["damage"]]).to eq([3, 0])
    end

    it "Magnificent End costs {3} less against a tapped creature" do
      game = board(hand: ["Magnificent End"], theirs: [["Canyon Crawler", { tapped: true }]], mana: { W: 1, C: 1 })
      cast(game, "Magnificent End", target(game, "Canyon Crawler"))
      expect(perm(game, "Canyon Crawler")["damage"]).to eq(5)
    end

    it "Nasty Little Rabbit and Ravening Warg are ferocious beside a 4-power creature" do
      game = board(mine: ["Nasty Little Rabbit", "Ravening Warg", "Canyon Crawler"])
      attack(game, "Ravening Warg")
      expect(perm(game, "Nasty Little Rabbit")["counters"]).to eq("+1/+1" => 1)
      expect(life(game, "alice")).to eq(22)
    end

    it "Stony-Voiced Goblins make each opponent discard" do
      game = board(hand: ["Stony-Voiced Goblins"])
      cast(game, "Stony-Voiced Goblins")
      expect(zone(game, "bob", :hand).size).to eq(1)
    end
  end

  describe "Teenage Mutant Ninja Turtles (tmt)" do
    def sneak_board(*hand, mine: ["Squirrelanoids"], mana: plenty)
      game = board(hand: hand, mine: mine, step: :declare_blockers, mana: mana)
      unblocked!(game, "Squirrelanoids")
      game
    end

    it "Squirrelanoids has deathtouch" do
      expect(perm(board(mine: ["Squirrelanoids"]), "Squirrelanoids")["keywords"]).to eq(["deathtouch"])
    end

    it "Donatello's Technique is sneaked for {U} to draw two" do
      game = sneak_board("Donatello's Technique", mana: { U: 1 })
      cast(game, "Donatello's Technique", { type: "cost", object: id(game, "Squirrelanoids") }, via: /alt/)
      expect(zone(game, "alice", :hand).size).to eq(3) # the returned attacker and two cards
    end

    it "Foot Ninjas sneak in attacking and gain 3 life; Splinter makes them bigger, and the monitor allows the sneak" do
      game = sneak_board("Foot Ninjas", mine: ["Squirrelanoids", "Splinter, Hamato Yoshi"])
      monitor = Enjine::RulesMonitor.new(game)
      ninjas = game.legal_options.find { it[:type] == "cast" && it[:via].to_s.start_with?("alt") }
      expect(monitor.check!(game.submit(ninjas))).to eq([])
      until game.pending_decision.kind == "priority"
        expect(monitor.check!(game.submit(game.legal_options.find { it[:type] != "cancel" }))).to eq([])
      end
      settle(game)
      expect(perm(game, "Foot Ninjas")).to include("tapped" => true, "attacking" => "player:bob", "power" => 6, "toughness" => 6)
      expect(life(game, "alice")).to eq(23)
    end

    it "Leonardo, Big Brother and Splinter, Hamato Yoshi sneak in; Leonardo gets +1/+0 for each other creature" do
      game = sneak_board("Leonardo, Big Brother", mine: ["Squirrelanoids", "A.I.M. Scientists", "Canyon Crawler"])
      cast(game, "Leonardo, Big Brother", { type: "cost", object: id(game, "Squirrelanoids") }, via: /alt/)
      expect(pt(game, "Leonardo, Big Brother")).to eq([3, 3])
      game = sneak_board("Splinter, Hamato Yoshi")
      cast(game, "Splinter, Hamato Yoshi", { type: "cost", object: id(game, "Squirrelanoids") }, via: /alt/)
      expect(perm(game, "Splinter, Hamato Yoshi")["attacking"]).to eq("player:bob")
    end

    it "alliance: EPF Point Squad grows, East Wind Avatar gets +1/+0, Raphael pings an opponent" do
      game = board(hand: ["Squirrelanoids"], mine: ["EPF Point Squad", "East Wind Avatar", "Raphael, Tough Turtle"])
      cast(game, "Squirrelanoids", { type: "target", target: "player:bob" })
      expect([perm(game, "EPF Point Squad")["counters"], pt(game, "East Wind Avatar"), life(game, "bob")])
        .to eq([{ "+1/+1" => 1 }, [3, 4], 19])
    end

    it "Mouser Foundry makes a Robot as it enters and as it leaves, and deals 3 when sacrificed" do
      game = board(hand: ["Mouser Foundry"], theirs: ["A.I.M. Scientists"])
      cast(game, "Mouser Foundry")
      activate(game, "Mouser Foundry", target(game, "A.I.M. Scientists"))
      expect([perms(game, "Robot").size, perms(game, "A.I.M. Scientists").size]).to eq([2, 0])
    end

    it "pizzas: Anchovy & Banana destroys, Guac & Marshmallow pumps and untaps, Omni-Cheese draws and makes mana; all are Food" do
      game = board(hand: ["Anchovy & Banana Pizza", "Guac & Marshmallow Pizza", "Omni-Cheese Pizza"],
                   mine: [["Squirrelanoids", { tapped: true }]], theirs: ["A.I.M. Scientists"])
      cast(game, "Anchovy & Banana Pizza", target(game, "A.I.M. Scientists"))
      cast(game, "Guac & Marshmallow Pizza", target(game, "Squirrelanoids", "alice"))
      cast(game, "Omni-Cheese Pizza")
      expect([perms(game, "A.I.M. Scientists"), perm(game, "Squirrelanoids").values_at("tapped", "power")]).to eq([[], [false, 3]])
      expect(zone(game, "alice", :hand).size).to eq(1)
      game.submit(game.legal_options.find { it[:type] == "activate_mana" && it[:object] == id(game, "Omni-Cheese Pizza") })
      activate(game, "Anchovy & Banana Pizza")
      expect([perms(game, "Omni-Cheese Pizza"), life(game, "alice")]).to eq([[], 23])
    end

    it "Mouser Attack! makes a Robot, or gives +3/+0 and first strike" do
      game = board(hand: ["Mouser Attack!"], mine: ["Squirrelanoids"])
      cast(game, "Mouser Attack!", { type: "mode", mode: 1 }, target(game, "Squirrelanoids", "alice"))
      expect([pt(game, "Squirrelanoids"), keywords(game, "Squirrelanoids")]).to eq([[4, 1], %w[deathtouch first_strike]])
    end

    it "Dimension X enters tapped and gains 1 life" do
      game = board(hand: ["Dimension X"])
      play(game, "Dimension X")
      expect([perm(game, "Dimension X")["tapped"], life(game, "alice")]).to eq([true, 21])
    end

    it "Turtle Power! gives Turtles +2/+2" do
      game = board(hand: ["Turtle Power!"], mine: ["Raphael, Tough Turtle", "Squirrelanoids"])
      cast(game, "Turtle Power!")
      expect([pt(game, "Raphael, Tough Turtle"), pt(game, "Squirrelanoids")]).to eq([[3, 5], [1, 1]])
    end

    it "Insectoid Exterminator scries at your end step if a permanent left under your control" do
      game = board(mine: ["Insectoid Exterminator", "Vibrant Cityscape"])
      activate(game, "Vibrant Cityscape")
      top = ids_in(game, "alice", :library).first
      until game.step == :end && game.pending_decision.kind == "effect_choice"
        game.submit(game.legal_options.find { it[:type] == "pass" } || game.legal_options.find { it[:type] == "done" })
      end
      settle(game, { type: "bottom" })
      expect(ids_in(game, "alice", :library).last).to eq(top)
    end

    it "Tunnel Rats return from the graveyard tapped" do
      game = board(graveyard: ["Tunnel Rats"])
      activate(game, "Tunnel Rats", zone: :graveyard)
      expect(perm(game, "Tunnel Rats")["tapped"]).to be(true)
    end

    it "Utrom Scientists tap a creature and stun it" do
      game = board(hand: ["Utrom Scientists"], theirs: ["A.I.M. Scientists"])
      cast(game, "Utrom Scientists", target(game, "A.I.M. Scientists"))
      expect(perm(game, "A.I.M. Scientists")).to include("tapped" => true, "counters" => { "stun" => 1 })
    end

    it "Turtle Blimp makes a Mutant that can crew it" do
      game = board(hand: ["Turtle Blimp"])
      cast(game, "Turtle Blimp")
      activate(game, "Turtle Blimp", { type: "cost", object: perm(game, "Mutant")["id"] }, { type: "done" })
      expect(pt(game, "Turtle Blimp")).to eq([3, 4])
    end

    it "Skateboard taps a permanent and gives +1/+0 and haste" do
      game = board(hand: ["Skateboard"], mine: ["Squirrelanoids"], theirs: ["A.I.M. Scientists"])
      cast(game, "Skateboard", target(game, "A.I.M. Scientists"))
      activate(game, "Skateboard", target(game, "Squirrelanoids", "alice"))
      expect([perm(game, "A.I.M. Scientists")["tapped"], pt(game, "Squirrelanoids"), keywords(game, "Squirrelanoids")])
        .to eq([true, [2, 1], %w[deathtouch haste]])
    end
  end

  describe "Marvel Super Heroes (msh)" do
    it "Agents of HYDRA leave a 2/1 menace Villain; Hire a Crew makes one and pumps the team" do
      game = board(hand: ["Agents of HYDRA", "Dark Deed", "Hire a Crew"])
      cast(game, "Agents of HYDRA")
      cast(game, "Dark Deed", target(game, "Agents of HYDRA", "alice"))
      expect(perm(game, "Villain")).to include("power" => 2, "keywords" => ["menace"])
      cast(game, "Hire a Crew")
      expect(perms(game, "Villain").map { it["power"] }).to eq([3, 3])
    end

    it "A.I.M. Scientists connive; A.I.M. Synthoids surveil 2" do
      game = board(hand: ["A.I.M. Scientists", "A.I.M. Synthoids", "Giant Growth"])
      cast(game, "A.I.M. Scientists", discard(game, "Giant Growth"))
      expect(perm(game, "A.I.M. Scientists")["counters"]).to eq("+1/+1" => 1)
      cast(game, "A.I.M. Synthoids", { type: "graveyard" }, { type: "graveyard" })
      expect(zone(game, "alice", :graveyard).size).to eq(3)
    end

    it "Dark Deed gives -4/-4; Giant Growth +3/+3" do
      game = board(hand: ["Dark Deed", "Giant Growth"], theirs: ["Canyon Crawler"])
      cast(game, "Dark Deed", target(game, "Canyon Crawler"))
      cast(game, "Giant Growth", target(game, "Canyon Crawler"))
      expect(pt(game, "Canyon Crawler")).to eq([5, 5])
    end

    it "Kree Sentinel basic-landcycles" do
      game = board(hand: ["Kree Sentinel"], library: %w[Plains Squirrelanoids])
      activate(game, "Kree Sentinel", zone: :hand)
      expect(zone(game, "alice", :hand)).to eq(["Plains"])
    end

    it "Stark Industries Executive makes a Treasure" do
      game = board(mine: ["Stark Industries Executive"])
      activate(game, "Stark Industries Executive")
      expect(perms(game, "Treasure").size).to eq(1)
    end

    it "Futurist Forge draws one, then two when sacrificed" do
      game = board(hand: ["Futurist Forge"])
      cast(game, "Futurist Forge")
      activate(game, "Futurist Forge")
      expect(zone(game, "alice", :hand).size).to eq(3)
    end

    it "Super Villain Lockup exiles a tapped opposing creature" do
      game = board(hand: ["Super Villain Lockup"], theirs: [["A.I.M. Scientists", { tapped: true }], "Canyon Crawler"])
      cast(game, "Super Villain Lockup", target(game, "A.I.M. Scientists"))
      expect(perms(game, "A.I.M. Scientists")).to be_empty
    end

    it "Super Speed gives first strike this turn, and +1/+0 and haste" do
      game = board(hand: ["Super Speed"], mine: ["Squirrelanoids"])
      cast(game, "Super Speed", target(game, "Squirrelanoids", "alice"))
      expect(pt(game, "Squirrelanoids")).to eq([2, 1])
      expect(keywords(game, "Squirrelanoids")).to contain_exactly("deathtouch", "first_strike", "haste")
    end

    it "Vibranium Energy Daggers are indestructible and give +2/+2" do
      game = board(hand: ["Vibranium Energy Daggers"], mine: ["Squirrelanoids"])
      cast(game, "Vibranium Energy Daggers")
      activate(game, "Vibranium Energy Daggers", target(game, "Squirrelanoids", "alice"))
      expect([pt(game, "Squirrelanoids"), keywords(game, "Vibranium Energy Daggers")]).to eq([[3, 3], ["indestructible"]])
    end

    it "Dependable Quinjet taps for mana and needs crew 4; S.H.I.E.L.D. Helicarrier brings two Soldiers" do
      game = board(hand: ["S.H.I.E.L.D. Helicarrier"], mine: ["Dependable Quinjet", "Canyon Crawler"])
      cast(game, "S.H.I.E.L.D. Helicarrier")
      expect(perms(game, "Soldier").size).to eq(2)
      game.submit(game.legal_options.find { it[:type] == "activate_mana" && it[:object] == id(game, "Dependable Quinjet") })
      expect(perm(game, "Dependable Quinjet")["tapped"]).to be(true)
      game = board(mine: ["Dependable Quinjet", "Canyon Crawler"])
      activate(game, "Dependable Quinjet", { type: "cost", object: id(game, "Canyon Crawler") }, { type: "done" })
      expect(pt(game, "Dependable Quinjet")).to eq([3, 3])
    end

    it "Visions of Villainy costs {1} less with a Villain; Truck Toss {2} less with a Vehicle" do
      game = board(hand: ["Visions of Villainy", "Truck Toss"], mine: ["A.I.M. Scientists", "Passenger Ferry"], mana: { B: 1, C: 1 })
      cast(game, "Visions of Villainy")
      fill(game, R: 2)
      cast(game, "Truck Toss", { type: "target", target: "player:bob" })
      expect([zone(game, "alice", :hand).size, life(game, "alice"), life(game, "bob")]).to eq([2, 18, 16])
    end

    it "Take Up the Shield: a counter, lifelink and indestructible" do
      game = board(hand: ["Take Up the Shield"], mine: ["Squirrelanoids"])
      cast(game, "Take Up the Shield", target(game, "Squirrelanoids", "alice"))
      expect(keywords(game, "Squirrelanoids")).to eq(%w[deathtouch lifelink indestructible])
    end

    it "Pym Particles: vigilance, unblockable, and a card" do
      game = board(hand: ["Pym Particles"], mine: ["Squirrelanoids"])
      cast(game, "Pym Particles", target(game, "Squirrelanoids", "alice"))
      expect([keywords(game, "Squirrelanoids"), zone(game, "alice", :hand).size]).to eq([%w[deathtouch vigilance cant_be_blocked], 1])
    end

    it "Machinesmith Automaton grows when another artifact enters" do
      game = board(hand: ["Futurist Forge"], mine: ["Machinesmith Automaton"])
      cast(game, "Futurist Forge")
      expect(pt(game, "Machinesmith Automaton")).to eq([3, 3])
    end

    it "Guerrilla Gorilla is sacrificed to destroy a noncreature artifact" do
      game = board(mine: ["Guerrilla Gorilla"], theirs: ["Futurist Forge", "A.I.M. Synthoids"])
      game.submit(game.legal_options.find { it[:type] == "activate" })
      expect(game.legal_options.map { it[:target] }.compact).to eq([id(game, "Futurist Forge", player: "bob")])
      settle(game)
      expect(perms(game, "Futurist Forge")).to be_empty
    end

    it "Origin of the Avengers: scry 2, then a cheap Hero from hand, then counters on your creatures" do
      game = board(hand: ["Origin of the Avengers", "Guerrilla Gorilla"])
      cast(game, "Origin of the Avengers", { type: "top" }, { type: "top" })
      next_main(game, { type: "choose", object: id(game, "Guerrilla Gorilla", :hand) })
      expect(perms(game, "Guerrilla Gorilla").size).to eq(1)
      next_main(game)
      expect(perm(game, "Guerrilla Gorilla")["counters"]).to eq("+1/+1" => 1)
    end

    it "Monica Rambeau transforms into Photon, who grows the team when you cast a noncreature spell" do
      game = board(hand: ["Monica Rambeau", "Giant Growth"], mine: ["Squirrelanoids"])
      cast(game, "Monica Rambeau")
      game.state.object(id(game, "Monica Rambeau")).controlled_since = 0
      activate(game, "Monica Rambeau")
      expect(pt(game, "Photon, Living Light")).to eq([4, 4])
      cast(game, "Giant Growth", target(game, "Squirrelanoids", "alice"))
      expect([perm(game, "Squirrelanoids")["counters"], perm(game, "Photon, Living Light")["counters"]]).to eq([{ "+1/+1" => 1 }, nil])
    end
  end

  describe "random DeckBuilder decks from the pool" do
    it "plays full games with the rules monitor, invariants and export/import round-trips" do
      builder = Enjine::DeckBuilder.new(cards)
      [[2, 4], [1, 7], [3, 9]].each do |colors, seed|
        decks = [builder.build(colors: colors, seed: seed), builder.build(colors: colors, seed: seed + 1)]
        setup = Enjine::Setup.new(*decks.each_with_index.map { |deck, i| Enjine::Player.new(name: "p#{i}", deck: deck) })
        result = Enjine::Fuzz.run(setup, games: 2, seed: seed * 100, roundtrip_every: 97)
        expect(result.outcomes.values.sum).to eq(2)
      end
    end
  end
end
