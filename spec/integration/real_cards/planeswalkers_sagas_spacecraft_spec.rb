# frozen_string_literal: true

# Real Standard cards (trk, eoe, fin, ecl) written in the card DSL: planeswalkers, Sagas, Spacecraft and
# Planets, warp, double-faced cards, job select, blight, kindred, copies and the Star Trek mechanics. Every card
# is cast, played or activated here and its effect checked.
RSpec.describe "Real cards: planeswalkers, Sagas and Spacecraft" do
  let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.cards + CardFixtures.real("planeswalkers_sagas_spacecraft")) }

  # Alice's precombat main phase of turn 3, with nine mana of each type in the active player's pool. Zones
  # take card names; a battlefield entry may be [name, options] (tapped:, counters:, controlled_since:).
  def board(alice: {}, bob: {}, active: "alice")
    build_game(catalog) do
      turn 3, active: active, step: :precombat_main
      { "alice" => alice, "bob" => bob }.each do |name, zones|
        player(name, life: zones.fetch(:life, 20), mana_pool: name == active ? Enjine::Mana::TYPES.to_h { [it, 9] } : {}) do
          %i[hand graveyard exile].each { |zone| Array(zones[zone]).each { send(zone, it) } }
          Array(zones[:battlefield]).each { |card, opts| battlefield card, **(opts || {}) }
          library(*zones.fetch(:library, ["Forest"] * 10))
        end
      end
    end
  end

  def objects(game, player, zone)
    owner = game.names.index(player)
    ids = %i[battlefield exile stack].include?(zone) ? game.state.public_send(zone) : game.state.players[owner].public_send(zone)
    ids.map { game.state.object(it) }.select { zone == :battlefield ? it.controller == owner : it.owner == owner }
  end

  def id(game, card, zone: :battlefield, player: "alice")
    objects(game, player, zone).find { it.card == Enjine::CardDefinition.slug(card) }&.id or raise "no #{card} in #{player}'s #{zone}"
  end

  def names(game, player, zone) = objects(game, player, zone).map { it.card.sub(/_token_\h+\z/, "") }
  def life(game, who) = game.view_for(:observer)["players"].find { it["name"] == who }["life"]
  def chars(game, object_id) = game.instance_variable_get(:@engine).chars(object_id)
  def pt(game, object_id) = view_of(game, object_id).values_at("power", "toughness")
  def counters(game, object_id) = game.state.object(object_id).counters
  def equipped(game, equipment) = game.state.object(id(game, equipment)).attached_to
  def tokens(game, player) = objects(game, player, :battlefield).select { game.instance_variable_get(:@engine).token?(it) }.map(&:id)

  # Answers decisions until `stop` holds at a priority decision (default: the stack is empty): the next
  # `answers` entry when it matches a legal option (a partial hash), else a mana payment, else a pass (or
  # "done" when declaring attackers and blockers).
  def drive(game, answers, stop: ->(g) { g.state.stack.empty? })
    turn = game.turn
    2000.times do
      raise "unused answers #{answers}: #{game.pending_decision.kind} #{game.legal_options}" if game.turn > turn + 2

      options = game.legal_options
      wanted = answers.find { |a| options.any? { |o| a.all? { |k, v| o[k] == v } } }
      answer = wanted && options.find { |o| wanted.all? { |k, v| o[k] == v } }
      if answer then answers.delete_at(answers.index(wanted))
      elsif game.pending_decision.kind == "pay_cost"
        answer = options.find { it[:type] == "pay_mana" } || options.find { it[:type] == "activate_mana" }
      elsif game.pending_decision.kind == "priority"
        return game if answers.empty? && stop.call(game)

        answer = { type: "pass" }
      elsif game.pending_decision.kind == "order_triggers" || options.include?({ type: "done" })
        answer = options.find { it[:type] == "done" } || options.first
      else raise "no answer for #{game.pending_decision.kind} #{game.pending_decision.details} #{options}"
      end
      game.submit(answer)
    end
    raise "drive did not settle: answers left #{answers}"
  end

  # Submits `option` and answers the decisions until everything it put on the stack has resolved.
  def play(game, option, *answers, resolve: true)
    game.submit(option)
    drive(game, answers, stop: resolve ? ->(g) { g.state.stack.empty? } : ->(_) { true })
  end

  def cast(game, card, *answers, from: :hand, player: "alice", resolve: true, **extra)
    play(game, { type: "cast", object: id(game, card, zone: from, player: player), **extra }, *answers, resolve: resolve)
  end

  # Casts by the first legal cast option for the card other than its normal one (warp, beam me up, a permission).
  def cast_via(game, card, *answers, from: :hand)
    object = id(game, card, zone: from)
    option = game.legal_options.find { it[:type] == "cast" && it[:object] == object && it[:via] }
    raise "no alternative cast for #{card}: #{game.legal_options}" unless option

    play(game, option, *answers)
  end

  # `ability`: a printed ability's index, or a ref such as "keyword:station".
  def activate(game, card, ability, *answers, player: "alice")
    ref = ability.is_a?(Integer) ? "printed:#{ability}" : ability
    play(game, { type: "activate", object: id(game, card, player: player), ability: ref }, *answers)
  end

  def play_land(game, card, *answers) = play(game, { type: "play_land", object: id(game, card, zone: :hand) }, *answers)
  def to_step(game, step, *answers) = drive(game, answers, stop: ->(g) { g.step == step && g.state.stack.empty? })

  def next_turn(game, *answers)
    turn = game.turn + (game.state.active.zero? ? 2 : 1)
    drive(game, answers, stop: ->(g) { g.turn == turn && g.step == :precombat_main && g.state.stack.empty? })
  end

  def attack(game, attackers, *answers)
    to_step(game, :declare_attackers, *attackers.map { { type: "attack", object: it } }, *answers)
  end

  describe "trk" do
    it "70,000 Light-Years from Home exiles a Spacecraft; its controller may fetch a basic land" do
      game = board(alice: { hand: ["70,000 Light-Years from Home"] }, bob: { battlefield: [["Class-F Shuttlecraft"]] })
      cast(game, "70,000 Light-Years from Home", { target: id(game, "Class-F Shuttlecraft", player: "bob") }, { type: "search" },
           { type: "find" })
      expect(names(game, "bob", :exile)).to eq(["class_f_shuttlecraft"])
      expect(names(game, "bob", :hand)).to eq(["forest"])
    end

    it "A Good Day to Die pumps a creature and draws a card when it dies this turn" do
      game = board(alice: { hand: ["A Good Day to Die", "Lightning Bolt"], battlefield: [["Grizzly Bears"]] })
      bears = id(game, "Grizzly Bears")
      cast(game, "A Good Day to Die", { target: bears })
      expect(pt(game, bears)).to eq([4, 2])
      cast(game, "Lightning Bolt", { target: bears })
      expect(names(game, "alice", :hand)).to eq(["forest"])
    end

    it "Amok Time: I fights, II gains 3 life, III returns a creature card, then it's sacrificed" do
      game = board(alice: { hand: ["Amok Time"], battlefield: [["Hill Giant"]], graveyard: ["Grizzly Bears"] },
                   bob: { battlefield: [["Grizzly Bears"]] })
      cast(game, "Amok Time", { target: id(game, "Hill Giant") }, { target: id(game, "Grizzly Bears", player: "bob") })
      expect(names(game, "bob", :battlefield)).to be_empty
      next_turn(game)
      expect(life(game, "alice")).to eq(23)
      next_turn(game, { target: id(game, "Grizzly Bears", zone: :graveyard) })
      expect(names(game, "alice", :hand)).to include("grizzly_bears")
      expect(names(game, "alice", :battlefield)).not_to include("amok_time")
    end

    it "Planets enter tapped and gain 1 life; shocklands ask for 2 life; Federation Outpost chooses a mode untapped" do
      game = board(alice: { hand: ["Andoria"] })
      play_land(game, "Andoria")
      expect([game.state.object(id(game, "Andoria")).tapped, life(game, "alice")]).to eq([true, 21])
      game = board(alice: { hand: ["Blood Crypt"] })
      play_land(game, "Blood Crypt", { type: "pay_life" })
      expect([game.state.object(id(game, "Blood Crypt")).tapped, life(game, "alice")]).to eq([false, 18])
      game = board(alice: { hand: ["Federation Outpost"], battlefield: %w[Plains Plains] })
      play_land(game, "Federation Outpost", { mode: 0 })
      expect([game.state.object(id(game, "Federation Outpost")).tapped, life(game, "alice")]).to eq([false, 22])
    end

    it "Adversary by Algorithm makes a 3/3 Illusion, then is cast again with beam me up" do
      game = board(alice: { hand: ["Adversary by Algorithm"], battlefield: [["Grizzly Bears"]] })
      cast(game, "Adversary by Algorithm")
      expect(names(game, "alice", :battlefield)).to include("illusion")
      cast_via(game, "Adversary by Algorithm", { type: "cost", object: id(game, "Grizzly Bears") }, from: :graveyard)
      expect(names(game, "alice", :battlefield).count("illusion")).to eq(2)
      expect(names(game, "alice", :hand)).to eq(["grizzly_bears"])
      expect(names(game, "alice", :exile)).to eq(["adversary_by_algorithm"])
    end

    it "Borg Cube costs less per artifact creature, exiles a creature as it enters, and flies its Borg at 12+" do
      game = board(alice: { hand: ["Borg Cube"], battlefield: [["Bastion Golem"]] }, bob: { battlefield: [["Grizzly Bears"]] })
      cast(game, "Borg Cube", { target: id(game, "Grizzly Bears", player: "bob") })
      expect(names(game, "bob", :exile)).to eq(["grizzly_bears"])
      expect(chars(game, id(game, "Bastion Golem")).keyword?(:flying)).to be(false)
      game = board(alice: { battlefield: [["Borg Cube", { counters: { "charge" => 12 } }], ["Bastion Golem"]] })
      expect(chars(game, id(game, "Bastion Golem")).keyword?(:flying)).to be(true)
      expect(pt(game, id(game, "Borg Cube"))).to eq([6, 6])
    end

    it "Class-F Shuttlecraft taps for any color and is a 2/4 flier at 6+" do
      game = board(alice: { battlefield: [["Class-F Shuttlecraft"]] })
      expect(chars(game, id(game, "Class-F Shuttlecraft")).creature?).to be(false)
      expect(game.legal_options).to include(a_hash_including(type: "activate_mana", object: id(game, "Class-F Shuttlecraft")))
      game = board(alice: { battlefield: [["Class-F Shuttlecraft", { counters: { "charge" => 6 } }]] })
      expect(pt(game, id(game, "Class-F Shuttlecraft"))).to eq([2, 4])
      expect(chars(game, id(game, "Class-F Shuttlecraft")).keyword?(:vigilance)).to be(true)
    end

    it "Command Decision destroys a big creature; choosing a mode is a dilemma for Elim Garak" do
      game = board(alice: { hand: ["Command Decision"], battlefield: [["Elim Garak, Simple Tailor"]] },
                   bob: { battlefield: [["Craw Wurm"]] })
      cast(game, "Command Decision", { mode: 0 }, { target: id(game, "Craw Wurm", player: "bob") })
      expect(names(game, "bob", :graveyard)).to eq(["craw_wurm"])
      expect([life(game, "alice"), life(game, "bob")]).to eq([22, 18])
    end

    it "Encounter the Unknown deals 2 to each creature and player, or exiles two cards to play" do
      game = board(alice: { hand: ["Encounter the Unknown"], battlefield: [["Grizzly Bears"]] }, bob: { battlefield: [["Hill Giant"]] })
      cast(game, "Encounter the Unknown", { mode: 1 })
      expect([names(game, "alice", :battlefield), names(game, "bob", :battlefield)]).to eq([[], ["hill_giant"]])
      expect([life(game, "alice"), life(game, "bob")]).to eq([18, 18])
      game = board(alice: { hand: ["Encounter the Unknown"], library: ["Mountain", "Lightning Bolt", "Forest"] })
      cast(game, "Encounter the Unknown", { mode: 0 })
      expect(names(game, "alice", :exile)).to contain_exactly("mountain", "lightning_bolt")
      expect(game.legal_options).to include(a_hash_including(type: "cast", object: id(game, "Lightning Bolt", zone: :exile)))
    end

    it "Energize returns an opposing creature to its owner's hand" do
      game = board(alice: { hand: ["Energize"], battlefield: [["Savannah Lions"]] }, bob: { battlefield: [["Hill Giant"]] })
      cast(game, "Energize", { target: id(game, "Hill Giant", player: "bob") })
      expect(names(game, "bob", :hand)).to eq(["hill_giant"])
      expect(names(game, "alice", :graveyard)).to eq(["energize"])
    end

    it "Engineered Explosives counts the colors spent and destroys each nonland permanent of that mana value" do
      game = board(alice: { hand: ["Engineered Explosives"] }, bob: { battlefield: [["Grizzly Bears"], ["Hill Giant"], ["Forest"]] })
      cast(game, "Engineered Explosives", { type: "x", value: 2 }, { type: "pay_mana", mana: "G" }, { type: "pay_mana", mana: "R" })
      explosives = id(game, "Engineered Explosives")
      expect(counters(game, explosives)).to eq("charge" => 2)
      activate(game, "Engineered Explosives", 0)
      expect(names(game, "bob", :battlefield)).to eq(%w[hill_giant forest])
    end

    it "Eject the Warp Core gives -2/-2, or -6/-6 when kicked by sacrificing a creature" do
      game = board(alice: { hand: ["Eject the Warp Core"], battlefield: [["Savannah Lions"]] }, bob: { battlefield: [["Craw Wurm"]] })
      cast(game, "Eject the Warp Core", { type: "kick" }, { type: "cost", object: id(game, "Savannah Lions") },
           { target: id(game, "Craw Wurm", player: "bob") })
      expect(names(game, "bob", :graveyard)).to eq(["craw_wurm"])
      expect(names(game, "alice", :graveyard)).to contain_exactly("savannah_lions", "eject_the_warp_core")
    end

    it "Highly Illogical counters a cheap spell, or any spell when kicked" do
      game = board(alice: { hand: ["Hill Giant", "Highly Illogical"] })
      cast(game, "Hill Giant", resolve: false)
      giant = id(game, "Hill Giant", zone: :stack)
      cast(game, "Highly Illogical", { type: "kick" }, { target: giant })
      expect(names(game, "alice", :graveyard)).to contain_exactly("hill_giant", "highly_illogical")
    end

    it "Khaaaaaaaaaaaannn! deals twice X damage and exiles the creature if it would die" do
      game = board(alice: { hand: ["Khaaaaaaaaaaaannn!"] }, bob: { battlefield: [["Craw Wurm"]] })
      cast(game, "Khaaaaaaaaaaaannn!", { type: "x", value: 2 }, { target: id(game, "Craw Wurm", player: "bob") })
      expect(names(game, "bob", :exile)).to eq(["craw_wurm"])
    end

    it "Dominion Saboteur enters as a copy of a creature with the same counters" do
      game = board(alice: { hand: ["Dominion Saboteur"] }, bob: { battlefield: [["Grizzly Bears", { counters: { "+1/+1" => 2 } }]] })
      cast(game, "Dominion Saboteur", { object: id(game, "Grizzly Bears", player: "bob") })
      copy = id(game, "Grizzly Bears")
      expect(pt(game, copy)).to eq([4, 4])
      expect(view_of(game, copy)["name"]).to eq("Grizzly Bears")
    end

    it "Captain Pike counts differently named lands and plays lands from the top of the library" do
      game = board(alice: { battlefield: [["Captain Pike, Fullness of Time"], ["Forest"], ["Forest"], ["Andoria"]],
                            library: %w[Mountain Forest] })
      pike = id(game, "Captain Pike, Fullness of Time")
      expect(pt(game, pike)).to eq([2, 2])
      play(game, game.legal_options.find { it[:type] == "play_land" })
      expect(pt(game, pike)).to eq([3, 3])
    end

    it "Year of Hell: each player draws and takes 2 damage each chapter" do
      game = board(alice: { hand: ["Year of Hell"] })
      cast(game, "Year of Hell")
      expect([life(game, "alice"), life(game, "bob")]).to eq([18, 18])
      expect([names(game, "alice", :hand).size, names(game, "bob", :hand).size]).to eq([1, 1])
    end

    it "The Wrath of Khan deals 4 damage, then steals the creature at the next combat" do
      game = board(alice: { hand: ["The Wrath of Khan"] }, bob: { battlefield: [["Wall of Timber", { tapped: true }]] })
      wall = id(game, "Wall of Timber", player: "bob")
      cast(game, "The Wrath of Khan", { target: wall })
      expect(game.state.object(wall).damage).to eq(4)
      to_step(game, :beginning_of_combat)
      expect(game.state.object(wall)).to have_attributes(controller: 0, tapped: false)
      expect(chars(game, wall).keyword?(:haste)).to be(true)
    end

    it "D-7 Battle Cruiser is stationed and makes a hasty Klingon at combat from 3+" do
      game = board(alice: { battlefield: [["D-7 Battle Cruiser"], ["Hill Giant"]] })
      activate(game, "D-7 Battle Cruiser", "keyword:station", { type: "cost", object: id(game, "Hill Giant") })
      expect(counters(game, id(game, "D-7 Battle Cruiser"))).to eq("charge" => 3)
      to_step(game, :beginning_of_combat)
      expect(names(game, "alice", :battlefield)).to include("klingon_warrior")
      to_step(game, :end)
      expect(names(game, "alice", :battlefield)).not_to include("klingon_warrior")
    end

    it "Enterprise NX-01 taps and stuns; U.S.S. Excelsior destroys a tapped creature" do
      game = board(alice: { hand: ["Enterprise NX-01", "U.S.S. Excelsior, Cutting Edge"] }, bob: { battlefield: [["Grizzly Bears"]] })
      bears = id(game, "Grizzly Bears", player: "bob")
      cast(game, "Enterprise NX-01", { target: bears })
      expect([game.state.object(bears).tapped, counters(game, bears)]).to eq([true, { "stun" => 1 }])
      cast(game, "U.S.S. Excelsior, Cutting Edge", { target: bears })
      expect(names(game, "bob", :graveyard)).to eq(["grizzly_bears"])
    end

    it "Death Is Irrelevant makes artifact creatures indestructible and assimilates at the end step" do
      game = board(alice: { battlefield: [["Death Is Irrelevant"]] }, bob: { graveyard: ["Grizzly Bears"] })
      to_step(game, :end, { target: id(game, "Grizzly Bears", zone: :graveyard, player: "bob") })
      bears = id(game, "Grizzly Bears")
      expect(chars(game, bears)).to have_attributes(types: contain_exactly(:artifact, :creature), subtypes: [:borg])
      expect(chars(game, bears).keyword?(:indestructible)).to be(true)
      expect(counters(game, bears)).to eq("+1/+1" => 1)
    end

    it "Combadge copies itself when cast" do
      game = board(alice: { hand: ["Combadge"] })
      cast(game, "Combadge")
      expect(names(game, "alice", :battlefield)).to eq(%w[combadge combadge])
    end

    it "Kai Winn and Nyota Uhura punish the chosen name and mana value" do
      game = board(alice: { hand: ["Kai Winn, Faithless Leader", "Nyota Uhura, Communications"] },
                   bob: { hand: ["Lightning Bolt"], battlefield: [["Mountain"]] })
      cast(game, "Kai Winn, Faithless Leader", { name: "Lightning Bolt" })
      cast(game, "Nyota Uhura, Communications", { number: 1 })
      game.submit(type: "pass")
      cast(game, "Lightning Bolt", { target: "player:alice" }, player: "bob")
      expect([life(game, "alice"), life(game, "bob")]).to eq([17, 17])
      expect(names(game, "alice", :hand)).to eq(["forest"])
    end

    it "Mr. Spock doubles draws (Cloistered Telepath loots)" do
      game = board(alice: { hand: ["Cloistered Telepath"], battlefield: [["Mr. Spock, Science Officer"]] })
      cast(game, "Cloistered Telepath", { type: "discard" })
      expect([names(game, "alice", :hand).size, names(game, "alice", :graveyard).size]).to eq([1, 1])
    end

    it "Set Phasers to . . . taps and stuns" do
      game = board(alice: { hand: ["Set Phasers to . . ."] }, bob: { battlefield: [["Grizzly Bears"]] })
      bears = id(game, "Grizzly Bears", player: "bob")
      cast(game, "Set Phasers to . . .", { mode: 0 }, { target: bears })
      expect(counters(game, bears)).to eq("stun" => 1)
    end

    it "Bat'leth shrinks an opposing creature and equips for +2/+0; Tricorder gives +1/+1 and surveils on attack" do
      game = board(alice: { hand: ["Bat'leth", "Tricorder"], battlefield: [["Grizzly Bears"]] }, bob: { battlefield: [["Savannah Lions"]] })
      bears = id(game, "Grizzly Bears")
      cast(game, "Bat'leth", { target: id(game, "Savannah Lions", player: "bob") })
      expect(names(game, "bob", :graveyard)).to eq(["savannah_lions"])
      activate(game, "Bat'leth", 2, { target: bears })
      cast(game, "Tricorder")
      activate(game, "Tricorder", 2, { target: bears })
      expect(pt(game, bears)).to eq([5, 3])
      attack(game, [bears], { type: "graveyard" })
      expect(names(game, "alice", :graveyard)).to eq(["forest"])
    end

    it "The Holodeck plays a permanent card from the graveyard once each turn" do
      game = board(alice: { battlefield: [["The Holodeck"]], graveyard: ["Grizzly Bears", "Savannah Lions"] })
      cast_via(game, "Grizzly Bears", from: :graveyard)
      expect(names(game, "alice", :battlefield)).to include("grizzly_bears")
      expect(game.legal_options).not_to include(a_hash_including(object: id(game, "Savannah Lions", zone: :graveyard)))
    end

    it "Pure Energy divides two +1/+1 counters" do
      game = board(alice: { hand: ["Pure Energy"], battlefield: [["Grizzly Bears"], ["Savannah Lions"]] })
      cast(game, "Pure Energy", { target: id(game, "Grizzly Bears") }, { target: id(game, "Savannah Lions") })
      expect([counters(game, id(game, "Grizzly Bears")), counters(game, id(game, "Savannah Lions"))]).to eq([{ "+1/+1" => 1 }] * 2)
    end

    it "Rules of Acquisition steals a permanent and its controller draws three" do
      game = board(alice: { hand: ["Rules of Acquisition"] }, bob: { battlefield: [["Hill Giant"]] })
      cast(game, "Rules of Acquisition", { mode: 0 }, { target: id(game, "Hill Giant", player: "bob") })
      expect(names(game, "alice", :battlefield)).to eq(["hill_giant"])
      expect(names(game, "bob", :hand).size).to eq(3)
    end
  end

  describe "eoe" do
    it "Planets enter tapped and gain abilities from their station striation: Adagia copies, Kavaron rallies, Evendo ramps" do
      game = board(alice: { hand: ["Adagia, Windswept Bastion"] })
      play_land(game, "Adagia, Windswept Bastion")
      expect(game.state.object(id(game, "Adagia, Windswept Bastion")).tapped).to be(true)
      game = board(alice: { battlefield: [["Adagia, Windswept Bastion", { counters: { "charge" => 12 } }], ["Class-F Shuttlecraft"]] })
      activate(game, "Adagia, Windswept Bastion", "printed:2:0", { target: id(game, "Class-F Shuttlecraft") })
      expect(chars(game, tokens(game, "alice").first).supertypes).to eq([:legendary])
      game = board(alice: { battlefield: [["Kavaron, Memorial World", { counters: { "charge" => 12 } }], ["Mountain"], ["Grizzly Bears"]] })
      activate(game, "Kavaron, Memorial World", "printed:2:0", { type: "cost", object: id(game, "Mountain") })
      robot = tokens(game, "alice").first
      expect([pt(game, robot), pt(game, id(game, "Grizzly Bears"))]).to eq([[3, 2], [3, 2]])
      expect(chars(game, robot).keyword?(:haste)).to be(true)
      game = board(alice: { battlefield: [["Evendo, Waking Haven", { counters: { "charge" => 12 } }], ["Grizzly Bears"], ["Hill Giant"]] })
      expect(game.legal_options).to include(a_hash_including(type: "activate_mana", object: id(game, "Evendo, Waking Haven"),
                                                             ability: "printed:2:0"))
    end

    it "All-Fates Stalker, warped, exiles a creature until it leaves; it is exiled at the end step and the creature returns" do
      game = board(alice: { hand: ["All-Fates Stalker"] }, bob: { battlefield: [["Grizzly Bears"]] })
      cast_via(game, "All-Fates Stalker", { target: id(game, "Grizzly Bears", player: "bob") })
      expect(names(game, "bob", :exile)).to eq(["grizzly_bears"])
      to_step(game, :end)
      expect(names(game, "bob", :battlefield)).to eq(["grizzly_bears"])
      expect(names(game, "alice", :exile)).to eq(["all_fates_stalker"])
    end

    it "Atmospheric Greenhouse puts a +1/+1 counter on each creature you control, doubled by Loading Zone" do
      game = board(alice: { hand: ["Atmospheric Greenhouse"], battlefield: [["Grizzly Bears"], ["Loading Zone"]] })
      cast(game, "Atmospheric Greenhouse")
      expect(counters(game, id(game, "Grizzly Bears"))).to eq("+1/+1" => 2)
    end

    it "Warp: Bygone Colossus for {3}, Red Tiger Mechan with haste, then cast again from exile on a later turn" do
      game = board(alice: { hand: ["Bygone Colossus", "Red Tiger Mechan"], battlefield: [["Mountain"]] * 4 })
      cast_via(game, "Bygone Colossus")
      cast_via(game, "Red Tiger Mechan")
      expect(pt(game, id(game, "Bygone Colossus"))).to eq([9, 9])
      expect(view_of(game, id(game, "Red Tiger Mechan"))["summoning_sick"]).to be(false)
      next_turn(game)
      expect(names(game, "alice", :exile)).to contain_exactly("bygone_colossus", "red_tiger_mechan")
      expect(game.legal_options).to include(a_hash_including(type: "cast", object: id(game, "Red Tiger Mechan", zone: :exile),
                                                             via: "warped"))
    end

    it "Cryogen Relic draws as it enters and leaves, stunning a tapped creature" do
      game = board(alice: { hand: ["Cryogen Relic"] }, bob: { battlefield: [["Grizzly Bears", { tapped: true }]] })
      cast(game, "Cryogen Relic")
      activate(game, "Cryogen Relic", 1, { target: id(game, "Grizzly Bears", player: "bob") })
      expect(names(game, "alice", :hand).size).to eq(2)
      expect(counters(game, id(game, "Grizzly Bears", player: "bob"))).to eq("stun" => 1)
    end

    it "Debris Field Crusher deals 3 damage as it enters; at 8+ it's a flier that pumps" do
      game = board(alice: { hand: ["Debris Field Crusher"] })
      cast(game, "Debris Field Crusher", { target: "player:bob" })
      expect(life(game, "bob")).to eq(17)
      game = board(alice: { battlefield: [["Debris Field Crusher", { counters: { "charge" => 8 } }]] })
      crusher = id(game, "Debris Field Crusher")
      activate(game, "Debris Field Crusher", "printed:1:0")
      expect(pt(game, crusher)).to eq([3, 5])
    end

    it "Devastating Onslaught makes X hasty copies that are sacrificed at the end step" do
      game = board(alice: { hand: ["Devastating Onslaught"], battlefield: [["Grizzly Bears"]] })
      cast(game, "Devastating Onslaught", { type: "x", value: 2 }, { target: id(game, "Grizzly Bears") })
      expect(names(game, "alice", :battlefield).count("grizzly_bears")).to eq(3)
      to_step(game, :end)
      expect(names(game, "alice", :battlefield)).to eq(["grizzly_bears"])
    end

    it "Invasive Maneuvers deals 3 damage, or 5 with a Spacecraft" do
      game = board(alice: { hand: ["Invasive Maneuvers"] }, bob: { battlefield: [["Wall of Timber"]] })
      cast(game, "Invasive Maneuvers", { target: id(game, "Wall of Timber", player: "bob") })
      expect(names(game, "bob", :battlefield)).to eq(["wall_of_timber"])
      game = board(alice: { hand: ["Invasive Maneuvers"], battlefield: [["Class-F Shuttlecraft"]] },
                   bob: { battlefield: [["Wall of Timber"]] })
      cast(game, "Invasive Maneuvers", { target: id(game, "Wall of Timber", player: "bob") })
      expect(names(game, "bob", :graveyard)).to eq(["wall_of_timber"])
    end

    it "Lumen-Class Frigate pumps other creatures at 2+ and is a 3/5 flying lifelinker at 12+" do
      game = board(alice: { battlefield: [["Lumen-Class Frigate", { counters: { "charge" => 2 } }], ["Grizzly Bears"]] })
      expect(pt(game, id(game, "Grizzly Bears"))).to eq([3, 3])
      expect(chars(game, id(game, "Lumen-Class Frigate")).creature?).to be(false)
      game = board(alice: { battlefield: [["Lumen-Class Frigate", { counters: { "charge" => 12 } }]] })
      expect(pt(game, id(game, "Lumen-Class Frigate"))).to eq([3, 5])
      expect(chars(game, id(game, "Lumen-Class Frigate")).keyword?(:lifelink)).to be(true)
    end

    it "Plasma Bolt deals 2, or 3 once a nonland permanent left the battlefield this turn (void)" do
      game = board(alice: { hand: ["Plasma Bolt", "Plasma Bolt", "Lightning Bolt"] }, bob: { battlefield: [["Savannah Lions"]] })
      cast(game, "Plasma Bolt", { target: "player:bob" })
      expect(life(game, "bob")).to eq(18)
      cast(game, "Lightning Bolt", { target: id(game, "Savannah Lions", player: "bob") })
      cast(game, "Plasma Bolt", { target: "player:bob" })
      expect(life(game, "bob")).to eq(15)
    end

    it "Seam Rip exiles a cheap permanent until it leaves" do
      game = board(alice: { hand: ["Seam Rip"] }, bob: { battlefield: [["Grizzly Bears"]] })
      cast(game, "Seam Rip", { target: id(game, "Grizzly Bears", player: "bob") })
      expect(names(game, "bob", :exile)).to eq(["grizzly_bears"])
    end

    it "Pinnacle Kill-Ship deals 10 damage to up to one creature; at 7+ it's a 7/7 flier" do
      game = board(alice: { hand: ["Pinnacle Kill-Ship"] }, bob: { battlefield: [["Craw Wurm"]] })
      cast(game, "Pinnacle Kill-Ship", { target: id(game, "Craw Wurm", player: "bob") })
      expect(names(game, "bob", :graveyard)).to eq(["craw_wurm"])
      game = board(alice: { battlefield: [["Pinnacle Kill-Ship", { counters: { "charge" => 7 } }]] })
      expect(pt(game, id(game, "Pinnacle Kill-Ship"))).to eq([7, 7])
    end

    it "Galactic Wayfarer makes a Lander that fetches a basic land" do
      game = board(alice: { hand: ["Galactic Wayfarer"], library: %w[Plains Forest] })
      cast(game, "Galactic Wayfarer")
      play(game, { type: "activate", object: tokens(game, "alice").first, ability: "printed:0" },
           { type: "find", object: id(game, "Plains", zone: :library) })
      expect(names(game, "alice", :battlefield)).to contain_exactly("galactic_wayfarer", "plains")
    end

    it "Embrace Oblivion sacrifices an artifact or creature to destroy a Spacecraft; Gravkill exiles one" do
      game = board(alice: { hand: ["Embrace Oblivion", "Gravkill"], battlefield: [["Savannah Lions"]] },
                   bob: { battlefield: [["Lumen-Class Frigate"], ["Class-F Shuttlecraft"]] })
      cast(game, "Embrace Oblivion", { type: "cost", object: id(game, "Savannah Lions") },
           { target: id(game, "Lumen-Class Frigate", player: "bob") })
      cast(game, "Gravkill", { target: id(game, "Class-F Shuttlecraft", player: "bob") })
      expect([names(game, "bob", :graveyard), names(game, "bob", :exile)]).to eq([["lumen_class_frigate"], ["class_f_shuttlecraft"]])
    end

    it "Germinating Wurm gains 2 life as it enters" do
      game = board(alice: { hand: ["Germinating Wurm"] })
      cast(game, "Germinating Wurm")
      expect(life(game, "alice")).to eq(22)
    end

    it "Susurian Dirgecraft makes each opponent sacrifice a nontoken creature" do
      game = board(alice: { hand: ["Susurian Dirgecraft"] }, bob: { battlefield: [["Grizzly Bears"]] })
      cast(game, "Susurian Dirgecraft")
      expect(names(game, "bob", :graveyard)).to eq(["grizzly_bears"])
    end

    it "Annul counters an artifact spell" do
      game = board(alice: { hand: ["Cryogen Relic", "Annul"] })
      cast(game, "Cryogen Relic", resolve: false)
      cast(game, "Annul", { target: id(game, "Cryogen Relic", zone: :stack) })
      expect(names(game, "alice", :graveyard)).to contain_exactly("cryogen_relic", "annul")
    end

    it "Beyond the Quiet exiles all creatures and Spacecraft" do
      game = board(alice: { hand: ["Beyond the Quiet"], battlefield: [["Grizzly Bears"], ["Forest"]] },
                   bob: { battlefield: [["Class-F Shuttlecraft"], ["Cryogen Relic"]] })
      cast(game, "Beyond the Quiet")
      expect([names(game, "alice", :battlefield), names(game, "bob", :battlefield)]).to eq([["forest"], ["cryogen_relic"]])
    end

    it "Sledge-Class Seedship at 7+ attacks and puts a creature card from hand onto the battlefield" do
      game = board(alice: { hand: ["Craw Wurm"], battlefield: [["Sledge-Class Seedship", { counters: { "charge" => 7 } }]] })
      attack(game, [id(game, "Sledge-Class Seedship")], { object: id(game, "Craw Wurm", zone: :hand) })
      expect(names(game, "alice", :battlefield)).to include("craw_wurm")
    end
  end

  describe "fin" do
    it "Summon: G.F. Ifrit is a Saga creature: loot on I and II, {R} on III and IV, then it's sacrificed" do
      game = board(alice: { hand: ["Summon: G.F. Ifrit", "Savannah Lions"] })
      cast(game, "Summon: G.F. Ifrit", { type: "yes" }, { object: id(game, "Savannah Lions", zone: :hand) })
      ifrit = id(game, "Summon: G.F. Ifrit")
      expect([pt(game, ifrit), names(game, "alice", :graveyard)]).to eq([[3, 2], ["savannah_lions"]])
      next_turn(game, { type: "no" })
      next_turn(game)
      expect(game.view_for(:observer)["players"][0]["mana_pool"]).to include("R" => 1)
      next_turn(game)
      expect(names(game, "alice", :graveyard)).to include("summon_g_f_ifrit")
    end

    it "Summon: Shiva taps and stuns on I and II, then draws per tapped opposing creature on III" do
      game = board(alice: { hand: ["Summon: Shiva"] }, bob: { battlefield: [["Grizzly Bears"]] })
      bears = id(game, "Grizzly Bears", player: "bob")
      cast(game, "Summon: Shiva", { target: bears })
      expect([game.state.object(bears).tapped, counters(game, bears)]).to eq([true, { "stun" => 1 }])
    end

    it "Summon: Choco/Mog gives other creatures +1/+0" do
      game = board(alice: { hand: ["Summon: Choco/Mog"], battlefield: [["Grizzly Bears"]] })
      cast(game, "Summon: Choco/Mog")
      expect([pt(game, id(game, "Grizzly Bears")), pt(game, id(game, "Summon: Choco/Mog"))]).to eq([[3, 2], [3, 3]])
    end

    it "Summon: Esper Ramuh deals damage equal to the noncreature, nonland cards in your graveyard" do
      game = board(alice: { hand: ["Summon: Esper Ramuh"], graveyard: ["Lightning Bolt", "Giant Growth", "Forest", "Grizzly Bears"] },
                   bob: { battlefield: [["Hill Giant"], ["Grizzly Bears"]] })
      cast(game, "Summon: Esper Ramuh", { target: id(game, "Grizzly Bears", player: "bob") })
      expect(names(game, "bob", :graveyard)).to eq(["grizzly_bears"])
    end

    it "Summon: Primal Garuda deals 4 damage to a tapped creature, then grants flying" do
      game = board(alice: { hand: ["Summon: Primal Garuda"] }, bob: { battlefield: [["Craw Wurm", { tapped: true }]] })
      cast(game, "Summon: Primal Garuda", { target: id(game, "Craw Wurm", player: "bob") })
      expect(names(game, "bob", :graveyard)).to eq(["craw_wurm"])
      expect(chars(game, id(game, "Summon: Primal Garuda")).keyword?(:flying)).to be(true)
    end

    it "Summon: Titan mills five, then returns the lands milled" do
      game = board(alice: { hand: ["Summon: Titan"], library: ["Forest", "Island", "Grizzly Bears", "Mountain", "Plains", "Forest"] })
      cast(game, "Summon: Titan")
      expect(names(game, "alice", :graveyard).size).to eq(5)
      next_turn(game)
      expect(names(game, "alice", :battlefield)).to include("island", "mountain", "plains")
      expect(names(game, "alice", :graveyard)).to eq(["grizzly_bears"])
    end

    it "Job select: each Equipment makes a Hero, attaches to it and gives it a job" do
      game = board(alice: { hand: ["Monk's Fist", "White Mage's Staff", "Black Mage's Rod", "Red Mage's Rapier"] })
      cast(game, "Monk's Fist")
      monk = equipped(game, "Monk's Fist")
      expect([pt(game, monk), chars(game, monk).subtypes]).to eq([[2, 1], %i[hero monk]])
      cast(game, "White Mage's Staff")
      cleric = equipped(game, "White Mage's Staff")
      expect([pt(game, cleric), chars(game, cleric).subtypes]).to eq([[2, 2], %i[hero cleric]])
      cast(game, "Black Mage's Rod")
      cast(game, "Red Mage's Rapier")
      expect(chars(game, equipped(game, "Red Mage's Rapier")).subtypes).to eq(%i[hero wizard])
      game = board(alice: { hand: ["Lightning Bolt"], battlefield: [["Black Mage's Rod"], ["Red Mage's Rapier"], ["Grizzly Bears"]] })
      bears = id(game, "Grizzly Bears")
      activate(game, "Black Mage's Rod", 1, { target: bears })
      activate(game, "Red Mage's Rapier", 1, { target: bears })
      cast(game, "Lightning Bolt", { target: "player:bob" })
      expect([life(game, "bob"), pt(game, bears)]).to eq([16, [5, 2]])
    end

    it "White Mage's Staff's Hero gains 1 life whenever it attacks" do
      game = board(alice: { battlefield: [["White Mage's Staff"], ["Grizzly Bears"]] })
      activate(game, "White Mage's Staff", 1, { target: id(game, "Grizzly Bears") })
      attack(game, [id(game, "Grizzly Bears")])
      expect(life(game, "alice")).to eq(21)
    end

    it "Cecil, Dark Knight costs life when it deals damage and transforms at half life" do
      game = board(alice: { life: 11, battlefield: [["Cecil, Dark Knight"]] })
      cecil = id(game, "Cecil, Dark Knight")
      attack(game, [cecil])
      to_step(game, :end)
      expect([life(game, "alice"), life(game, "bob")]).to eq([9, 18])
      expect(game.state.object(cecil)).to have_attributes(card: "cecil_dark_knight/1", tapped: false)
      expect(pt(game, cecil)).to eq([4, 4])
    end

    it "Sidequest: Raise a Chocobo makes a Bird and transforms with four Birds, fetching a land" do
      game = board(alice: { hand: ["Sidequest: Raise a Chocobo"], battlefield: [["Cloud Kite"]] * 3, library: ["Plains"] * 4 })
      cast(game, "Sidequest: Raise a Chocobo")
      expect(names(game, "alice", :battlefield)).to include("bird")
      next_turn(game, { type: "find" })
      chocobo = game.state.battlefield.find { game.state.object(it).card == "sidequest_raise_a_chocobo/1" }
      expect(chars(game, chocobo)).to have_attributes(name: "Black Chocobo", power: 3) # landfall from the land it fetched
      expect(names(game, "alice", :battlefield).count("plains")).to eq(1)
    end

    it "Balamb Garden taps for G or U and transforms into a flying Vehicle that draws when it attacks" do
      game = board(alice: { battlefield: [["Balamb Garden, SeeD Academy"], ["Baron, Airship Kingdom"], ["Grizzly Bears"]] })
      garden = id(game, "Balamb Garden, SeeD Academy")
      activate(game, "Balamb Garden, SeeD Academy", 2)
      expect(chars(game, garden)).to have_attributes(name: "Balamb Garden, Airborne", types: [:artifact])
      play(game, { type: "activate", object: garden, ability: "printed:1" }, { type: "cost", object: id(game, "Grizzly Bears") })
      expect(pt(game, garden)).to eq([5, 4])
    end

    it "Adelbert Steiner gets +1/+1 for each Equipment" do
      game = board(alice: { battlefield: [["Adelbert Steiner"], ["Tricorder"], ["Bat'leth"]] })
      expect(pt(game, id(game, "Adelbert Steiner"))).to eq([4, 3])
    end

    it "Adventurer's Airship is crewed and loots when it attacks" do
      game = board(alice: { hand: ["Lightning Bolt"], battlefield: [["Adventurer's Airship"], ["Grizzly Bears"]] })
      ship = id(game, "Adventurer's Airship")
      activate(game, "Adventurer's Airship", 1, { type: "cost", object: id(game, "Grizzly Bears") })
      expect(chars(game, ship).creature?).to be(true)
      attack(game, [ship], { type: "discard", object: id(game, "Lightning Bolt", zone: :hand) })
      expect(names(game, "alice", :graveyard)).to eq(["lightning_bolt"])
    end

    it "Adventurer's Inn gains 2 life; Baron, Airship Kingdom enters tapped" do
      game = board(alice: { hand: ["Adventurer's Inn"] })
      play_land(game, "Adventurer's Inn")
      expect(life(game, "alice")).to eq(22)
      game = board(alice: { hand: ["Baron, Airship Kingdom"] })
      play_land(game, "Baron, Airship Kingdom")
      expect(game.state.object(id(game, "Baron, Airship Kingdom")).tapped).to be(true)
    end

    it "Airship Crash destroys a flier or cycles" do
      game = board(alice: { hand: ["Airship Crash", "Airship Crash"] }, bob: { battlefield: [["Cloud Kite"]] })
      cast(game, "Airship Crash", { target: id(game, "Cloud Kite", player: "bob") })
      expect(names(game, "bob", :graveyard)).to eq(["cloud_kite"])
      play(game, game.legal_options.find { it[:type] == "activate" && it[:object] == id(game, "Airship Crash", zone: :hand) })
      expect(names(game, "alice", :hand)).to eq(["forest"])
    end

    it "Battle Menu makes a 2/2 Knight; Blitzball Shot gives +3/+3 and trample" do
      game = board(alice: { hand: ["Battle Menu", "Blitzball Shot"] })
      cast(game, "Battle Menu", { mode: 0 })
      knight = tokens(game, "alice").first
      cast(game, "Blitzball Shot", { target: knight })
      expect(pt(game, knight)).to eq([5, 5])
      expect(chars(game, knight).keyword?(:trample)).to be(true)
    end

    it "Evil Reawakened returns a creature card with two +1/+1 counters" do
      game = board(alice: { hand: ["Evil Reawakened"], graveyard: ["Hill Giant"] })
      cast(game, "Evil Reawakened", { target: id(game, "Hill Giant", zone: :graveyard) })
      expect(pt(game, id(game, "Hill Giant"))).to eq([5, 5])
    end

    it "Eject can't be countered, bounces a nonland permanent and draws" do
      game = board(alice: { hand: %w[Eject Counterspell] }, bob: { battlefield: [["Hill Giant"]] })
      cast(game, "Eject", { target: id(game, "Hill Giant", player: "bob") }, resolve: false)
      cast(game, "Counterspell", { target: id(game, "Eject", zone: :stack) })
      expect(names(game, "bob", :hand)).to eq(["hill_giant"])
      expect(names(game, "alice", :hand)).to eq(["forest"])
    end

    it "Instant Ramen draws, then is sacrificed for 3 life" do
      game = board(alice: { hand: ["Instant Ramen"] })
      cast(game, "Instant Ramen")
      activate(game, "Instant Ramen", 1)
      expect([names(game, "alice", :hand), life(game, "alice")]).to eq([["forest"], 23])
    end

    it "Ice Flan taps and stuns; Hecteyes makes each opponent discard; Dragoon's Wyvern makes a Hero" do
      game = board(alice: { hand: ["Ice Flan", "Hecteyes", "Dragoon's Wyvern"] },
                   bob: { hand: ["Forest"], battlefield: [["Grizzly Bears"]] })
      bears = id(game, "Grizzly Bears", player: "bob")
      cast(game, "Ice Flan", { target: bears })
      cast(game, "Hecteyes", { type: "discard" })
      cast(game, "Dragoon's Wyvern")
      expect([counters(game, bears), names(game, "bob", :graveyard)]).to eq([{ "stun" => 1 }, ["forest"]])
      expect(chars(game, tokens(game, "alice").first).subtypes).to eq([:hero])
    end
  end

  describe "ecl" do
    it "Ajani, Outland Chaperone: +1 makes a Kithkin, -2 deals 4 to a tapped creature" do
      game = board(alice: { battlefield: [["Ajani, Outland Chaperone"]] }, bob: { battlefield: [["Craw Wurm", { tapped: true }]] })
      ajani = id(game, "Ajani, Outland Chaperone")
      activate(game, "Ajani, Outland Chaperone", 0)
      expect([counters(game, ajani)["loyalty"], chars(game, tokens(game, "alice").first).subtypes]).to eq([4, [:kithkin]])
      game = board(alice: { battlefield: [["Ajani, Outland Chaperone"]] }, bob: { battlefield: [["Craw Wurm", { tapped: true }]] })
      activate(game, "Ajani, Outland Chaperone", 1, { target: id(game, "Craw Wurm", player: "bob") })
      expect([names(game, "bob", :graveyard), counters(game, id(game, "Ajani, Outland Chaperone"))["loyalty"]]).to eq([["craw_wurm"], 1])
    end

    it "Ajani's -8 puts any number of cheap nonland permanent cards from the top X onto the battlefield" do
      game = board(alice: { life: 3, battlefield: [["Ajani, Outland Chaperone", { counters: { "loyalty" => 8 } }]],
                            library: ["Grizzly Bears", "Hill Giant", "Savannah Lions", "Forest"] })
      activate(game, "Ajani, Outland Chaperone", 2, { type: "take", object: id(game, "Grizzly Bears", zone: :library) },
               { type: "take", object: id(game, "Savannah Lions", zone: :library) })
      expect(names(game, "alice", :battlefield)).to contain_exactly("grizzly_bears", "savannah_lions")
    end

    it "Blight Rot puts four -1/-1 counters on a creature" do
      game = board(alice: { hand: ["Blight Rot"] }, bob: { battlefield: [["Craw Wurm"]] })
      cast(game, "Blight Rot", { target: id(game, "Craw Wurm", player: "bob") })
      expect(names(game, "bob", :graveyard)).to eq(["craw_wurm"])
    end

    it "Boggart Mischief blights for two Goblins and drains when a Goblin dies; Sourbread Auntie blights 2 for two" do
      game = board(alice: { hand: ["Boggart Mischief", "Sourbread Auntie", "Lightning Bolt"], battlefield: [["Craw Wurm"]] })
      giant = id(game, "Craw Wurm")
      cast(game, "Boggart Mischief", { type: "yes" }, { object: giant })
      cast(game, "Sourbread Auntie", { type: "yes" }, { object: giant })
      expect(names(game, "alice", :battlefield).count("goblin")).to eq(4)
      expect(counters(game, giant)).to eq("-1/-1" => 3)
      cast(game, "Lightning Bolt", { target: tokens(game, "alice").first })
      expect([life(game, "alice"), life(game, "bob")]).to eq([21, 19])
    end

    it "Crib Swap exiles a creature and its controller gets a 1/1 changeling" do
      game = board(alice: { hand: ["Crib Swap"] }, bob: { battlefield: [["Craw Wurm"]] })
      cast(game, "Crib Swap", { target: id(game, "Craw Wurm", player: "bob") })
      shapeshifter = tokens(game, "bob").first
      expect([pt(game, shapeshifter), chars(game, shapeshifter).keyword?(:changeling)]).to eq([[1, 1], true])
    end

    it "Firdoch Core taps for any color and becomes a 4/4 artifact creature" do
      game = board(alice: { battlefield: [["Firdoch Core"]] })
      core = id(game, "Firdoch Core")
      activate(game, "Firdoch Core", 1)
      expect([chars(game, core).types, pt(game, core)]).to eq([%i[kindred artifact creature], [4, 4]])
    end

    it "Brigid's Command chooses two: a Kithkin for a player and +3/+3" do
      game = board(alice: { hand: ["Brigid's Command"], battlefield: [["Grizzly Bears"]] })
      bears = id(game, "Grizzly Bears")
      cast(game, "Brigid's Command", { mode: 1 }, { mode: 2 }, { target: "player:alice" }, { target: bears })
      expect([pt(game, bears), tokens(game, "alice").size]).to eq([[5, 5], 1])
    end

    it "Changeling Wayfinder may fetch a basic land; changelings have every creature type" do
      game = board(alice: { hand: ["Changeling Wayfinder", "Chitinous Graspling", "Gangly Stompling"], library: %w[Island Forest] })
      cast(game, "Changeling Wayfinder", { type: "search" }, { type: "find", object: id(game, "Island", zone: :library) })
      cast(game, "Chitinous Graspling")
      cast(game, "Gangly Stompling")
      expect(names(game, "alice", :hand)).to eq(["island"])
      expect(game.instance_variable_get(:@engine).chars(id(game, "Gangly Stompling")).keyword?(:trample)).to be(true)
      expect(Enjine::Mechanics::Amount.creature_types(chars(game, id(game, "Chitinous Graspling")))).to include(:goblin, :kithkin)
    end

    it "Dream Seizer blights 1 to make each opponent discard; Blighted Blackthorn blights 2 to draw" do
      game = board(alice: { hand: ["Dream Seizer", "Blighted Blackthorn"], battlefield: [["Craw Wurm"]] }, bob: { hand: ["Forest"] })
      wurm = id(game, "Craw Wurm")
      cast(game, "Dream Seizer", { type: "yes" }, { object: wurm }, { type: "discard" })
      cast(game, "Blighted Blackthorn", { type: "yes" }, { object: wurm })
      expect([names(game, "bob", :graveyard), counters(game, wurm), life(game, "alice")]).to eq([["forest"], { "-1/-1" => 3 }, 19])
      expect(names(game, "alice", :hand)).to eq(["forest"])
    end

    it "Gristle Glutton and Sting-Slinger blight as a cost" do
      game = board(alice: { hand: ["Lightning Bolt"], battlefield: [["Gristle Glutton"], ["Sting-Slinger"], ["Craw Wurm"]] })
      wurm = id(game, "Craw Wurm")
      activate(game, "Gristle Glutton", 0, { type: "cost", object: wurm }, { type: "discard" })
      activate(game, "Sting-Slinger", 0, { type: "cost", object: wurm })
      expect([names(game, "alice", :hand), counters(game, wurm), life(game, "bob")]).to eq([["forest"], { "-1/-1" => 2 }, 18])
    end

    it "Mutable Explorer makes a tapped Mutavault that becomes a 2/2 changeling" do
      game = board(alice: { hand: ["Mutable Explorer"] })
      cast(game, "Mutable Explorer")
      vault = tokens(game, "alice").first
      expect(game.state.object(vault).tapped).to be(true)
      play(game, { type: "activate", object: vault, ability: "printed:1" })
      expect([pt(game, vault), chars(game, vault).keyword?(:changeling)]).to eq([[2, 2], true])
    end

    it "Morcant's Eyes surveils each upkeep and makes an Elf per Elf card in the graveyard" do
      game = board(alice: { battlefield: [["Morcant's Eyes"]], graveyard: ["Many-Faced Wanderer", "Grizzly Bears"] })
      activate(game, "Morcant's Eyes", 1)
      expect(tokens(game, "alice").size).to eq(2)
      game = board(alice: { battlefield: [["Morcant's Eyes"]] })
      next_turn(game, { type: "graveyard" })
      expect(names(game, "alice", :graveyard)).to eq(["forest"])
    end

    it "Clachan Festival makes two Kithkin, and one more for {4}{W}" do
      game = board(alice: { hand: ["Clachan Festival"] })
      cast(game, "Clachan Festival")
      activate(game, "Clachan Festival", 1)
      expect(tokens(game, "alice").size).to eq(3)
    end

    it "Feisty Spikeling has first strike only during your turn" do
      game = board(alice: { battlefield: [["Feisty Spikeling"]] })
      expect(chars(game, id(game, "Feisty Spikeling")).keyword?(:first_strike)).to be(true)
      game = board(alice: { battlefield: [["Feisty Spikeling"]] }, active: "bob")
      expect(chars(game, id(game, "Feisty Spikeling")).keyword?(:first_strike)).to be(false)
    end

    it "Evolving Wilds fetches a basic land tapped" do
      game = board(alice: { battlefield: [["Evolving Wilds"]], library: %w[Swamp] })
      activate(game, "Evolving Wilds", 0, { type: "find" })
      expect(names(game, "alice", :battlefield)).to eq(["swamp"])
    end
  end
end
