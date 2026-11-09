# frozen_string_literal: true

# Set mechanics of current Standard: power-up (CR 702.193), teamwork (702.194), increment (702.191), extort
# (702.101), boast (702.142), colors among permanents (105.2) and domain (305.6).
RSpec.describe "Set mechanics: power-up, teamwork, increment, extort, boast, colors among, domain" do
  let(:brawler) do
    { "name" => "Spec Brave Brawler", "mana_cost" => "{1}{W}", "types" => ["creature"], "power" => 2, "toughness" => 1,
      "abilities" => [{ "activated" => { "power_up" => true, "cost" => [{ "mana" => "{4}{W}" }],
                                         "effects" => [{ "add_counters" => { "counter" => "+1/+1", "amount" => 2,
                                                                             "to" => "self" } }] } }] }
  end
  let(:showoff) do
    { "name" => "Spec Show-Off", "mana_cost" => "{R}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "activated" => { "boast" => true, "cost" => [{ "mana" => "{1}" }],
                                         "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
  end
  let(:augmenter) do
    { "name" => "Spec Augmenter", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 1, "toughness" => 3,
      "keywords" => ["increment"] }
  end
  let(:extortionist) do
    { "name" => "Spec Extortionist", "mana_cost" => "{1}{B}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "keywords" => ["extort"] }
  end
  let(:lens) do
    { "name" => "Spec Prism Lens", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "activated" => { "cost" => ["tap"], "effects" => [
        { "gain_life" => { "amount" => { "distinct_colors" => { "each" => "permanent", "controller" => "you" } } } }
      ] } },
                      { "activated" => { "cost" => [{ "mana" => "{1}" }], "effects" => [
                        { "lose_life" => { "to" => "each_opponent",
                                           "amount" => { "distinct_land_types" => { "each" => "land", "controller" => "you" } } } }
                      ] } }] }
  end
  let(:azorius) do
    { "name" => "Spec Azorius Envoy", "mana_cost" => "{W}{U}", "types" => ["creature"], "power" => 2, "toughness" => 2 }
  end
  let(:ford) { { "name" => "Spec Verdant Ford", "types" => ["land"], "subtypes" => %w[forest island] } }
  let(:team_charge) do
    { "name" => "Spec Team Charge", "mana_cost" => "{R}", "types" => ["sorcery"],
      "abilities" => [{ "teamwork" => { "power" => 3 } },
                      { "spell" => { "choose" => 1,
                                     "choose_if" => { "if" => { "cast_with" => "teamwork" }, "choose" => 2 },
                                     "modes" => [{ "effects" => [{ "gain_life" => { "amount" => 3 } }] },
                                                 { "effects" => [{ "draw" => { "amount" => 1 } }] }] } }] }
  end
  let(:team_exile) do
    { "name" => "Spec Team Exile", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "teamwork" => { "power" => 2 } },
                      { "spell" => { "targets" => [{ "creature" => { "power" => { "at_most" => 1 } } }],
                                     "kicked_targets" => ["creature"],
                                     "effects" => [{ "exile" => { "to" => { "target" => 0 } } },
                                                   { "gain_life" => { "amount" => 3, "if" => { "cast_with" => "teamwork" } } }] } }] }
  end
  let(:catalog) { catalog_with(brawler, showoff, augmenter, extortionist, lens, azorius, ford, team_charge, team_exile) }

  def engine(game) = game.instance_variable_get(:@engine)

  def errors_for(card)
    Enjine::CardDefinition.from_h(card)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def life(game, name) = game.state.players[game.names.index(name)].life

  def board(alice: [], hand: [], bob: [], mana: {})
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: mana) do
        alice.each { |card, opts| battlefield card, **(opts || {}) }
        hand(*hand)
        library "Forest", count: 5
      end
      player("bob") do
        bob.each { battlefield it }
        library "Forest", count: 5
      end
    end
  end

  # Answers decisions in order (an option or a block on the game), pays mana from the pool, resolves the stack.
  def play(game, action, *answers)
    game.submit(action) if action
    until (decision = game.pending_decision).kind == "priority" && game.state.stack.empty?
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

  def cast(game, card, *)
    play(game, { type: "cast", object: ids_in(game, "alice", :hand).find { game.state.object(it).card == slug(card) } }, *)
  end

  def slug(card) = Enjine::CardDefinition.slug(card)

  describe "power-up (CR 702.193)" do
    def total(game, id)
      ability = engine(game).chars(engine(game).object(id)).ability("printed:0")
      engine(game).total_cost(0, ability.mana_cost, ability: ability, source: id).to_s
    end

    it "costs its full cost unless the permanent entered this turn, and activates only once (CR 702.193a)" do
      game = board(alice: [["Spec Brave Brawler"]], mana: { W: 1, C: 4 })
      brawler = obj_id(game, "Spec Brave Brawler")
      expect(total(game, brawler)).to eq("{4}{W}")
      option = { type: "activate", object: brawler, ability: "printed:0" }
      play(game, option)
      expect(game.state.object(brawler).counters["+1/+1"]).to eq(2)
      expect(game.legal_options).not_to include(option)
    end

    it "is reduced by the permanent's mana cost the turn it entered: colored first, then generic (CR 702.193b)" do
      game = board(hand: ["Spec Brave Brawler"], mana: { W: 1, C: 5 })
      cast(game, "Spec Brave Brawler")
      brawler = obj_id(game, "Spec Brave Brawler")
      expect(total(game, brawler)).to eq("{3}")
      play(game, { type: "activate", object: brawler, ability: "printed:0" })
      expect(game.state.object(brawler).counters["+1/+1"]).to eq(2)
      expect(game.state.players[0].mana_pool[:C]).to eq(1)
    end

    it "reduces colored mana the cost doesn't need, hybrid and colorless by CR 118.7b-e" do
      reduce = ->(cost, by) { Enjine::Mechanics::Keywords::PowerUp.reduce(Enjine::Mana::Cost.parse(cost), Enjine::Mana::Cost.parse(by)).to_s }
      expect(reduce.call("{5}{R/G}{R/G}", "{3}{R/G}")).to eq("{2}{R/G}")
      expect(reduce.call("{4}{W}", "{W}{W}")).to eq("{3}")
      expect(reduce.call("{2}{C}", "{C}{C}{U}")).to eq("{0}")
      expect(reduce.call("{1}{G}", "{1}{R/W}")).to eq("{G}")
    end

    it "reads like the card and rejects exhaust with it" do
      expect(catalog.fetch("spec_brave_brawler").abilities.first.to_s).to start_with("Power-up — ")
      errors = errors_for(brawler.merge("abilities" => [{ "activated" => {
                                          "power_up" => true, "exhaust" => true, "cost" => [{ "mana" => "{1}" }],
                                          "effects" => [{ "draw" => { "amount" => 1 } }]
                                        } }]))
      expect(errors).to include("abilities[0].activated: exhaust and power_up can't be used together")
    end
  end

  describe "boast (CR 702.142a)" do
    it "can be activated only if the creature attacked this turn, and only once each turn" do
      game = board(alice: [["Spec Show-Off"]], mana: { C: 2 })
      showoff = obj_id(game, "Spec Show-Off")
      option = { type: "activate", object: showoff, ability: "printed:0" }
      expect(game.legal_options).not_to include(option)
      game = board(alice: [["Spec Show-Off"]], mana: { C: 2 })
      engine(game).object(showoff).memory["attacked"] = { "turn" => 3, "count" => 1 } # it attacked this turn
      game = Enjine::Game.import({ "state" => game.state.to_h }, catalog: catalog)
      expect(game.legal_options).to include(option)
      play(game, option)
      expect(game.state.players[0].hand.size).to eq(1)
      expect(game.legal_options).not_to include(option)
      expect(catalog.fetch("spec_show_off").abilities.first.to_s).to start_with("Boast — ")
    end

    it "can't also have a limit" do
      errors = errors_for(showoff.merge("abilities" => [{ "activated" => {
                                          "boast" => true, "limit" => "once_each_turn", "cost" => [{ "mana" => "{1}" }],
                                          "effects" => [{ "draw" => { "amount" => 1 } }]
                                        } }]))
      expect(errors).to include("abilities[0].activated.boast: can't be combined with limit")
    end
  end

  describe "increment (CR 702.191a)" do
    it "puts a +1/+1 counter on it when more mana was spent on a spell than its power or toughness" do
      game = board(alice: [["Spec Augmenter"]], hand: ["Lightning Bolt", "Hill Giant"], mana: { R: 2, C: 3 })
      augmenter = obj_id(game, "Spec Augmenter")
      cast(game, "Lightning Bolt", { type: "target", target: "player:bob" }) # 1 mana: not more than 1 or 3
      expect(game.state.object(augmenter).counters["+1/+1"].to_i).to eq(0)
      cast(game, "Hill Giant") # 4 mana
      expect(game.state.object(augmenter).counters["+1/+1"]).to eq(1)
    end
  end

  describe "extort (CR 702.101a)" do
    it "may pay {W/B} as you cast a spell: each opponent loses 1 life and you gain that much" do
      game = board(alice: [["Spec Extortionist"]], hand: ["Lightning Bolt"], mana: { R: 1, B: 1 })
      cast(game, "Lightning Bolt", { type: "target", target: "player:bob" }, { type: "pay" })
      expect(life(game, "bob")).to eq(16)
      expect(life(game, "alice")).to eq(21)
    end

    it "does nothing when declined" do
      game = board(alice: [["Spec Extortionist"]], hand: ["Lightning Bolt"], mana: { R: 1, B: 1 })
      cast(game, "Lightning Bolt", { type: "target", target: "player:bob" }, { type: "decline" })
      expect([life(game, "bob"), life(game, "alice")]).to eq([17, 20])
    end
  end

  describe "colors among permanents and domain (CR 105.2, 305.6)" do
    it "counts the colors among permanents you control and the basic land types among your lands" do
      game = board(alice: [["Spec Prism Lens"], ["Spec Azorius Envoy"], ["Grizzly Bears"], ["Spec Verdant Ford"],
                           ["Forest"], ["Mountain"]], mana: { C: 1 })
      lens = obj_id(game, "Spec Prism Lens")
      play(game, { type: "activate", object: lens, ability: "printed:0" })
      expect(life(game, "alice")).to eq(23) # white, blue, green
      play(game, { type: "activate", object: lens, ability: "printed:1" })
      expect(life(game, "bob")).to eq(17) # forest, island, mountain
    end
  end

  describe "teamwork (CR 702.194)" do
    it "taps creatures with total power N or more as an optional additional cost; cast using teamwork, choose both" do
      game = board(alice: [["Grizzly Bears"], ["Spec Augmenter"]], hand: ["Spec Team Charge"], mana: { R: 1 })
      bears = obj_id(game, "Grizzly Bears")
      augmenter = obj_id(game, "Spec Augmenter")
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      expect(game.pending_decision.kind).to eq("choose_kicker")
      game.submit(type: "kick")
      expect(game.pending_decision.kind).to eq("choose_mode")
      game.submit(type: "mode", mode: 0)
      game.submit(type: "mode", mode: 1)
      expect(game.pending_decision.kind).to eq("choose_cost")
      game.submit(type: "cost", object: bears)
      expect(game.legal_options).not_to include(type: "done") # power 2 of 3
      game.submit(type: "cost", object: augmenter)
      play(game, nil)
      expect(game.state.object(bears).tapped && game.state.object(augmenter).tapped).to be(true)
      expect(life(game, "alice")).to eq(23)
      expect(game.state.players[0].hand.size).to eq(1)
    end

    it "isn't offered without enough power, and uses the teamwork targets only when used (CR 702.194c)" do
      game = board(alice: [["Grizzly Bears"]], hand: ["Spec Team Exile"], bob: ["Hill Giant"], mana: { B: 1 })
      giant = obj_id(game, "Hill Giant")
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(type: "kick")
      expect(game.legal_options).to include(type: "target", target: giant)
      game.submit(type: "target", target: giant)
      game.submit(type: "cost", object: obj_id(game, "Grizzly Bears"))
      play(game, nil)
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["hill_giant"])
      expect(life(game, "alice")).to eq(23)

      weak = board(alice: [["Spec Augmenter"]], hand: ["Spec Team Exile"], bob: ["Hill Giant"], mana: { B: 1 })
      weak.submit(type: "cast", object: ids_in(weak, "alice", :hand).first)
      expect(weak.legal_options.map { it[:type] }).not_to include("kick")
    end

    it "reads like the card and validates its power" do
      expect(catalog.fetch("spec_team_charge").abilities.first.to_s).to eq("Teamwork 3")
      errors = errors_for(team_charge.merge("abilities" => [{ "teamwork" => { "power" => 0 } }]))
      expect(errors.join).to include("abilities[0].teamwork.power")
      errors = errors_for(team_charge.merge("abilities" => [
                                              { "spell" => { "effects" => [{ "draw" => { "amount" => 1,
                                                                                         "if" => { "cast_with" => "gift_of_gab" } } }] } }
                                            ]))
      expect(errors.join).to include("cast_with: must be one of")
    end
  end

  describe "tiered (CR 702.183a)" do
    it "allows a cost on a spell's modes only, as a mana cost" do
      mode = ->(cost) { { "cost" => cost, "effects" => [{ "draw" => { "amount" => 1 } }] } }
      spell = { "name" => "Spec Tiers", "mana_cost" => "{U}", "types" => ["instant"],
                "abilities" => [{ "spell" => { "modes" => [mode.call("{0}"), mode.call("{2}{U}")] } }] }
      expect(errors_for(spell)).to eq([])
      bad = spell.merge("abilities" => [{ "spell" => { "modes" => [mode.call("{0}"), mode.call("2")] } }])
      expect(errors_for(bad).join).to include("modes[1].cost")
      ability = { "activated" => { "cost" => [{ "mana" => "{1}" }], "modes" => [mode.call("{0}"), mode.call("{1}")] } }
      expect(errors_for(brawler.merge("abilities" => [ability])).join).to include("modes[0]: unknown parameter \"cost\"")
    end
  end

  describe "storied and the enduring story designation (CR 702.195)" do
    let(:bard) do
      { "name" => "Spec Story Bard", "mana_cost" => "{1}{R}", "types" => ["creature"], "supertypes" => ["legendary"],
        "power" => 2, "toughness" => 2, "keywords" => ["storied"],
        "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{1}" }], "only_if" => { "designation" => "enduring_story" },
                                           "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
    end
    let(:relic) { { "name" => "Spec Old Relic", "mana_cost" => "{1}", "types" => ["artifact"] } }
    let(:saga) do
      { "name" => "Spec Short Saga", "mana_cost" => "{1}", "types" => ["enchantment"], "subtypes" => ["saga"],
        "abilities" => [{ "chapter" => { "chapter" => 1, "effects" => [{ "gain_life" => { "amount" => 1 } }] } },
                        { "chapter" => { "chapter" => 2, "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
    end
    let(:catalog) { catalog_with(bard, relic, saga) }

    def story_board(alice, hand: [])
      build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { C: 3 }) do
          alice.each { battlefield it }
          hand(*hand)
          library "Forest", count: 5
        end
        player("bob") { library "Forest", count: 5 }
      end
    end

    it "you get an enduring story once you control three artifacts, Sagas and/or legendaries, for the rest of the game" do
      game = story_board(["Spec Story Bard", "Spec Old Relic"], hand: ["Spec Short Saga"])
      bard_id = obj_id(game, "Spec Story Bard")
      option = { type: "activate", object: bard_id, ability: "printed:0" }
      expect(game.legal_options).not_to include(option)
      play(game, { type: "cast", object: ids_in(game, "alice", :hand).first })
      expect(engine(game).designation?(0, "enduring_story")).to be(true)
      expect(game.history.flat_map(&:events).map(&:type)).to include("designation_gained")
      engine(game).move!(obj_id(game, "Spec Old Relic"), :graveyard, reason: "test")
      game = Enjine::Game.import(game.export, catalog: catalog) # it round-trips
      expect(engine(game).designation?(0, "enduring_story")).to be(true)
      expect(game.legal_options).to include(option)
    end

    it "needs a storied permanent and three pieces" do
      without = story_board(["Spec Old Relic", "Spec Old Relic", "Spec Short Saga"])
      expect(engine(without).tell_enduring_stories!).to be(false)
      two = story_board(["Spec Story Bard", "Spec Old Relic"])
      expect(engine(two).tell_enduring_stories!).to be(false)
    end

    it "validates the designation in card data and in snapshots" do
      bad = bard.merge("abilities" => [{ "static" => { "affects" => "self", "if" => { "designation" => "monarch" },
                                                       "pump" => { "power" => 1, "toughness" => 0 } } }])
      expect(errors_for(bad).join).to include("if.designation: must be one of enduring_story")
      game = story_board(["Spec Old Relic"])
      data = JSON.parse(game.export).tap { it["state"]["players"][0]["designations"] = %w[enduring_story enduring_story] }
      expect { Enjine::Game.import(data, catalog: catalog) }.to raise_error(Enjine::InvalidSnapshot, /designations: must be a list/)
    end
  end
end
