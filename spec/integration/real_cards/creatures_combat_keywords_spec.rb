# frozen_string_literal: true

# Real Standard cards (fdn, dft, tdm) written in the card DSL (spec/fixtures/cards/real/creatures_combat_keywords.json):
# each one is cast, played or activated and its effect checked.
RSpec.describe "Real cards: creatures, combat and keywords" do
  let(:pool) { CardFixtures.real("creatures_combat_keywords") }
  let(:catalog) { Enjine::Catalog.from_definitions(pool) }

  def engine(game) = game.instance_variable_get(:@engine)
  def chars(game, card) = engine(game).chars(id(game, card))
  def life(game, name = "alice") = game.state.players[game.names.index(name)].life
  def names(game, player, zone) = ids_in(game, player, zone).map { game.state.object(it).card }
  def on_battlefield(game) = game.state.battlefield.map { engine(game).chars(it).name }
  def counters(game, card) = game.state.object(id(game, card)).counters
  def option(game, type) = game.legal_options.find { it[:type] == type } || raise("no #{type} in #{game.legal_options}")

  # The id of a card or token by name: on the battlefield, else in a hand, a graveyard or on the stack.
  def id(game, card)
    all = game.state.battlefield + game.state.players.flat_map { it.hand + it.graveyard } + game.state.stack
    all.find { engine(game).chars(it).name == card } or raise "no #{card}"
  end

  # The card in the hand (else the graveyard) of the player who is deciding.
  def own(game, card)
    player = game.state.players[game.names.index(game.pending_decision.player)]
    (player.hand + player.graveyard).find { engine(game).chars(it).name == card } or raise "no #{card} for #{player.name}"
  end

  # Alice is active in her precombat main phase; each side lists its zones and attributes
  # (`mana_pool`, `life`, `speed`). A battlefield entry is a name or [name, options].
  def play(step: :precombat_main, active: "alice", alice: {}, bob: {})
    build_game(catalog) do
      turn 3, active: active, step: step
      { "alice" => alice, "bob" => bob }.each do |name, side|
        player(name, **side.slice(:mana_pool, :life, :speed)) do
          side.fetch(:hand, []).each { hand it }
          side.fetch(:graveyard, []).each { graveyard it }
          side.fetch(:battlefield, []).each { |card, opts| battlefield card, **(opts || {}) }
          library "Forest", count: 10
        end
      end
    end
  end

  def pay_all(game)
    while game.pending_decision&.kind == "pay_cost"
      options = game.legal_options
      game.submit(options.find { it[:type] == "pay_mana" } || options.find { it[:type] == "activate_mana" })
    end
  end

  # Casts a card from hand (or with `via`), choosing `mode` and targets (ids or "player:<name>"), then pays.
  def cast(game, card, *targets, via: nil, mode: nil, kick: nil)
    game.submit({ type: "cast", object: own(game, card), via: via }.compact)
    game.submit(type: kick ? "kick" : "no_kick") unless kick.nil?
    game.submit(type: "mode", mode: mode) if mode
    targets.each { game.submit(type: "target", target: it) }
    pay_all(game)
  end

  def activate(game, card, ability, *targets)
    game.submit(type: "activate", object: id(game, card), ability: ability)
    targets.each { game.submit(type: "target", target: it) }
    pay_all(game)
  end

  def resolve(game)
    game.submit(type: "pass") until game.state.stack.empty? || game.pending_decision.kind != "priority"
  end

  def cast_and_resolve(game, card, *targets, **)
    cast(game, card, *targets, **)
    resolve(game)
  end

  # Passes to declare attackers and attacks bob with each card; attack triggers wait on the stack.
  def attack(game, *cards)
    game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
    ids = cards.map { id(game, it) }
    ids.each { game.submit(type: "attack", object: it, target: "player:bob") }
    game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
    ids
  end

  # Bob declares the blocks ({blocker => attacker}), then priority passes until combat ends.
  def block_and_deal(game, blocks = {})
    until game.step == :end_of_combat
      next game.submit(type: "pass") unless game.pending_decision.kind == "declare_blockers"

      blocks.each { |blocker, attacker| game.submit(type: "block", object: id(game, blocker), attacker: id(game, attacker)) }
      blocks = {}
      game.submit(type: "done") if game.pending_decision.kind == "declare_blockers"
    end
  end

  it "every card validates and carries its printing" do
    expect(pool.size).to be >= 100
    expect(pool.map { Enjine::CardDefinition.from_h(it) }).to all(have_attributes(printing: be_a(Hash)))
  end

  describe "evergreen keywords in combat (CR 702)" do
    it "a creature with haste attacks the turn it's cast (CR 702.10b)" do
      game = play(alice: { hand: ["Brazen Scourge"], mana_pool: { R: 3 } })
      cast_and_resolve(game, "Brazen Scourge")
      attack(game, "Brazen Scourge")
      block_and_deal(game)
      expect(life(game, "bob")).to eq(17)
    end

    it "deathtouch destroys its blocker and lifelink gains its damage (CR 702.2b, 702.15b)" do
      game = play(alice: { battlefield: ["Vampire Nighthawk"] }, bob: { battlefield: ["Thornweald Archer"] })
      attack(game, "Vampire Nighthawk")
      block_and_deal(game, "Thornweald Archer" => "Vampire Nighthawk") # reach blocks a flyer; both have deathtouch
      expect(on_battlefield(game)).not_to include("Vampire Nighthawk", "Thornweald Archer")
      expect(life(game)).to eq(22)
    end

    it "double strike with trample deals damage twice, and vigilance leaves it untapped (CR 702.4b, 702.19b, 702.20b)" do
      game = play(alice: { battlefield: ["Swiftblade Vindicator"] })
      attack(game, "Swiftblade Vindicator")
      block_and_deal(game)
      expect(life(game, "bob")).to eq(18)
      expect(game.state.object(id(game, "Swiftblade Vindicator")).tapped).to be(false)
    end

    it "prowess pumps a double striker when a noncreature spell is cast (CR 702.108a)" do
      game = play(alice: { battlefield: ["Jeskai Brushmaster", "Forest"], hand: ["Giant Growth"] })
      attack(game, "Jeskai Brushmaster")
      cast_and_resolve(game, "Giant Growth", id(game, "Jeskai Brushmaster"))
      expect(chars(game, "Jeskai Brushmaster")).to have_attributes(power: 6, toughness: 8)
      block_and_deal(game)
      expect(life(game, "bob")).to eq(8)
    end

    it "first strike during your turn kills a blocker before it deals damage (CR 702.7b)" do
      game = play(alice: { battlefield: ["Bearer of Glory"] }, bob: { battlefield: ["Fanatical Firebrand"] })
      expect(chars(game, "Bearer of Glory").keyword?(:first_strike)).to be(true)
      attack(game, "Bearer of Glory")
      block_and_deal(game, "Fanatical Firebrand" => "Bearer of Glory")
      expect(on_battlefield(game)).to include("Bearer of Glory")
      expect(on_battlefield(game)).not_to include("Fanatical Firebrand")
      theirs = play(active: "bob", alice: { battlefield: ["Bearer of Glory"] })
      expect(chars(theirs, "Bearer of Glory").keyword?(:first_strike)).to be(false)
    end

    it "menace can't be blocked by one creature (CR 702.111b)" do
      game = play(alice: { battlefield: ["Sandskitter Outrider"] }, bob: { battlefield: ["Thornweald Archer"] })
      attack(game, "Sandskitter Outrider")
      game.submit(type: "pass") until game.pending_decision.kind == "declare_blockers"
      game.submit(type: "block", object: id(game, "Thornweald Archer"), attacker: id(game, "Sandskitter Outrider"))
      expect(game.legal_options).not_to include(type: "done")
    end
  end

  describe "creatures that enter or leave" do
    it "makes two 3/3 Knight tokens as it enters (CR 111.1)" do
      game = play(alice: { hand: ["Guarded Heir"], mana_pool: { W: 6 } })
      cast_and_resolve(game, "Guarded Heir")
      resolve(game)
      expect(on_battlefield(game).count("Knight")).to eq(2)
      expect(game.view_for(:observer)["battlefield"].find { it["name"] == "Knight" }).to include("power" => 3, "toughness" => 3)
    end

    it "puts a +1/+1 counter on each of up to two other creatures you control (CR 115.3)" do
      game = play(alice: { hand: ["Felidar Savior"], battlefield: ["Brazen Scourge", "Thornweald Archer"], mana_pool: { W: 4 } })
      cast_and_resolve(game, "Felidar Savior")
      game.submit(type: "count", count: 2) if game.pending_decision.kind == "choose_target_count"
      game.submit(type: "target", target: id(game, "Brazen Scourge"))
      game.submit(type: "target", target: id(game, "Thornweald Archer"))
      resolve(game)
      expect([counters(game, "Brazen Scourge"), counters(game, "Thornweald Archer")]).to all(eq("+1/+1" => 1))
      expect(chars(game, "Felidar Savior").keyword?(:lifelink)).to be(true)
    end

    it "flash: cast in the opponent's turn, it exiles a card from a graveyard (CR 702.8a)" do
      game = play(active: "bob", alice: { hand: ["Ambush Wolf"], battlefield: %w[Forest Forest Forest] },
                  bob: { graveyard: ["Stab"] })
      game.submit(type: "pass") # bob passes priority to alice
      cast_and_resolve(game, "Ambush Wolf")
      game.submit(type: "target", target: id(game, "Stab"))
      resolve(game)
      expect(names(game, "bob", :graveyard)).to be_empty
      expect(on_battlefield(game)).to include("Ambush Wolf")
    end

    it "chooses one mode of its enters trigger (CR 700.2)" do
      game = play(alice: { hand: ["Apothecary Stomper"], mana_pool: { G: 6 } })
      cast_and_resolve(game, "Apothecary Stomper")
      game.submit(type: "mode", mode: 1)
      resolve(game)
      expect(life(game)).to eq(24)
      game = play(alice: { hand: ["Apothecary Stomper"], battlefield: ["Thornweald Archer"], mana_pool: { G: 6 } })
      cast_and_resolve(game, "Apothecary Stomper")
      game.submit(type: "mode", mode: 0)
      game.submit(type: "target", target: id(game, "Thornweald Archer"))
      resolve(game)
      expect(counters(game, "Thornweald Archer")).to eq("+1/+1" => 2)
    end

    it "gets +1/+0 whenever another creature you control enters" do
      game = play(alice: { hand: ["Brazen Scourge"], battlefield: ["Beast-Kin Ranger"], mana_pool: { R: 3 } })
      cast_and_resolve(game, "Brazen Scourge")
      resolve(game)
      expect(chars(game, "Beast-Kin Ranger")).to have_attributes(power: 4, toughness: 3)
    end

    it "landfall makes a 1/1 Elf Warrior token" do
      game = play(alice: { hand: ["Forest"], battlefield: ["Elfsworn Giant"] })
      game.submit(type: "play_land", object: id(game, "Forest"))
      resolve(game)
      expect(on_battlefield(game)).to include("Elf Warrior")
    end

    it "makes a Treasure as it enters" do
      game = play(alice: { hand: ["Meticulous Artisan"], mana_pool: { R: 4 } })
      cast_and_resolve(game, "Meticulous Artisan")
      resolve(game)
      expect(on_battlefield(game)).to include("Treasure")
    end

    it "gives every other creature -2/-2 as it enters, then cycles from hand (CR 702.29a)" do
      game = play(alice: { hand: ["Shefet Archfiend"], battlefield: ["Dusyut Earthcarver"], mana_pool: { B: 7 } },
                  bob: { battlefield: ["Fanatical Firebrand"] })
      cast_and_resolve(game, "Shefet Archfiend")
      resolve(game)
      expect(on_battlefield(game)).not_to include("Fanatical Firebrand")
      expect(chars(game, "Dusyut Earthcarver")).to have_attributes(power: 2, toughness: 2)
      expect(chars(game, "Shefet Archfiend")).to have_attributes(power: 5, toughness: 5)
    end

    it "a kicked creature returns a creature card from your graveyard (CR 702.33d)" do
      game = play(alice: { hand: ["Nullpriest of Oblivion"], graveyard: ["Vampire Nighthawk"], mana_pool: { B: 6 } })
      cast(game, "Nullpriest of Oblivion", kick: true)
      resolve(game)
      game.submit(type: "target", target: id(game, "Vampire Nighthawk"))
      resolve(game)
      expect(on_battlefield(game)).to include("Vampire Nighthawk", "Nullpriest of Oblivion")
      expect(chars(game, "Nullpriest of Oblivion").keyword?(:menace)).to be(true)
    end

    it "a dying creature with defender leaves a Treasure; the destroying spell hits creatures or planeswalkers" do
      game = play(alice: { hand: ["Hero's Downfall"], mana_pool: { B: 3 } }, bob: { battlefield: ["Gleaming Barrier"] })
      expect(chars(game, "Gleaming Barrier").keyword?(:defender)).to be(true)
      cast_and_resolve(game, "Hero's Downfall", id(game, "Gleaming Barrier"))
      resolve(game)
      expect(names(game, "bob", :graveyard)).to eq(["gleaming_barrier"])
      expect(game.state.object(id(game, "Treasure")).controller).to eq(1)
    end

    it "a dying creature leaves a 2/2 Zombie Druid; renew exiles it from the graveyard for counters (sorcery speed)" do
      game = play(alice: { hand: ["Stab"], battlefield: ["Thornweald Archer"], graveyard: ["Adorned Crocodile"], mana_pool: { B: 2 } },
                  bob: { battlefield: ["Shock Brigade"] })
      activate(game, "Adorned Crocodile", "printed:1", id(game, "Thornweald Archer"))
      resolve(game)
      expect(counters(game, "Thornweald Archer")).to eq("+1/+1" => 1)
      expect(names(game, "alice", :graveyard)).to be_empty
    end
  end

  describe "endure (CR 701.63)" do
    [["Fortress Kin-Guard", 1, { W: 2 }], ["Kin-Tree Nurturer", 1, { B: 3 }], ["Sandskitter Outrider", 2, { B: 4 }],
     ["Dusyut Earthcarver", 3, { G: 6 }]].each do |card, n, mana|
      it "#{card} endures #{n} as it enters: counters, or a #{n}/#{n} Spirit" do
        game = play(alice: { hand: [card], mana_pool: mana })
        cast_and_resolve(game, card)
        resolve(game)
        game.submit(type: "counters", object: id(game, card))
        expect(counters(game, card)).to eq("+1/+1" => n)
        game = play(alice: { hand: [card], mana_pool: mana })
        cast_and_resolve(game, card)
        resolve(game)
        game.submit(type: "spirit")
        expect(chars(game, "Spirit")).to have_attributes(power: n, toughness: n, colors: [:W])
      end
    end

    it "endures 2 whenever another nontoken creature you control dies" do
      game = play(alice: { battlefield: ["Anafenza, Unyielding Lineage", "Fanatical Firebrand"] })
      expect(chars(game, "Anafenza, Unyielding Lineage").keyword?(:first_strike)).to be(true)
      activate(game, "Fanatical Firebrand", "printed:0", "player:bob")
      resolve(game)
      game.submit(type: "counters", object: id(game, "Anafenza, Unyielding Lineage"))
      resolve(game)
      expect(counters(game, "Anafenza, Unyielding Lineage")).to eq("+1/+1" => 2)
      expect(life(game, "bob")).to eq(19)
    end

    it "endures 2 as it enters and whenever it attacks" do
      game = play(alice: { battlefield: ["Inspirited Vanguard"] })
      attack(game, "Inspirited Vanguard")
      resolve(game)
      game.submit(type: "spirit")
      expect(on_battlefield(game)).to include("Spirit")
    end

    it "loses 1 life and endures 1 whenever it attacks" do
      game = play(alice: { battlefield: ["Sinkhole Surveyor"] })
      attack(game, "Sinkhole Surveyor")
      resolve(game)
      game.submit(type: "counters", object: id(game, "Sinkhole Surveyor"))
      expect([life(game), counters(game, "Sinkhole Surveyor")]).to eq([19, { "+1/+1" => 1 }])
    end

    it "may pay {1}{W} as it attacks to endure 1 (CR 118.12)" do
      game = play(alice: { battlefield: ["Descendant of Storms", "Plains", "Plains"] })
      attack(game, "Descendant of Storms")
      resolve(game)
      game.submit(type: "pay")
      pay_all(game)
      game.submit(type: "counters", object: id(game, "Descendant of Storms"))
      expect(counters(game, "Descendant of Storms")).to eq("+1/+1" => 1)
    end
  end

  describe "activated abilities of creatures" do
    it "sacrifices itself to deal its power, as it last existed, to a creature (CR 608.2h)" do
      game = play(alice: { battlefield: ["Heartfire Immolator", "Forest", "Mountain"], hand: ["Giant Growth"] },
                  bob: { battlefield: ["Dusyut Earthcarver"] })
      cast_and_resolve(game, "Giant Growth", id(game, "Heartfire Immolator"))
      expect(chars(game, "Heartfire Immolator").power).to eq(6) # +3 and prowess +1
      activate(game, "Heartfire Immolator", "printed:0", id(game, "Dusyut Earthcarver"))
      resolve(game)
      expect(names(game, "bob", :graveyard)).to eq(["dusyut_earthcarver"])
    end

    it "sacrifices itself to destroy an artifact or enchantment" do
      game = play(alice: { battlefield: ["Cathar Commando"], mana_pool: { W: 1 } }, bob: { battlefield: ["Swiftfoot Boots"] })
      activate(game, "Cathar Commando", "printed:0", id(game, "Swiftfoot Boots"))
      resolve(game)
      expect(names(game, "bob", :graveyard)).to eq(["swiftfoot_boots"])
      expect(names(game, "alice", :graveyard)).to eq(["cathar_commando"])
    end

    it "taps and sacrifices itself to destroy another artifact, only as a sorcery" do
      game = play(alice: { battlefield: ["Aetherjacket"], mana_pool: { C: 2 } }, bob: { battlefield: ["Juggernaut"] })
      expect(chars(game, "Aetherjacket").keyword?(:vigilance)).to be(true)
      activate(game, "Aetherjacket", "printed:0", id(game, "Juggernaut"))
      resolve(game)
      expect(names(game, "bob", :graveyard)).to eq(["juggernaut"])
    end

    it "grants trample for {G}; its exhaust ability works only once (CR 702.177a)" do
      game = play(alice: { battlefield: ["Greenbelt Guardian"], mana_pool: { G: 5 } })
      activate(game, "Greenbelt Guardian", "printed:0", id(game, "Greenbelt Guardian"))
      resolve(game)
      expect(chars(game, "Greenbelt Guardian").keyword?(:trample)).to be(true)
      activate(game, "Greenbelt Guardian", "printed:1")
      resolve(game)
      expect(counters(game, "Greenbelt Guardian")).to eq("+1/+1" => 3)
      expect(game.legal_options).not_to include(type: "activate", object: id(game, "Greenbelt Guardian"), ability: "printed:1")
    end

    it "pumps every creature you control" do
      game = play(alice: { battlefield: ["Bearer of Glory", "Thornweald Archer"], mana_pool: { W: 5 } })
      activate(game, "Bearer of Glory", "printed:1")
      resolve(game)
      expect([chars(game, "Bearer of Glory"), chars(game, "Thornweald Archer")].map { [it.power, it.toughness] }).to eq([[3, 2], [3, 2]])
    end
  end

  describe "exhaust (CR 702.177)" do
    it "puts counters on itself; haste lets it attack at once" do
      game = play(alice: { hand: ["Prowcatcher Specialist"], mana_pool: { R: 6 } })
      cast_and_resolve(game, "Prowcatcher Specialist")
      activate(game, "Prowcatcher Specialist", "printed:0")
      resolve(game)
      expect(chars(game, "Prowcatcher Specialist")).to have_attributes(power: 4, toughness: 3)
    end

    it "a counter and double strike until end of turn" do
      game = play(alice: { battlefield: ["Pacesetter Paragon"], mana_pool: { R: 3 } })
      activate(game, "Pacesetter Paragon", "printed:0")
      resolve(game)
      expect(chars(game, "Pacesetter Paragon")).to have_attributes(power: 3, toughness: 4)
      expect(chars(game, "Pacesetter Paragon").keyword?(:double_strike)).to be(true)
    end

    [["Camera Launcher", { C: 3 }, "Thopter", [1, 1]],
     ["Stampeding Scurryfoot", { G: 4 }, "Elephant", [3, 3]]].each do |card, mana, token, pt|
      it "#{card}: a counter and a #{token} token" do
        game = play(alice: { battlefield: [card], mana_pool: mana })
        activate(game, card, "printed:0")
        resolve(game)
        expect(counters(game, card)).to eq("+1/+1" => 1)
        expect([chars(game, token).power, chars(game, token).toughness]).to eq(pt)
      end
    end

    it "returns from the graveyard to the battlefield whenever you activate an exhaust ability (CR 113.6k)" do
      game = play(alice: { battlefield: ["Prowcatcher Specialist"], graveyard: ["Afterburner Expert"], mana_pool: { R: 4 } })
      activate(game, "Prowcatcher Specialist", "printed:0")
      resolve(game)
      expect(on_battlefield(game)).to include("Afterburner Expert")
      game = play(alice: { battlefield: ["Afterburner Expert"], mana_pool: { G: 4 } })
      activate(game, "Afterburner Expert", "printed:0")
      resolve(game)
      expect(chars(game, "Afterburner Expert")).to have_attributes(power: 6, toughness: 4)
    end
  end

  describe "start your engines! and max speed (CR 702.178, 702.179)" do
    it "a creature with start your engines! gives you speed 1" do
      game = play(alice: { hand: ["Goblin Surveyor"], mana_pool: { R: 3 } })
      cast_and_resolve(game, "Goblin Surveyor")
      expect(engine(game).speed(0)).to eq(1)
      expect(chars(game, "Goblin Surveyor").keyword?(:trample)).to be(true)
    end

    it "at max speed, exiles itself from your graveyard to draw a card" do
      game = play(alice: { graveyard: ["Goblin Surveyor"], speed: 4, mana_pool: { C: 3 } })
      activate(game, "Goblin Surveyor", "printed:0:0")
      resolve(game)
      expect(ids_in(game, "alice", :hand).size).to eq(1)
      expect(names(game, "alice", :graveyard)).to be_empty
    end

    it "keywords and static abilities apply only at max speed" do
      slow = play(alice: { battlefield: ["Streaking Oilgorger", "Walking Sarcophagus", "Swiftwing Assailant"], speed: 3 })
      expect(chars(slow, "Streaking Oilgorger").keyword?(:lifelink)).to be(false)
      expect(chars(slow, "Walking Sarcophagus")).to have_attributes(power: 2, toughness: 1)
      fast = play(alice: { battlefield: ["Streaking Oilgorger", "Walking Sarcophagus", "Swiftwing Assailant"], speed: 4 })
      expect(chars(fast, "Streaking Oilgorger").keyword?(:lifelink)).to be(true)
      expect(chars(fast, "Walking Sarcophagus")).to have_attributes(power: 3, toughness: 3)
      expect(chars(fast, "Swiftwing Assailant")).to have_attributes(power: 3, toughness: 4)
      expect(chars(fast, "Swiftwing Assailant").keyword?(:vigilance)).to be(true)
    end

    it "at max speed a creature and a land tap for two mana" do
      game = play(alice: { battlefield: ["Endrider Catalyzer", "Muraganda Raceway"], speed: 4 })
      game.submit(type: "activate_mana", object: id(game, "Endrider Catalyzer"), ability: "printed:0:0")
      game.submit(type: "activate_mana", object: id(game, "Muraganda Raceway"), ability: "printed:1:0")
      expect(game.state.players[0].mana_pool).to include(R: 2, C: 2)
      slow = play(alice: { battlefield: ["Endrider Catalyzer", "Muraganda Raceway"], speed: 3 })
      expect(slow.legal_options.filter_map { it[:ability] }).to eq(["printed:0"]) # only the Raceway's {C}
    end

    it "at max speed a land gives a creature haste" do
      game = play(alice: { battlefield: ["Amonkhet Raceway"], hand: ["Shock Brigade"], speed: 4, mana_pool: { R: 2 } })
      cast_and_resolve(game, "Shock Brigade")
      activate(game, "Amonkhet Raceway", "printed:1:0", id(game, "Shock Brigade"))
      resolve(game)
      expect(chars(game, "Shock Brigade").keyword?(:haste)).to be(true)
    end

    it "at max speed an Aura is cast from your graveyard" do
      game = play(alice: { graveyard: ["Lightwheel Enhancements"], battlefield: ["Thornweald Archer"], speed: 4, mana_pool: { W: 1 } })
      game.submit(type: "cast", object: id(game, "Lightwheel Enhancements"), via: option(game, "cast")[:via])
      game.submit(type: "target", target: id(game, "Thornweald Archer"))
      pay_all(game)
      resolve(game)
      expect(chars(game, "Thornweald Archer")).to have_attributes(power: 3, toughness: 2)
      expect(chars(game, "Thornweald Archer").keyword?(:vigilance)).to be(true)
    end
  end

  describe "mobilize (CR 702.181)" do
    [["Dalkovan Packbeasts", 3, 3], ["Dragonback Lancer", 1, 4], ["Shock Brigade", 1, 2]].each do |card, tokens, damage|
      it "#{card} attacks with #{tokens} Warrior token(s), sacrificed at the next end step" do
        game = play(alice: { battlefield: [card] })
        attack(game, card)
        resolve(game)
        expect(on_battlefield(game).count("Warrior")).to eq(tokens)
        block_and_deal(game)
        expect(life(game, "bob")).to eq(20 - damage)
        skip_to(game, :end)
        resolve(game)
        expect(on_battlefield(game)).not_to include("Warrior")
      end
    end

    it "mobilize X counts the creature cards in your graveyard" do
      game = play(alice: { battlefield: ["Avenger of the Fallen"], graveyard: ["Brazen Scourge", "Juggernaut", "Stab"] })
      attack(game, "Avenger of the Fallen")
      resolve(game)
      expect(on_battlefield(game).count("Warrior")).to eq(2)
    end
  end

  describe "attack triggers and lords" do
    it "other Elves get +1/+1; attacking gains 1 life per attacking Elf" do
      game = play(alice: { battlefield: ["Dwynen, Gilt-Leaf Daen", "Thornweald Archer"] })
      expect(chars(game, "Thornweald Archer")).to have_attributes(power: 3, toughness: 2)
      expect(chars(game, "Dwynen, Gilt-Leaf Daen")).to have_attributes(power: 3, toughness: 4)
      attack(game, "Dwynen, Gilt-Leaf Daen", "Thornweald Archer")
      resolve(game)
      expect(life(game)).to eq(22)
    end

    it "attacking pumps the other creatures you control" do
      game = play(alice: { battlefield: ["Syr Alin, the Lion's Claw", "Thornweald Archer"] })
      attack(game, "Syr Alin, the Lion's Claw")
      resolve(game)
      expect(chars(game, "Thornweald Archer")).to have_attributes(power: 3, toughness: 2)
      expect(chars(game, "Syr Alin, the Lion's Claw")).to have_attributes(power: 4, toughness: 4)
    end

    it "whenever you attack, a creature gets +X/+X for the attacking creatures" do
      game = play(alice: { battlefield: ["Marshal of the Lost", "Thornweald Archer", "Brazen Scourge"] })
      attack(game, "Thornweald Archer", "Brazen Scourge")
      game.submit(type: "target", target: id(game, "Thornweald Archer"))
      resolve(game)
      expect(chars(game, "Thornweald Archer")).to have_attributes(power: 4, toughness: 3)
    end

    it "attacks each combat and can't be blocked by Walls (CR 508.1d, 509.1b)" do
      game = play(alice: { battlefield: ["Juggernaut"] }, bob: { battlefield: ["Gleaming Barrier", "Thornweald Archer"] })
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      expect(game.legal_options).not_to include(type: "done")
      attack(game, "Juggernaut")
      game.submit(type: "pass") until game.pending_decision.kind == "declare_blockers"
      blockers = game.legal_options.filter_map { it[:object] if it[:type] == "block" }
      expect(blockers).to eq([id(game, "Thornweald Archer")])
    end
  end

  describe "Vehicles and crew (CR 702.122)" do
    def crew(game, vehicle, *creatures)
      game.submit(type: "activate", object: id(game, vehicle), ability: option(game, "activate")[:ability])
      creatures.each { game.submit(type: "cost", object: id(game, it)) }
      game.submit(type: "done") if game.pending_decision.kind == "choose_cost"
      resolve(game)
    end

    it "crewed, it's a flying, vigilant artifact creature that attacks" do
      game = play(alice: { battlefield: ["Air Response Unit", "Fanatical Firebrand"] })
      expect(chars(game, "Air Response Unit").creature?).to be(false)
      crew(game, "Air Response Unit", "Fanatical Firebrand")
      expect(chars(game, "Air Response Unit")).to have_attributes(types: %i[artifact creature], power: 3, toughness: 3)
      attack(game, "Air Response Unit")
      block_and_deal(game)
      expect(life(game, "bob")).to eq(17)
      expect(game.state.object(id(game, "Air Response Unit")).tapped).to be(false)
    end

    it "is an artifact creature during the opponent's turn only" do
      expect(chars(play(alice: { battlefield: ["Midnight Mangler"] }), "Midnight Mangler").creature?).to be(false)
      theirs = play(active: "bob", alice: { battlefield: ["Midnight Mangler"] })
      expect(chars(theirs, "Midnight Mangler")).to have_attributes(power: 3, toughness: 3, types: %i[artifact creature])
    end

    it "draws two as it enters; another drains 3; another gains 2 and taps for any color" do
      game = play(alice: { hand: ["Hulldrifter", "Debris Beetle", "Veloheart Bike"], mana_pool: { U: 5, B: 2, G: 5 } })
      cast_and_resolve(game, "Hulldrifter")
      resolve(game)
      expect(ids_in(game, "alice", :hand).size).to eq(4)
      cast_and_resolve(game, "Debris Beetle")
      resolve(game)
      expect([life(game), life(game, "bob")]).to eq([23, 17])
      cast_and_resolve(game, "Veloheart Bike")
      resolve(game)
      expect(life(game)).to eq(25)
      game.submit(type: "activate_mana", object: id(game, "Veloheart Bike"), ability: "printed:1", mana: "{U}")
      expect(game.state.players[0].mana_pool[:U]).to eq(1)
    end

    it "cycles from hand to draw a card (CR 702.29a)" do
      game = play(alice: { hand: ["Skybox Ferry"], mana_pool: { C: 2 } })
      activate(game, "Skybox Ferry", "printed:1")
      resolve(game)
      expect(names(game, "alice", :graveyard)).to eq(["skybox_ferry"])
      expect(ids_in(game, "alice", :hand).size).to eq(1)
    end

    it "whenever you attack it loots; a discard grows a creature that counts discards" do
      game = play(alice: { battlefield: ["Boosted Sloop", "Marauding Mako", "Thornweald Archer"], hand: ["Stab"] })
      crew(game, "Boosted Sloop", "Thornweald Archer")
      attack(game, "Boosted Sloop")
      resolve(game)
      game.submit(type: "discard", object: id(game, "Stab")) if game.pending_decision.kind == "effect_choice"
      resolve(game)
      expect(names(game, "alice", :graveyard)).to eq(["stab"])
      expect(counters(game, "Marauding Mako")).to eq("+1/+1" => 1)
    end
  end

  describe "combat tricks and removal" do
    def bob_creature(spell, mana, creature = "Dusyut Earthcarver")
      play(alice: { hand: [spell], mana_pool: mana }, bob: { battlefield: [creature] })
    end

    it "+2/+2; -2/-2 kills; +3/+0 and first strike" do
      game = play(alice: { hand: ["Sure Strike", "Stab", "Lightshield Parry"], battlefield: ["Thornweald Archer"],
                           mana_pool: { R: 2, B: 1, W: 1 } }, bob: { battlefield: ["Fanatical Firebrand"] })
      cast_and_resolve(game, "Lightshield Parry", id(game, "Thornweald Archer"))
      expect(chars(game, "Thornweald Archer")).to have_attributes(power: 4, toughness: 3)
      cast_and_resolve(game, "Stab", id(game, "Fanatical Firebrand"))
      cast_and_resolve(game, "Sure Strike", id(game, "Thornweald Archer"))
      expect(chars(game, "Thornweald Archer")).to have_attributes(power: 7, toughness: 3)
      expect(chars(game, "Thornweald Archer").keyword?(:first_strike)).to be(true)
      expect(names(game, "bob", :graveyard)).to eq(["fanatical_firebrand"])
    end

    it "deals 2, or 4 when kicked (CR 702.33d)" do
      game = play(alice: { hand: ["Burst Lightning"], mana_pool: { R: 1 } })
      cast_and_resolve(game, "Burst Lightning", "player:bob", kick: false)
      expect(life(game, "bob")).to eq(18)
      game = play(alice: { hand: ["Burst Lightning"], mana_pool: { R: 5 } })
      cast_and_resolve(game, "Burst Lightning", "player:bob", kick: true)
      expect(life(game, "bob")).to eq(16)
    end

    it "doubles a creature's power, and again with flashback from the graveyard (CR 702.34a)" do
      game = play(alice: { hand: ["Bulk Up"], battlefield: ["Dusyut Earthcarver"], mana_pool: { R: 8 } })
      cast_and_resolve(game, "Bulk Up", id(game, "Dusyut Earthcarver"))
      expect(chars(game, "Dusyut Earthcarver").power).to eq(8)
      cast_and_resolve(game, "Bulk Up", id(game, "Dusyut Earthcarver"), via: "alt:printed:1")
      expect(chars(game, "Dusyut Earthcarver").power).to eq(16)
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["bulk_up"])
    end

    it "deals 3 to an attacking or blocking creature and gains 1 life" do
      game = play(active: "bob", alice: { hand: ["Joust Through"], battlefield: ["Plains"] }, bob: { battlefield: ["Brazen Scourge"] })
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      expect(game.pending_decision.player).to eq("bob")
      game.submit(type: "attack", object: id(game, "Brazen Scourge"), target: "player:alice")
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
      game.submit(type: "pass") # bob passes; alice may respond
      cast_and_resolve(game, "Joust Through", id(game, "Brazen Scourge"))
      expect([names(game, "bob", :graveyard), life(game)]).to eq([["brazen_scourge"], 21])
    end

    it "costs {3} less against a tapped creature (CR 601.2f)" do
      game = play(alice: { hand: ["Luminous Rebuke"], battlefield: %w[Plains Plains] },
                  bob: { battlefield: [["Dusyut Earthcarver", { tapped: true }], "Thornweald Archer"] })
      targets = game.legal_options.select { it[:type] == "cast" }
      expect(targets).not_to be_empty
      cast_and_resolve(game, "Luminous Rebuke", id(game, "Dusyut Earthcarver"))
      expect(names(game, "bob", :graveyard)).to eq(["dusyut_earthcarver"])
    end

    it "either deals 3 to a creature or destroys an artifact (CR 700.2)" do
      game = play(alice: { hand: %w[Abrade Abrade], mana_pool: { R: 4 } },
                  bob: { battlefield: ["Thornweald Archer", "Swiftfoot Boots"] })
      cast_and_resolve(game, "Abrade", id(game, "Thornweald Archer"), mode: 0)
      cast_and_resolve(game, "Abrade", id(game, "Swiftfoot Boots"), mode: 1)
      expect(names(game, "bob", :graveyard)).to contain_exactly("thornweald_archer", "swiftfoot_boots")
    end

    it "counters a creature spell, not another spell (CR 701.6a)" do
      game = play(active: "bob", alice: { hand: ["Essence Scatter"], battlefield: %w[Island Island] },
                  bob: { hand: ["Brazen Scourge"], mana_pool: { R: 3 } })
      cast(game, "Brazen Scourge")
      game.submit(type: "pass")
      cast_and_resolve(game, "Essence Scatter", id(game, "Brazen Scourge"))
      expect(names(game, "bob", :graveyard)).to eq(["brazen_scourge"])
    end

    it "your creature deals damage equal to its power to theirs, after a counter on it (CR 701.14 bite)" do
      game = play(alice: { hand: ["Bite Down", "Knockout Maneuver"], battlefield: ["Thornweald Archer"], mana_pool: { G: 5 } },
                  bob: { battlefield: ["Kin-Tree Nurturer", "Shock Brigade"] })
      cast_and_resolve(game, "Bite Down", id(game, "Thornweald Archer"), id(game, "Kin-Tree Nurturer"))
      cast_and_resolve(game, "Knockout Maneuver", id(game, "Thornweald Archer"), id(game, "Shock Brigade"))
      expect(names(game, "bob", :graveyard)).to contain_exactly("kin_tree_nurturer", "shock_brigade")
      expect(on_battlefield(game)).to include("Thornweald Archer") # nothing is dealt back
    end

    it "2 damage to each creature without flying, then to each creature (cycling also offered)" do
      game = play(alice: { hand: ["Seismic Rupture", "Fuel the Flames"], battlefield: ["Vampire Nighthawk"], mana_pool: { R: 6 } },
                  bob: { battlefield: ["Thornweald Archer"] })
      cast_and_resolve(game, "Seismic Rupture")
      expect(on_battlefield(game)).to eq(["Vampire Nighthawk"])
      expect(game.legal_options).to include(type: "activate", object: id(game, "Fuel the Flames"), ability: "printed:1")
      cast_and_resolve(game, "Fuel the Flames")
      expect(on_battlefield(game)).to eq(["Vampire Nighthawk"])
      expect(game.state.object(id(game, "Vampire Nighthawk")).damage).to eq(2)
    end

    it "your creatures get +3/+3 and trample" do
      game = play(alice: { hand: ["Overrun"], battlefield: ["Thornweald Archer"], mana_pool: { G: 5 } })
      cast_and_resolve(game, "Overrun")
      expect(chars(game, "Thornweald Archer")).to have_attributes(power: 5, toughness: 4)
      expect(chars(game, "Thornweald Archer").keyword?(:trample)).to be(true)
    end

    it "destroys a creature with toughness 4 or greater only" do
      game = play(alice: { hand: ["Gallant Strike"], mana_pool: { W: 2 } },
                  bob: { battlefield: ["Dusyut Earthcarver", "Thornweald Archer"] })
      game.submit(type: "cast", object: id(game, "Gallant Strike"))
      expect(game.legal_options.filter_map { it[:target] }).to eq([id(game, "Dusyut Earthcarver")])
      game.submit(type: "target", target: id(game, "Dusyut Earthcarver"))
      pay_all(game)
      resolve(game)
      expect(names(game, "bob", :graveyard)).to eq(["dusyut_earthcarver"])
    end

    it "taps a Vehicle and puts three stun counters on it (CR 122.1d)" do
      game = play(alice: { hand: ["Stall Out"], mana_pool: { U: 2 } }, bob: { battlefield: ["Air Response Unit"] })
      cast_and_resolve(game, "Stall Out", id(game, "Air Response Unit"))
      unit = game.state.object(id(game, "Air Response Unit"))
      expect([unit.tapped, unit.counters]).to eq([true, { "stun" => 3 }])
    end

    it "deathtouch and indestructible for your creature" do
      game = play(alice: { hand: ["Alesha's Legacy"], battlefield: ["Brazen Scourge"], mana_pool: { B: 2 } })
      cast_and_resolve(game, "Alesha's Legacy", id(game, "Brazen Scourge"))
      expect(%i[deathtouch indestructible].map { chars(game, "Brazen Scourge").keyword?(it) }).to eq([true, true])
    end

    it "+3/+0 and haste, then again by harmonize, tapping a creature to pay less (CR 702.180a)" do
      game = play(alice: { hand: ["Wild Ride"], battlefield: ["Dusyut Earthcarver"], mana_pool: { R: 2 } })
      cast_and_resolve(game, "Wild Ride", id(game, "Dusyut Earthcarver"))
      expect(chars(game, "Dusyut Earthcarver").power).to eq(7)
      game.submit(type: "cast", object: id(game, "Wild Ride"), via: "alt:printed:1")
      game.submit(type: "target", target: id(game, "Dusyut Earthcarver")) if game.pending_decision.kind == "choose_target"
      game.submit(type: "cost", object: id(game, "Dusyut Earthcarver"))
      game.submit(type: "target", target: id(game, "Dusyut Earthcarver")) if game.pending_decision.kind == "choose_target"
      pay_all(game)
      resolve(game)
      expect(chars(game, "Dusyut Earthcarver").power).to eq(10)
      expect(chars(game, "Dusyut Earthcarver").keyword?(:haste)).to be(true)
    end

    it "deals 2 to any target; harmonize from the graveyard" do
      game = play(alice: { graveyard: ["Channeled Dragonfire"], mana_pool: { R: 7 } })
      game.submit(type: "cast", object: id(game, "Channeled Dragonfire"), via: "alt:printed:1")
      game.submit(type: "target", target: "player:bob") if game.pending_decision.kind == "choose_target"
      game.submit(type: "cost") if game.pending_decision.kind == "choose_cost"
      game.submit(type: "target", target: "player:bob") if game.pending_decision.kind == "choose_target"
      pay_all(game)
      resolve(game)
      expect(life(game, "bob")).to eq(18)
    end

    it "either +3/+3 or destroys a creature with flying" do
      game = play(alice: { hand: ["Sarkhan's Resolve", "Sarkhan's Resolve"], battlefield: ["Thornweald Archer"], mana_pool: { G: 4 } },
                  bob: { battlefield: ["Vampire Nighthawk"] })
      cast_and_resolve(game, "Sarkhan's Resolve", id(game, "Thornweald Archer"), mode: 0)
      expect(chars(game, "Thornweald Archer").power).to eq(5)
      cast_and_resolve(game, "Sarkhan's Resolve", id(game, "Vampire Nighthawk"), mode: 1)
      expect(names(game, "bob", :graveyard)).to eq(["vampire_nighthawk"])
    end

    it "sacrifices a creature as an additional cost to exile a creature (CR 601.2b)" do
      game = play(alice: { hand: ["Worthy Cost"], battlefield: ["Fanatical Firebrand"], mana_pool: { B: 1 } },
                  bob: { battlefield: ["Dusyut Earthcarver"] })
      game.submit(type: "cast", object: id(game, "Worthy Cost"))
      game.submit(type: "target", target: id(game, "Dusyut Earthcarver"))
      game.submit(type: "cost", object: id(game, "Fanatical Firebrand"))
      pay_all(game)
      resolve(game)
      expect(names(game, "alice", :graveyard)).to contain_exactly("fanatical_firebrand", "worthy_cost")
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["dusyut_earthcarver"])
    end

    it "a +1/+1 counter, flying and indestructible" do
      game = play(alice: { hand: ["Lightfoot Technique"], battlefield: ["Brazen Scourge"], mana_pool: { W: 2 } })
      cast_and_resolve(game, "Lightfoot Technique", id(game, "Brazen Scourge"))
      expect(counters(game, "Brazen Scourge")).to eq("+1/+1" => 1)
      expect(%i[flying indestructible].map { chars(game, "Brazen Scourge").keyword?(it) }).to eq([true, true])
    end
  end

  describe "Equipment and Auras (CR 301.5, 303.4)" do
    def equip(game, equipment, creature)
      game.submit(type: "activate", object: id(game, equipment), ability: option(game, "activate")[:ability])
      game.submit(type: "target", target: id(game, creature))
      pay_all(game)
      resolve(game)
    end

    [["Basilisk Collar", %i[deathtouch lifelink], [2, 1]], ["Swiftfoot Boots", %i[hexproof haste], [2, 1]],
     ["Fireshrieker", %i[double_strike], [2, 1]], ["Goldvein Pick", [], [3, 2]]].each do |equipment, keywords, pt|
      it "#{equipment} gives the equipped creature #{keywords.join(", ").then { it.empty? ? "+1/+1" : it }}" do
        game = play(alice: { battlefield: [equipment, "Thornweald Archer"], mana_pool: { C: 2 } })
        equip(game, equipment, "Thornweald Archer")
        archer = chars(game, "Thornweald Archer")
        expect([archer.power, archer.toughness]).to eq(pt)
        expect(keywords.map { archer.keyword?(it) }).to all(be(true))
      end
    end

    it "makes a Treasure when the equipped creature deals combat damage to a player" do
      game = play(alice: { battlefield: ["Goldvein Pick", "Brazen Scourge"], mana_pool: { C: 1 } })
      equip(game, "Goldvein Pick", "Brazen Scourge")
      attack(game, "Brazen Scourge")
      block_and_deal(game)
      expect(life(game, "bob")).to eq(16)
      expect(on_battlefield(game)).to include("Treasure")
    end

    it "gives +2/+0 and first strike during your turn only" do
      game = play(alice: { battlefield: ["Quick-Draw Katana", "Thornweald Archer"], mana_pool: { C: 2 } })
      equip(game, "Quick-Draw Katana", "Thornweald Archer")
      expect(chars(game, "Thornweald Archer")).to have_attributes(power: 4, toughness: 1)
      skip_to(game, :upkeep, turn: 4)
      expect(chars(game, "Thornweald Archer").power).to eq(2)
    end

    it "+3/+0; draws when the equipped creature attacks with two others" do
      game = play(alice: { battlefield: ["Stormbeacon Blade", "Brazen Scourge", "Thornweald Archer", "Vampire Nighthawk"],
                           mana_pool: { C: 2 } })
      equip(game, "Stormbeacon Blade", "Brazen Scourge")
      expect(chars(game, "Brazen Scourge").power).to eq(6)
      attack(game, "Brazen Scourge", "Thornweald Archer", "Vampire Nighthawk")
      resolve(game)
      expect(ids_in(game, "alice", :hand).size).to eq(1)
    end

    it "an enchanted creature can't attack or block" do
      game = play(alice: { hand: ["Pacifism"], mana_pool: { W: 2 } }, bob: { battlefield: ["Brazen Scourge"] })
      cast_and_resolve(game, "Pacifism", id(game, "Brazen Scourge"))
      expect(%i[cant_attack cant_block].map { chars(game, "Brazen Scourge").keyword?(it) }).to eq([true, true])
    end

    it "flash Auras: double strike; first strike as it enters and +2/+0" do
      game = play(alice: { hand: ["Twinblade Blessing", "Fire-Rim Form"], battlefield: ["Thornweald Archer", "Brazen Scourge"],
                           mana_pool: { W: 3, R: 2 } })
      cast_and_resolve(game, "Twinblade Blessing", id(game, "Thornweald Archer"))
      cast_and_resolve(game, "Fire-Rim Form", id(game, "Brazen Scourge"))
      resolve(game)
      expect(chars(game, "Thornweald Archer").keyword?(:double_strike)).to be(true)
      expect(chars(game, "Brazen Scourge")).to have_attributes(power: 5, toughness: 3)
      expect(chars(game, "Brazen Scourge").keyword?(:first_strike)).to be(true)
    end

    it "+2/+2, trample and lifelink" do
      game = play(alice: { hand: ["Unflinching Courage"], battlefield: ["Thornweald Archer"], mana_pool: { G: 2, W: 1 } })
      cast_and_resolve(game, "Unflinching Courage", id(game, "Thornweald Archer"))
      expect(chars(game, "Thornweald Archer")).to have_attributes(power: 4, toughness: 3)
      expect(%i[trample lifelink].map { chars(game, "Thornweald Archer").keyword?(it) }).to eq([true, true])
    end

    it "taps the creature as it enters; it doesn't untap in its controller's untap step (CR 502.3)" do
      game = play(alice: { hand: ["Starlight Snare"], mana_pool: { U: 3 } }, bob: { battlefield: ["Brazen Scourge"] })
      cast_and_resolve(game, "Starlight Snare", id(game, "Brazen Scourge"))
      resolve(game)
      skip_to(game, :upkeep, turn: 4)
      expect(game.state.object(id(game, "Brazen Scourge")).tapped).to be(true)
    end

    it "+1/+1 and flying, and returns to its owner's hand" do
      game = play(alice: { hand: ["Wingspan Stride"], battlefield: ["Thornweald Archer"], mana_pool: { U: 4 } })
      cast_and_resolve(game, "Wingspan Stride", id(game, "Thornweald Archer"))
      expect(chars(game, "Thornweald Archer")).to have_attributes(power: 3, toughness: 2)
      activate(game, "Wingspan Stride", "printed:2")
      resolve(game)
      expect(names(game, "alice", :hand)).to eq(["wingspan_stride"])
    end

    it "enchants a Vehicle, untapping it, +1/+2 and reach" do
      game = play(alice: { hand: ["Silken Strength"], battlefield: [["Air Response Unit", { tapped: true }]], mana_pool: { G: 2 } })
      cast_and_resolve(game, "Silken Strength", id(game, "Air Response Unit"))
      resolve(game)
      expect(game.state.object(id(game, "Air Response Unit")).tapped).to be(false)
      expect(engine(game).chars(id(game, "Air Response Unit")).keyword?(:reach)).to be(true)
    end
  end

  describe "enchantments and a planeswalker" do
    it "your creatures get +1/+1" do
      game = play(alice: { hand: ["Anthem of Champions"], battlefield: ["Thornweald Archer"], mana_pool: { G: 1, W: 1 } })
      cast_and_resolve(game, "Anthem of Champions")
      expect(chars(game, "Thornweald Archer")).to have_attributes(power: 3, toughness: 2)
    end

    it "+1/+0, and an attacking Warrior token whenever you attack, sacrificed at the end step" do
      game = play(alice: { battlefield: ["War Effort", "Thornweald Archer"] })
      attack(game, "Thornweald Archer")
      resolve(game)
      expect(chars(game, "Warrior")).to have_attributes(power: 2, toughness: 1)
      block_and_deal(game)
      expect(life(game, "bob")).to eq(15)
      skip_to(game, :end)
      resolve(game)
      expect(on_battlefield(game)).not_to include("Warrior")
    end

    it "exiles an opponent's nonland permanent until it leaves the battlefield (CR 610.3)" do
      game = play(alice: { hand: ["Stormplain Detainment", "Cathar Commando"], mana_pool: { W: 6 } },
                  bob: { battlefield: %w[Juggernaut Mountain] })
      cast_and_resolve(game, "Stormplain Detainment")
      game.submit(type: "target", target: id(game, "Juggernaut"))
      resolve(game)
      expect(on_battlefield(game)).not_to include("Juggernaut")
      cast_and_resolve(game, "Cathar Commando")
      activate(game, "Cathar Commando", "printed:0", id(game, "Stormplain Detainment"))
      resolve(game)
      expect(on_battlefield(game)).to include("Juggernaut")
    end

    it "loyalty abilities: a +1/+1 counter, flying and double strike, and a Cat per point of life (CR 606)" do
      game = play(alice: { battlefield: ["Ajani, Caller of the Pride", "Brazen Scourge"] })
      activate(game, "Ajani, Caller of the Pride", "printed:0", id(game, "Brazen Scourge"))
      resolve(game)
      expect(counters(game, "Brazen Scourge")).to eq("+1/+1" => 1)
      expect(counters(game, "Ajani, Caller of the Pride")).to eq("loyalty" => 5)
      game = play(alice: { battlefield: ["Ajani, Caller of the Pride", "Brazen Scourge"] })
      activate(game, "Ajani, Caller of the Pride", "printed:1", id(game, "Brazen Scourge"))
      resolve(game)
      expect(%i[flying double_strike].map { chars(game, "Brazen Scourge").keyword?(it) }).to eq([true, true])
      game = play(alice: { battlefield: [["Ajani, Caller of the Pride", { loyalty: 8 }]], life: 3 })
      activate(game, "Ajani, Caller of the Pride", "printed:2")
      resolve(game)
      expect(on_battlefield(game).count("Cat")).to eq(3)
      expect(names(game, "alice", :graveyard)).to eq(["ajani_caller_of_the_pride"]) # 0 loyalty (CR 704.5i)
    end
  end

  describe "lands" do
    it "basic lands tap for their color (CR 305.6)" do
      game = play(alice: { battlefield: %w[Plains Island Swamp Mountain Forest] })
      %w[Plains Island Swamp Mountain Forest].each do |land|
        game.submit(type: "activate_mana", object: id(game, land), ability: "intrinsic:#{land.downcase}")
      end
      expect(game.state.players[0].mana_pool).to include(W: 1, U: 1, B: 1, R: 1, G: 1)
    end

    { "Bloodfell Caves" => %w[B R], "Jungle Hollow" => %w[B G], "Rugged Highlands" => %w[R G],
      "Tranquil Cove" => %w[W U] }.each do |land, colors|
      it "#{land} enters tapped, gains 1 life and taps for #{colors.join(" or ")}" do
        game = play(alice: { hand: [land] })
        game.submit(type: "play_land", object: id(game, land))
        resolve(game)
        expect([life(game), game.state.object(id(game, land)).tapped]).to eq([21, true])
        game = play(alice: { battlefield: [land] })
        expect(game.legal_options.filter_map { it[:mana] if it[:object] == id(game, land) }).to eq(colors.map { "{#{it}}" })
      end
    end

    it "sacrifices itself to put a basic land onto the battlefield tapped (CR 701.23)" do
      game = play(alice: { battlefield: ["Evolving Wilds"] })
      activate(game, "Evolving Wilds", "printed:0")
      resolve(game)
      game.submit(game.legal_options.first) while game.pending_decision.kind == "effect_choice"
      resolve(game)
      expect(on_battlefield(game)).to eq(["Forest"])
      expect(game.state.object(id(game, "Forest")).tapped).to be(true)
    end

    it "taps for {C}, or makes a creature unblockable this turn" do
      game = play(alice: { battlefield: ["Rogue's Passage", "Brazen Scourge"], mana_pool: { R: 4 } })
      activate(game, "Rogue's Passage", "printed:1", id(game, "Brazen Scourge"))
      resolve(game)
      expect(chars(game, "Brazen Scourge").keyword?(:cant_be_blocked)).to be(true)
    end
  end

  describe "costs and ward" do
    it "costs {1} less per instant and sorcery card in your graveyard; ward taxes an opponent's targeting (CR 702.21a)" do
      game = play(alice: { hand: ["Tolarian Terror"], graveyard: %w[Stab Abrade Overrun], mana_pool: { U: 4 } },
                  bob: { hand: ["Stab"], battlefield: ["Swamp"] })
      cast_and_resolve(game, "Tolarian Terror")
      expect(on_battlefield(game)).to include("Tolarian Terror")
      skip_to(game, :upkeep, turn: 4)
      game.submit(type: "pass") until game.pending_decision.player == "bob" && game.pending_decision.kind == "priority"
      cast(game, "Stab", id(game, "Tolarian Terror"))
      resolve(game)
      expect(chars(game, "Tolarian Terror").power).to eq(5) # countered: bob couldn't pay {2}
    end

    it "exiles a card from a graveyard and gains 1 life as it enters or attacks; cycles for {2}" do
      game = play(alice: { hand: ["Wreck Remover"], mana_pool: { C: 4 } }, bob: { graveyard: ["Stab"] })
      cast_and_resolve(game, "Wreck Remover")
      game.submit(type: "target", target: id(game, "Stab"))
      resolve(game)
      expect([names(game, "bob", :graveyard), life(game)]).to eq([[], 21])
    end
  end

  describe "renew: keyword counters from the graveyard (CR 122.1b)" do
    it "a +1/+1 counter and a trample counter" do
      game = play(alice: { graveyard: ["Champion of Dusan"], battlefield: ["Thornweald Archer"], mana_pool: { G: 2 } })
      activate(game, "Champion of Dusan", "printed:0", id(game, "Thornweald Archer"))
      resolve(game)
      expect(counters(game, "Thornweald Archer")).to eq("+1/+1" => 1, "trample" => 1)
      expect(chars(game, "Thornweald Archer").keyword?(:trample)).to be(true)
    end

    it "flying, deathtouch and lifelink counters" do
      game = play(alice: { graveyard: ["Qarsi Revenant"], battlefield: ["Brazen Scourge"], mana_pool: { B: 3 } })
      activate(game, "Qarsi Revenant", "printed:0", id(game, "Brazen Scourge"))
      resolve(game)
      expect(%i[flying deathtouch lifelink].map { chars(game, "Brazen Scourge").keyword?(it) }).to eq([true, true, true])
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["qarsi_revenant"])
    end
  end

  it "random two-color decks built from the pool survive the fuzzer with the RulesMonitor on" do
    builder = Enjine::DeckBuilder.new(pool)
    players = [1, 2].map { Enjine::Player.new(name: "p#{it}", deck: builder.build(colors: 2, seed: it)) }
    result = Enjine::Fuzz.run(Enjine::Setup.new(*players), games: 2, seed: 5, roundtrip_every: 97)
    expect(result.outcomes.values.sum).to eq(2)
    expect(result.casts).not_to be_empty
  end
end
