# frozen_string_literal: true

RSpec.describe "Losing all abilities and granted activated abilities (CR 613.1f, 613.7, 613.8a, 611.2b)" do
  def creature(name, power, toughness, extra = {})
    { "name" => name, "mana_cost" => "{1}", "types" => ["creature"], "power" => power, "toughness" => toughness }.merge(extra)
  end

  let(:catalog) do
    catalog_with(
      creature("Sky Herald", 2, 2, "keywords" => ["flying"], "colors" => ["W"], "subtypes" => ["bird"]),
      creature("Herald Captain", 2, 2, "abilities" => [{ "static" => { "affects" => { "each" => "creature", "controller" => "you",
                                                                                      "other" => true },
                                                                       "pump" => { "power" => 1, "toughness" => 1 } } }]),
      creature("Pyre Imp", 1, 1, "abilities" => [{ "triggered" => { "when" => { "dies" => {} },
                                                                    "effects" => [{ "deal_damage" => { "amount" => 2,
                                                                                                       "to" => "each_opponent" } }] } }]),
      creature("Swarm Measure", { "count" => { "each" => "creature", "controller" => "you" } },
               { "count" => { "each" => "creature", "controller" => "you" } }),
      { "name" => "Wing Gift", "mana_cost" => "{W}", "types" => ["instant"],
        "abilities" => [{ "spell" => { "targets" => ["creature"],
                                       "effects" => [{ "grant" => { "keywords" => ["lifelink"], "to" => { "target" => 0 } } }] } }] },
      { "name" => "Blackout Purge", "mana_cost" => "{B}", "types" => ["sorcery"],
        "abilities" => [{ "spell" => { "effects" => [
          { "become" => { "loses_abilities" => true, "to" => { "each" => "creature" } } },
          { "destroy" => { "to" => { "each" => "creature" } } }
        ] } }] }
    )
  end

  def board(hand: [], mine: [], theirs: [], mana: { U: 3, W: 2, B: 2 })
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: mana) do
        hand(*hand)
        mine.each { |card, opts| battlefield card, **(opts || {}) }
        library "Island", count: 10
      end
      player("bob") do
        theirs.each { |card, opts| battlefield card, **(opts || {}) }
        library "Island", count: 10
      end
    end
  end

  def play(game, action, *answers)
    game.submit(action)
    until game.over? || ((decision = game.pending_decision).kind == "priority" && game.state.stack.empty?)
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { it[:type] == "pay_mana" } || raise("can't pay"))
      else game.submit(answers.shift || raise("no answer for #{decision.kind}: #{game.legal_options}"))
      end
    end
    game
  end

  def cast(game, card, *) = play(game, { type: "cast", object: obj_id(game, card, zone: :hand, player: "alice") }, *)
  def chars(game, id) = Enjine::Engine.new(game.catalog, game.state) { nil }.chars(id)

  it "an Aura's static: loses all abilities, is a colorless Frog with base 1/1; counters still count (CR 613.1f, 613.4b-c)" do
    game = board(hand: ["Hushing Bubble"], theirs: [["Sky Herald", { counters: { "+1/+1" => 1 } }]])
    herald = obj_id(game, "Sky Herald")
    cast(game, "Hushing Bubble", { type: "target", target: herald })
    c = chars(game, herald)
    expect([c.keywords, c.colors, c.subtypes, c.power, c.toughness]).to eq([[], [], [:frog], 2, 2])
    expect(Enjine::Game.import(game.export, catalog: catalog).state.to_h).to eq(game.state.to_h)
  end

  it "a removal until end of turn takes what it had; a keyword counter put on later stays (CR 613.7b-c, 122.1b)" do
    game = board(hand: ["Quieting Word"], theirs: ["Sky Herald"])
    herald = obj_id(game, "Sky Herald")
    cast(game, "Quieting Word", { type: "target", target: herald })
    expect(chars(game, herald).keywords).to eq([:flying])
    expect(game.state.effects.map { it["kind"] }).to eq(["lose_abilities"])
    expect(game.state.object(herald).memory["counter_timestamps"]).to eq("flying" => game.state.effects.first["timestamp"] + 1)
    skip_to(game, :upkeep, turn: 4)
    expect(game.state.effects).to be_empty
    expect(chars(game, herald).keywords).to eq([:flying])
  end

  it "a removal applied after a grant takes it away; a grant after the removal stays (CR 613.7)" do
    game = board(hand: ["Quieting Word", "Wing Gift", "Wing Gift"], mine: ["Sky Herald"])
    herald = obj_id(game, "Sky Herald")
    first, second = ids_in(game, "alice", :hand).select { game.state.object(it).card == "wing_gift" }
    play(game, { type: "cast", object: first }, { type: "target", target: herald })
    cast(game, "Quieting Word", { type: "target", target: herald })
    expect(chars(game, herald).keywords).to eq([:flying]) # the counter's flying only
    play(game, { type: "cast", object: second }, { type: "target", target: herald })
    expect(chars(game, herald).keywords).to contain_exactly(:flying, :lifelink)
  end

  it "a permanent that lost its abilities stops its static abilities from applying (CR 613.8a)" do
    game = board(hand: ["Quieting Word"], mine: ["Herald Captain", "Sky Herald"])
    herald = obj_id(game, "Sky Herald")
    expect(chars(game, herald).power).to eq(3)
    cast(game, "Quieting Word", { type: "target", target: obj_id(game, "Herald Captain") })
    expect(chars(game, herald).power).to eq(2)
  end

  it "a characteristic-defining power and toughness is lost too: only counters and effects remain (CR 604.3, 613.4a)" do
    game = board(hand: ["Quieting Word"], mine: [["Swarm Measure", { counters: { "+1/+1" => 1 } }], "Sky Herald"])
    measure = obj_id(game, "Swarm Measure")
    expect(chars(game, measure).power).to eq(3)
    cast(game, "Quieting Word", { type: "target", target: measure })
    expect([chars(game, measure).power, chars(game, measure).toughness]).to eq([1, 1])
  end

  it "a creature that lost its abilities dies without its dies trigger (CR 603.10a)" do
    game = board(hand: ["Blackout Purge"], theirs: ["Pyre Imp"])
    cast(game, "Blackout Purge")
    expect(ids_in(game, "bob", :graveyard).size).to eq(1)
    expect(game.state.players[0].life).to eq(20)
    expect(game.state.stack + game.state.pending_triggers).to be_empty
  end

  describe "for as long as the source remains on the battlefield (CR 611.2b)" do
    def moth_board
      board(hand: ["Stillwing Moth", "Lightning Bolt"], theirs: ["Sky Herald"], mana: { U: 2, R: 1 })
    end

    it "lasts while the source stays and ends as it leaves" do
      game = moth_board
      herald = obj_id(game, "Sky Herald")
      cast(game, "Stillwing Moth", { type: "target", target: herald })
      expect(game.state.object(herald).tapped).to be(true)
      expect(chars(game, herald).keywords).to be_empty
      skip_to(game, :upkeep, turn: 4)
      expect(chars(game, herald).keywords).to be_empty
      game = moth_board
      herald = obj_id(game, "Sky Herald")
      cast(game, "Stillwing Moth", { type: "target", target: herald })
      cast(game, "Lightning Bolt", { type: "target", target: obj_id(game, "Stillwing Moth") })
      expect(game.state.effects).to be_empty
      expect(chars(game, herald).keywords).to eq([:flying])
    end

    it "does nothing if the source left before it resolved" do
      game = moth_board
      herald = obj_id(game, "Sky Herald")
      pay = -> { game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost" }
      game.submit(type: "cast", object: obj_id(game, "Stillwing Moth", zone: :hand, player: "alice"))
      pay.call
      game.submit(type: "pass") until game.pending_decision.kind == "choose_target" # the Moth resolves; its trigger targets
      game.submit(type: "target", target: herald)
      game.submit(type: "cast", object: obj_id(game, "Lightning Bolt", zone: :hand, player: "alice"))
      game.submit(type: "target", target: obj_id(game, "Stillwing Moth"))
      pay.call
      game.submit(type: "pass") until game.state.stack.empty?
      expect(game.state.effects).to be_empty
      expect(chars(game, herald).keywords).to eq([:flying])
    end
  end

  it "grants an activated ability to other creatures; it resolves from the granting card's data (CR 613.1f, 602.1)" do
    game = board(mine: ["Wrenchwright", "Sky Herald"], mana: { R: 2 })
    herald = obj_id(game, "Sky Herald")
    wright = obj_id(game, "Wrenchwright")
    options = game.legal_options.select { it[:type] == "activate" }
    expect(options.map { it[:object] }).to eq([herald])
    expect(options.first[:ability]).to start_with("granted:wrenchwright:")
    play(game, options.first)
    expect(chars(game, herald).power).to eq(3)
    expect(chars(game, wright).power).to eq(2)
  end

  it "validates the new parameters with paths" do
    validate = lambda do |card|
      Enjine::CardDefinition.from_h(card)
      []
    rescue Enjine::InvalidCardDefinition => e
      e.errors
    end
    errors = ->(ability) { validate.call(creature("X", 1, 1, "abilities" => [ability])) }
    expect(errors.call("static" => { "affects" => "self", "loses_abilities" => false }))
      .to include("abilities[0].static.loses_abilities: must be true (or absent)")
    expect(errors.call("static" => { "affects" => "self", "colors" => ["X"] }))
      .to include("abilities[0].static.colors: must be a list of W, U, B, R, G ([] for colorless)")
    expect(errors.call("static" => { "affects" => "self", "base_power_toughness" => { "power" => 1 } }))
      .to include("abilities[0].static.base_power_toughness.toughness: must be an integer >= 0")
    become = { "spell" => { "effects" => [{ "become" => { "loses_abilities" => "yes", "duration" => "forever" } }] } }
    expect(validate.call({ "name" => "Y", "mana_cost" => "{U}", "types" => ["instant"], "abilities" => [become] }))
      .to include("abilities[0].spell.effects[0].become.loses_abilities: must be true (or absent)",
                  a_string_matching(/become\.duration: must be one of end_of_turn, until_your_next_turn, indefinite, /))
  end
end
