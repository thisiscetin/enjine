# frozen_string_literal: true

# Real cards that need endure with a computed N, proliferate X times, paradigm, foretell, hideaway, suspend,
# devour and meld (spec/fixtures/cards/real/exile_and_meld_mechanics.json). Basic lands and the planeswalkers
# come from the other real-card files.
RSpec.describe "Real cards: exile, suspend and meld mechanics" do
  let(:catalog) { Enjine::Catalog.from_definitions(CardFixtures.real_cards) }

  def board(hand: [], battlefield: [], theirs: [], mana: {}, step: :precombat_main, library: ["Island"])
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana) do
        hand(*hand)
        library(*library, count: 10)
        battlefield.each { |entry| entry.is_a?(Array) ? battlefield(entry[0], **entry[1]) : battlefield(entry) }
      end
      player("bob") do
        library "Swamp", count: 10
        theirs.each { battlefield it }
      end
    end
  end

  # Submits `action`, then answers decisions in order until the stack is empty and alice has priority.
  def play(game, action, *answers)
    game.submit(action) if action
    until (decision = game.pending_decision).kind == "priority" && game.state.stack.empty?
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { %w[pay_mana activate_mana].include?(it[:type]) } || raise("can't pay"))
      else
        answer = answers.shift || raise("no answer for #{decision.kind}: #{game.legal_options}")
        game.submit(answer.respond_to?(:call) ? answer.call(game) : answer) # a block: an object made meanwhile
      end
    end
    expect(answers).to be_empty
    game
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def hand_id(game, card) = ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) }
  def spirits(game) = game.state.battlefield.select { game.state.object(it).card.start_with?("spirit_token") }
  def stats(game, id) = [engine(game).power(engine(game).object(id)), engine(game).toughness(engine(game).object(id))]

  describe "endure with a computed N (CR 701.63a)" do
    it "Krumar Initiate: endures X, paying X life; the Spirit is X/X" do
      game = board(battlefield: ["Krumar Initiate"], mana: { B: 1, C: 3 })
      krumar = obj_id(game, "Krumar Initiate")
      play(game, { type: "activate", object: krumar, ability: "printed:0" }, { type: "x", value: 3 }, { type: "spirit" })
      expect(game.state.players[0].life).to eq(17)
      expect(stats(game, spirits(game).first)).to eq([3, 3])
    end

    it "Warden of the Grove: another nontoken creature entering endures the number of counters on the Warden" do
      game = board(battlefield: [["Warden of the Grove", { counters: { "+1/+1" => 2 } }]], hand: ["Krumar Initiate"], mana: { B: 1, C: 1 })
      play(game, { type: "cast", object: hand_id(game, "Krumar Initiate") },
           ->(g) { { type: "counters", object: obj_id(g, "Krumar Initiate") } })
      expect(game.state.object(obj_id(game, "Krumar Initiate")).counters["+1/+1"]).to eq(2)
    end
  end

  describe "paradigm (CR 702.192a)" do
    def bob_ref(_game) = "player:bob"

    it "Decorum Dissertation: exiled as it resolves; each of your precombat main phases you may cast a free copy" do
      game = board(hand: ["Decorum Dissertation"], mana: { B: 2, C: 3 })
      card = hand_id(game, "Decorum Dissertation")
      play(game, { type: "cast", object: card }, { type: "target", target: bob_ref(game) })
      expect(game.state.players[1].life).to eq(18)
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["decorum_dissertation"])
      expect(game.state.delayed_triggers.size).to eq(1)

      skip_to(game, :precombat_main, turn: 5)
      until game.legal_options.any? { it[:type] == "cast" && it[:object].to_s != card }
        game.submit(game.legal_options.find { it[:type] == "pass" } || game.legal_options.first)
      end
      copy = game.legal_options.find { it[:type] == "cast" }[:object]
      expect(game.state.object(copy).memory["copy"]).to eq("card")
      play(game, { type: "cast", object: copy }, { type: "target", target: bob_ref(game) })
      expect(game.state.players[1].life).to eq(16)
      expect(game.state.exile.size).to eq(1) # the copy ceased to exist; the card stays
      expect(game.state.delayed_triggers.size).to eq(1) # not the first time any more
    end

    it "Germination Practicum: a copy declined is gone; the trigger comes back next turn" do
      game = board(hand: ["Germination Practicum"], battlefield: ["Krumar Initiate"], mana: { G: 2, C: 3 })
      play(game, { type: "cast", object: hand_id(game, "Germination Practicum") })
      krumar = obj_id(game, "Krumar Initiate")
      expect(game.state.object(krumar).counters["+1/+1"]).to eq(2)
      skip_to(game, :precombat_main, turn: 5)
      game.submit(type: "pass") until game.pending_decision.kind == "effect_choice"
      play(game, nil, { type: "done" })
      expect(game.state.exile.size).to eq(1)
      expect(game.state.object(krumar).counters["+1/+1"]).to eq(2)
      expect(Enjine::Game.import(game.export, catalog: catalog).state.delayed_triggers.size).to eq(1) # round-trips
    end
  end

  describe "hideaway (CR 702.75a)" do
    let(:legends) { ["Tam, the Possibility", "The Kingpin of Crime", "Swarm, Being of Bees"] }

    def hide(game)
      play(game, { type: "play_land", object: hand_id(game, "Clive's Hideaway") }, ->(g) { g.legal_options.find { it[:type] == "take" } })
      { type: "activate", object: obj_id(game, "Clive's Hideaway"), ability: "printed:2" }
    end

    it "Clive's Hideaway: exiles one of the top four face down; with four legendary creatures you may play it free" do
      game = board(hand: ["Clive's Hideaway"], battlefield: legends + ["Spider-Man, Web-Slinger"], library: ["Krumar Initiate"],
                   mana: { C: 2 })
      activate = hide(game)
      hidden = game.state.exile.first
      expect(game.state.object(hidden).memory).to include("face_down" => true, "may_look" => [0])
      expect(game.state.players[0].library.size).to eq(9)
      expect(game.view_for("bob")["exile"].first["card"]).to be_nil # only alice may look at it (CR 406.3)
      play(game, activate, ->(g) { g.legal_options.find { it[:type] == "cast" } }, { type: "decline" }) # extort
      expect(game.state.exile).to be_empty
      expect(obj_id(game, "Krumar Initiate")).not_to be_nil
    end

    it "Clive's Hideaway: with three legendary creatures nothing happens" do
      game = board(hand: ["Clive's Hideaway"], battlefield: legends, library: ["Krumar Initiate"], mana: { C: 2 })
      play(game, hide(game))
      expect(game.state.exile.size).to eq(1)
    end
  end

  describe "foretell (CR 702.143a)" do
    it "Sozin's Comet: foretold for {2} face down, cast on a later turn for {2}{R}; creatures gain firebending 5" do
      game = board(hand: ["Sozin's Comet"], battlefield: ["Krumar Initiate"] + (["Mountain"] * 3), mana: { C: 2 })
      comet = hand_id(game, "Sozin's Comet")
      foretell = game.legal_options.find { it[:type] == "special_action" }
      expect(foretell).to eq(type: "special_action", object: comet, ability: "printed:1")
      play(game, foretell)
      exiled = game.state.exile.first
      expect(game.state.object(exiled).memory).to include("face_down" => true, "foretold" => 3)
      expect(game.view_for("bob")["exile"].first["card"]).to be_nil
      expect(game.legal_options.select { it[:type] == "cast" }).to be_empty # not the turn it was foretold

      skip_to(game, :precombat_main, turn: 5)
      cast = game.legal_options.find { it[:type] == "cast" && it[:object] == exiled }
      expect(cast[:via]).to eq("alt:printed:1")
      play(game, cast)
      krumar = obj_id(game, "Krumar Initiate")
      expect(engine(game).chars(engine(game).object(krumar)).abilities.map { it.ability.to_s }).to include("Firebending 5")
      expect(game.state.players[0].mana_pool.values.sum).to eq(0)
    end
  end

  describe "suspend (CR 702.62a)" do
    it "Taigam, Master Opportunist: the second spell is copied and suspended with four time counters; cast free with haste" do
      game = board(hand: ["Krumar Initiate"] * 2, battlefield: ["Taigam, Master Opportunist"], mana: { B: 4 })
      cast = -> { play(game, { type: "cast", object: hand_id(game, "Krumar Initiate") }) }
      cast.call
      cast.call
      expect(game.state.battlefield.count { game.state.object(it).card == "krumar_initiate" }).to eq(2) # the first, the copy
      suspended = game.state.exile.first
      expect(game.state.object(suspended).counters).to eq("time" => 4)
      expect(game.state.object(suspended).memory["suspend"]).to be(true)

      skip_to(game, :draw, turn: 9)
      expect(game.state.object(suspended).counters).to eq("time" => 1)
      skip_to(game, :upkeep, turn: 11)
      game.submit(type: "pass") until game.pending_decision.kind == "effect_choice"
      expect(game.legal_options).to eq([{ type: "cast", object: suspended }, { type: "done" }])
      play(game, { type: "cast", object: suspended })
      krumar = game.state.battlefield.find { (o = game.state.object(it)).card == "krumar_initiate" && o.controlled_since == 11 }
      expect(engine(game).chars(engine(game).object(krumar)).keyword?(:haste)).to be(true)
      expect(game.state.exile).to be_empty
    end
  end

  describe "devour (CR 702.82c)" do
    it "Famished Worldsire: devours two lands for six +1/+1 counters, then looks at the top six" do
      game = board(hand: ["Famished Worldsire"], battlefield: ["Forest"] * 3, mana: { G: 3, C: 5 })
      lands = game.state.battlefield.dup
      game.submit(type: "cast", object: hand_id(game, "Famished Worldsire"))
      game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
      game.submit(type: "pass") until game.pending_decision.kind == "enter_choice"
      expect(game.legal_options).to eq(lands.map { { type: "devour", object: it } } + [{ type: "done" }])
      game.submit(type: "devour", object: lands[0])
      expect(game.legal_options).to eq(lands.drop(1).map { { type: "devour", object: it } } + [{ type: "done" }])
      play(game, { type: "devour", object: lands[1] }, { type: "done" }, ->(g) { g.legal_options.last })
      worldsire = obj_id(game, "Famished Worldsire")
      expect(stats(game, worldsire)).to eq([6, 6])
      expect(game.state.object(worldsire).memory["devoured"]).to eq(2)
      expect(game.state.players[0].graveyard.size).to eq(2)
    end

    it "Famished Worldsire: devouring nothing, it's a 0/0 and dies" do
      game = board(hand: ["Famished Worldsire"], battlefield: ["Forest"], mana: { G: 3, C: 5 })
      play(game, { type: "cast", object: hand_id(game, "Famished Worldsire") }, { type: "done" })
      expect(game.state.players[0].graveyard.map { game.state.object(it).card }).to eq(["famished_worldsire"])
    end
  end

  describe "proliferate X times (CR 701.34a)" do
    it "Tam, the Possibility: proliferates once per planeswalker type among your planeswalkers" do
      game = board(battlefield: ["Tam, the Possibility", "Ajani Resolute", "Ajani, Outland Chaperone", "The Theorist, Jace Beleren"],
                   mana: { W: 1, U: 1, B: 1, R: 1, G: 1 })
      jace = obj_id(game, "The Theorist, Jace Beleren")
      done = { type: "done" }
      play(game, { type: "activate", object: obj_id(game, "Tam, the Possibility"), ability: "printed:1" },
           { type: "choose", object: jace }, done, { type: "choose", object: jace }, done)
      expect(game.state.object(jace).counters["loyalty"]).to eq(5)
    end
  end
end
