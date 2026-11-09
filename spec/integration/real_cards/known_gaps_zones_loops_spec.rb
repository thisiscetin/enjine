# frozen_string_literal: true

# Real cards that need effects, zones and loops (spec/fixtures/cards/real/known_gaps_zones_loops.json): "repeat
# this process" (Sin), exiling until a total mana value (Improvisation Capstone), targeting a card exiled with
# the source (The Darkness Crystal), "if it was attacking" (Desculpting Blast), the Nth counter (Death to Our
# Enemies) and changing a target (Redirect Lightning); plus Borg Cube's linked assimilate, the mana value of a
# melded permanent, hideaway under another controller and earthbend's return ending with the land.
RSpec.describe "Real cards: effects, zones and loops" do
  let(:families) { %w[known_gaps_zones_loops exile_and_meld_mechanics bending_and_mounts planeswalkers_sagas_spacecraft] }
  let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.cards + families.flat_map { CardFixtures.real(it) }) }

  # Alice's precombat main phase of turn 3 (or `active`'s), with nine mana of each type in the active player's
  # pool. Zones take card names; a battlefield entry may be [name, options].
  def board(alice: {}, bob: {}, active: "alice", step: :precombat_main)
    build_game(catalog) do
      turn 3, active: active, step: step
      { "alice" => alice, "bob" => bob }.each do |name, zones|
        player(name, life: zones.fetch(:life, 20), mana_pool: name == active ? Enjine::Mana::TYPES.to_h { [it, 9] } : {}) do
          %i[hand graveyard exile].each { |zone| Array(zones[zone]).each { send(zone, it) } }
          Array(zones[:battlefield]).each { |card, opts| battlefield card, **(opts || {}) }
          library(*zones.fetch(:library, ["Forest"] * 10))
        end
      end
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)

  def objects(game, player, zone)
    owner = game.names.index(player)
    ids = %i[battlefield exile stack].include?(zone) ? game.state.public_send(zone) : game.state.players[owner].public_send(zone)
    ids.map { game.state.object(it) }.select { zone == :battlefield ? it.controller == owner : it.owner == owner }
  end

  def id(game, card, zone: :battlefield, player: "alice")
    objects(game, player, zone).find { it.card == Enjine::CardDefinition.slug(card) }&.id or raise "no #{card} in #{player}'s #{zone}"
  end

  def names(game, player, zone) = objects(game, player, zone).map(&:card)
  def life(game, who) = game.state.players[game.names.index(who)].life
  def tokens(game, player) = objects(game, player, :battlefield).select { engine(game).token?(it) }

  # Answers decisions until `stop` holds at a priority decision (default: the stack is empty): the next
  # `answers` entry when it matches a legal option (a partial hash), else a mana payment, else a pass.
  def drive(game, answers, stop: ->(g) { g.state.stack.empty? })
    500.times do
      options = game.legal_options
      wanted = answers.find { |a| options.any? { |o| a.all? { |k, v| o[k] == v } } }
      answer = wanted && options.find { |o| wanted.all? { |k, v| o[k] == v } }
      if answer then answers.delete_at(answers.index(wanted))
      elsif game.pending_decision.kind == "pay_cost"
        answer = options.find { it[:type] == "pay_mana" } || options.find { it[:type] == "activate_mana" }
      elsif game.pending_decision.kind == "priority"
        return game if answers.empty? && stop.call(game)

        answer = { type: "pass" }
      elsif options.include?({ type: "done" }) then answer = { type: "done" }
      else raise "no answer for #{game.pending_decision.kind} #{options}"
      end
      game.submit(answer)
    end
    raise "drive did not settle: answers left #{answers}"
  end

  def play(game, option, *answers, stop: ->(g) { g.state.stack.empty? })
    game.submit(option)
    drive(game, answers, stop: stop)
  end

  def cast(game, card, *answers, player: "alice", **extra)
    play(game, { type: "cast", object: id(game, card, zone: :hand, player: player), **extra }, *answers)
  end

  def to_step(game, step, *answers) = drive(game, answers, stop: ->(g) { g.step == step && g.state.stack.empty? })

  describe "Sin, Spira's Punishment: repeat this process (CR 608.2c)" do
    it "exiles permanent cards at random and copies each tapped, repeating while the exiled card is a land" do
      game = board(alice: { hand: ["Sin, Spira's Punishment"], graveyard: ["Island", "Forest", "Lightning Bolt"] })
      cast(game, "Sin, Spira's Punishment")
      expect(names(game, "alice", :exile)).to contain_exactly("island", "forest")
      expect(names(game, "alice", :graveyard)).to eq(["lightning_bolt"]) # not a permanent card: the third pass exiles nothing
      copies = tokens(game, "alice")
      expect(copies.map { engine(game).chars(it).name }).to contain_exactly("Island", "Forest")
      expect(copies.map(&:tapped)).to eq([true, true])
    end

    it "stops after a nonland card; a pass sees only its own results" do
      game = board(alice: { hand: ["Sin, Spira's Punishment"], graveyard: ["Grizzly Bears"] })
      cast(game, "Sin, Spira's Punishment")
      expect(names(game, "alice", :exile)).to eq(["grizzly_bears"])
      expect(tokens(game, "alice").map { engine(game).chars(it).name }).to eq(["Grizzly Bears"])
    end

    it "with an empty graveyard does nothing" do
      game = board(alice: { hand: ["Sin, Spira's Punishment"] })
      cast(game, "Sin, Spira's Punishment")
      expect(tokens(game, "alice")).to be_empty
    end
  end

  describe "Improvisation Capstone: exile until a total mana value (CR 406.1)" do
    it "exiles until the exiled cards' mana values total 4, then casts any of them free" do
      game = board(alice: { hand: ["Improvisation Capstone"], library: ["Grizzly Bears", "Island", "Hill Giant"] + (["Forest"] * 5) })
      cast(game, "Improvisation Capstone", { type: "cast" }, { type: "cast" })
      expect(names(game, "alice", :battlefield)).to include("grizzly_bears", "hill_giant")
      expect(names(game, "alice", :exile)).to contain_exactly("island", "improvisation_capstone") # paradigm (CR 702.192a)
      expect(game.state.players[0].library.size).to eq(5)
    end

    it "stops when the library runs out" do
      game = board(alice: { hand: ["Improvisation Capstone"], library: ["Island"] })
      cast(game, "Improvisation Capstone")
      expect(names(game, "alice", :exile)).to contain_exactly("island", "improvisation_capstone")
    end
  end

  describe "The Darkness Crystal: a card exiled with this permanent (CR 607.2a)" do
    it "exiles an opponent's dying creature, gains 2 life, and later returns it under your control" do
      game = board(alice: { hand: ["Lightning Bolt"], battlefield: [["The Darkness Crystal"]] },
                   bob: { battlefield: [["Grizzly Bears"]], exile: ["Hill Giant"] })
      cast(game, "Lightning Bolt", { target: id(game, "Grizzly Bears", player: "bob") })
      exiled = id(game, "Grizzly Bears", zone: :exile, player: "bob")
      expect(life(game, "alice")).to eq(22)
      crystal = id(game, "The Darkness Crystal")
      game.submit(type: "activate", object: crystal, ability: "printed:2")
      expect(game.legal_options.filter_map { it[:target] }).to eq([exiled]) # not Hill Giant: not exiled with it
      drive(game, [{ target: exiled }])
      bears = id(game, "Grizzly Bears")
      expect([game.state.object(bears).tapped, game.state.object(bears).counters]).to eq([true, { "+1/+1" => 2 }])
    end

    it "black spells cost {1} less" do
      game = board(alice: { battlefield: [["The Darkness Crystal"]] })
      crystal = engine(game).definition(engine(game).object(id(game, "The Darkness Crystal"))).abilities.first
      expect(crystal.to_s).to eq("B spells you cast cost {1} less")
    end
  end

  describe "Desculpting Blast: if it was attacking (CR 608.2h)" do
    it "returns an attacking creature and creates a Drone" do
      game = board(alice: { hand: ["Desculpting Blast"],
                            battlefield: [["Grizzly Bears", { controlled_since: 1 }], ["Island"], ["Island"]] })
      bears = id(game, "Grizzly Bears")
      to_step(game, :declare_attackers, { type: "attack", object: bears })
      cast(game, "Desculpting Blast", { target: bears })
      expect(names(game, "alice", :hand)).to eq(["grizzly_bears"])
      expect(tokens(game, "alice").map { engine(game).chars(it).name }).to eq(["Drone"])
    end

    it "returns a permanent that isn't attacking without a Drone" do
      game = board(alice: { hand: ["Desculpting Blast"] }, bob: { battlefield: [["Grizzly Bears"]] })
      cast(game, "Desculpting Blast", { target: id(game, "Grizzly Bears", player: "bob") })
      expect(names(game, "bob", :hand)).to eq(["grizzly_bears"])
      expect(tokens(game, "alice")).to be_empty
    end
  end

  describe "Death to Our Enemies: the fourth plan counter (CR 122.6)" do
    it "makes a tapped Treasure and a plan counter per noncreature spell; the fourth sacrifices it for 7 divided damage" do
      game = board(alice: { hand: ["Lightning Bolt"], battlefield: [["Death to Our Enemies", { counters: { "plan" => 3 } }]] },
                   bob: { battlefield: [["Hill Giant"]] })
      giant = id(game, "Hill Giant", player: "bob")
      cast(game, "Lightning Bolt", { target: "player:bob" }, { type: "count", count: 2 }, { target: giant }, { target: "player:bob" },
           { type: "assign", target: giant }, { type: "assign", target: giant },
           *Array.new(3) { { type: "assign", target: "player:bob" } })
      expect(names(game, "alice", :battlefield)).not_to include("death_to_our_enemies")
      expect(names(game, "alice", :graveyard)).to include("death_to_our_enemies")
      expect(tokens(game, "alice").map { [engine(game).chars(it).name, it.tapped] }).to eq([["Treasure", true]])
      expect(life(game, "bob")).to eq(13) # Lightning Bolt's 3, then 4 of the 7
      expect(names(game, "bob", :graveyard)).to eq(["hill_giant"])
    end

    it "the third counter doesn't trigger it" do
      game = board(alice: { hand: ["Lightning Bolt"], battlefield: [["Death to Our Enemies", { counters: { "plan" => 2 } }]] })
      cast(game, "Lightning Bolt", { target: "player:bob" })
      enemies = id(game, "Death to Our Enemies")
      expect(game.state.object(enemies).counters).to eq("plan" => 3)
    end
  end

  describe "Redirect Lightning: change the target (CR 115.7a)" do
    def bolt_at_alice(alice_battlefield)
      game = board(alice: { hand: ["Redirect Lightning"], battlefield: alice_battlefield }, bob: { hand: ["Lightning Bolt"] },
                   active: "bob")
      play(game, { type: "cast", object: id(game, "Lightning Bolt", zone: :hand, player: "bob") }, { target: "player:alice" },
           stop: ->(g) { g.state.priority.zero? })
      game
    end

    it "pays 5 life to move an opponent's Lightning Bolt from its target to another legal one" do
      game = bolt_at_alice([["Grizzly Bears"], ["Mountain"]])
      bears = id(game, "Grizzly Bears")
      bolt = game.state.stack.first
      game.submit(type: "cast", object: id(game, "Redirect Lightning", zone: :hand))
      game.submit(type: "cost_option", option: 0) # pay 5 life (only one Mountain: {2} more is out of reach)
      expect(game.legal_options.filter_map { it[:target] }).to eq([bolt])
      drive(game, [{ target: bolt }], stop: ->(g) { g.state.stack.size == 2 })
      drive(game, [{ target: bears }], stop: ->(g) { g.state.stack.size == 1 })
      expect(game.state.object(bolt).targets).to eq([bears])
      drive(game, [])
      expect(names(game, "alice", :graveyard)).to include("grizzly_bears", "redirect_lightning")
      expect(life(game, "alice")).to eq(15)
    end

    it "a target with no other legal target stays (CR 115.7a)" do
      game = board(alice: { hand: ["Redirect Lightning"], battlefield: [["Grizzly Bears"], ["Mountain"]] },
                   bob: { hand: ["Giant Growth"] }, active: "bob")
      bears = id(game, "Grizzly Bears")
      play(game, { type: "cast", object: id(game, "Giant Growth", zone: :hand, player: "bob") }, { target: bears },
           stop: ->(g) { g.state.priority.zero? })
      growth = game.state.stack.first
      play(game, { type: "cast", object: id(game, "Redirect Lightning", zone: :hand) }, { type: "cost_option", option: 0 },
           { target: growth }, stop: ->(g) { g.state.stack.size == 1 })
      expect(game.state.object(growth).targets).to eq([bears]) # no other creature: no question, nothing changes
    end
  end

  describe "Borg Cube: assimilate a creature card exiled with it (CR 701.72b, 607.2a)" do
    it "exiles a creature as it enters; attacking, it assimilates that card instead of exiling another" do
      game = board(alice: { hand: ["Borg Cube"] }, bob: { battlefield: [["Grizzly Bears"], ["Hill Giant"]] })
      cast(game, "Borg Cube", { target: id(game, "Grizzly Bears", player: "bob") })
      cube = id(game, "Borg Cube")
      expect(Enjine::Mechanics::Linked.exiled_with(engine(game), cube)).to eq([id(game, "Grizzly Bears", zone: :exile, player: "bob")])
      game.state.object(cube).counters["charge"] = 12 # stationed: a 6/6 artifact creature
      game.state.object(cube).controlled_since = 1
      engine(game).touch!
      to_step(game, :declare_attackers, { type: "attack", object: cube }, { target: id(game, "Hill Giant", player: "bob") })
      bears = id(game, "Grizzly Bears")
      chars = engine(game).chars(bears)
      expect([chars.types.sort, chars.subtypes,
              game.state.object(bears).counters]).to eq([%i[artifact creature], [:borg], { "+1/+1" => 1 }])
      expect(names(game, "bob", :battlefield)).to eq(["hill_giant"]) # assimilated, so the target isn't exiled
    end
  end

  describe "meld (CR 713.5c)" do
    it "a melded permanent's mana value is the sum of its front faces'; the second card leaves exile too" do
      game = board(alice: { battlefield: [["Vanille, Cheerful l'Cie"], ["Fang, Fearless l'Cie"]] })
      e = engine(game)
      exiled = [id(game, "Vanille, Cheerful l'Cie"), id(game, "Fang, Fearless l'Cie")].map { e.move!(it, :exile, reason: "spec") }
      events = []
      allow(e).to(receive(:emit).and_wrap_original { |emit, event| (events << event.to_h) && emit.call(event) })
      melded = e.meld!(*exiled, 0)
      expect(Enjine::Mechanics::Amount.mana_value(e, melded)).to eq(7) # {3}{G} + {2}{B}
      expect(events.map { it.slice("from", "to", "reason", "new_id") }).to eq(
        [{ "from" => "exile", "to" => "battlefield", "reason" => "meld", "new_id" => melded.id },
         { "from" => "exile", "to" => "battlefield", "reason" => "meld", "new_id" => nil }]
      )
      big = Enjine::Mechanics.build_entry(:filter, { "permanent" => { "mana_value" => { "at_least" => 7 } } }, [], "spec")
      expect(big.candidates(e, 0)).to eq([melded.id])
    end
  end

  describe "hideaway (CR 702.75a)" do
    it "the player who controls the permanent may look at the hidden card and play it" do
      game = board(alice: { hand: ["Clive's Hideaway"], library: ["Hill Giant"] + (["Forest"] * 9) })
      play(game, { type: "play_land", object: id(game, "Clive's Hideaway", zone: :hand) }, { type: "take" })
      hidden = game.state.exile.first
      expect(game.view_for("bob")["exile"].first["card"]).to be_nil
      engine(game).gain_control!(game.state.object(id(game, "Clive's Hideaway")), 1)
      expect(game.view_for("bob")["exile"].first["card"]).to eq("hill_giant")
      expect(game.view_for("alice")["exile"].first["card"]).to be_nil
      expect(engine(game).may_look?(game.state.object(hidden), 1)).to be(true)
      engine(game).move!(id(game, "Clive's Hideaway", player: "bob"), :graveyard, reason: "spec")
      expect(engine(game).may_look?(game.state.object(hidden), 0)).to be(true) # gone: whoever exiled it
    end
  end

  describe "earthbend (CR 701.66a, 603.7c)" do
    it "the return trigger ends when the land leaves for another zone, and still returns a land that dies" do
      game = board(alice: { hand: ["Earthbending Lesson", "Earthbending Lesson"], battlefield: [["Forest"], ["Island"]] })
      cast(game, "Earthbending Lesson", { target: id(game, "Forest") })
      cast(game, "Earthbending Lesson", { target: id(game, "Island") })
      expect(game.state.delayed_triggers.size).to eq(2)
      engine(game).move!(id(game, "Forest"), :hand, reason: "spec")
      expect(game.state.delayed_triggers.size).to eq(1)
      engine(game).move!(id(game, "Island"), :graveyard, reason: "destroy")
      drive(game, [{ type: "pass" }]) # the delayed trigger goes on the stack and resolves
      expect(game.state.delayed_triggers).to be_empty
      expect(game.state.object(id(game, "Island")).tapped).to be(true)
    end
  end
end
