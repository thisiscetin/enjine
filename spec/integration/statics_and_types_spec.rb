# frozen_string_literal: true

# Statics that set names and card types, protection from each opponent, hexproof from each of its colors, abilities
# that change how a creature crews or stations, "abilities can't be activated / countered", "for as long as you
# control", granted abilities naming their granter and several "as this enters" choices, with invented cards
# (spec/fixtures/cards/*.json).
RSpec.describe "Statics, types and restrictions" do
  let(:catalog) do
    catalog_with(
      { "name" => "Pathfinding", "mana_cost" => "{G}", "types" => ["sorcery"],
        "abilities" => [{ "spell" => { "effects" => [{ "search_library" => { "for" => { "types" => ["land"] },
                                                                             "put" => "battlefield" } }] } }] },
      { "name" => "Ember Dart", "mana_cost" => "{R}", "colors" => ["R"], "types" => ["instant"],
        "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                       "effects" => [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }] } }] }
    )
  end

  def board(mine: [], theirs: [], hand: [], library: [], mana: {}, their_hand: [], their_mana: {})
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: mana) do
        hand(*hand)
        mine.each { |card, opts| battlefield card, **(opts || {}) }
        library(*library) unless library.empty?
        library "Forest", count: 5
      end
      player("bob", mana_pool: their_mana) do
        hand(*their_hand)
        theirs.each { |card, opts| battlefield card, **(opts || {}) }
        library "Forest", count: 5
      end
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def chars(game, card) = engine(game).chars(obj_id(game, card))

  def resolve(game)
    until game.over? || ((decision = game.pending_decision).kind == "priority" && game.state.stack.empty?)
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { it[:type] == "pay_mana" })
      when "choose_target" then game.submit(game.legal_options.first)
      when "legend_rule" then return game
      else raise "unexpected #{decision.kind}: #{game.legal_options}"
      end
    end
    game
  end

  def errors_for(ability)
    Enjine::CardDefinition.from_h("name" => "X", "mana_cost" => "{1}", "types" => ["creature"], "power" => 1,
                                  "toughness" => 1, "abilities" => [ability])
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  it "validates the new shapes with paths" do
    expect(errors_for("static" => { "affects" => "attached", "set_types" => ["instant"] }))
      .to include(a_string_starting_with("abilities[0].static.set_types: must be a non-empty list of types"))
    expect(errors_for("static" => { "affects" => "attached", "name" => "" }))
      .to include("abilities[0].static.name: must be a non-empty string")
    expect(errors_for("tapping_power" => { "for" => ["fly"], "plus" => 2 }))
      .to include("abilities[0].tapping_power.for: must be a non-empty list of crew, saddle, station")
    expect(errors_for("tapping_power" => { "for" => ["crew"], "use" => "luck" }))
      .to include("abilities[0].tapping_power.use: must be one of power, toughness, toughness_if_greater")
    expect(errors_for("tapping_power" => { "for" => ["crew"] })).to include("abilities[0].tapping_power: needs `use` or `plus`")
    expect(errors_for("protection_from" => "each_player"))
      .to include(a_string_starting_with("abilities[0].protection_from: must be a card spec, \"everything\""))
    expect(errors_for("player_rule" => { "rule" => "protection_from_opponents" })).to eq([])
    expect(errors_for("triggered" => { "when" => { "enters" => {} }, "effects" => [{ "become" => { "keywords" => ["flying"],
                                                                                                   "duration" => "while_tapped" } }] }))
      .to include(a_string_including("duration: must be one of end_of_turn, indefinite, while_source_on_battlefield, " \
                                     "while_you_control_source"))
  end

  it "describes the new abilities" do
    defn = catalog.fetch("Mask of Anonymity")
    expect(defn.abilities.last.to_s).to include("named Nameless One", "card types exactly creature")
    expect(catalog.fetch("Copilot Gremlin").abilities.first.to_s).to eq("crew, saddle, station using its toughness + 1")
    expect(catalog.fetch("Oathsworn Paladin").abilities.first.to_s).to eq("Protection from each of your opponents")
    expect(Enjine::Mechanics::Selector.build("granter", [], "x", targets_count: 0).to_s).to eq("the permanent granting it")
  end

  it "a name set by a static makes two legendary creatures share it: the legend rule applies (CR 612.8, 704.5j)" do
    game = board(mine: ["Ripple Sage", "Hall-Song Chronicler"], hand: ["Mask of Anonymity", "Mask of Anonymity"], mana: { U: 4 })
    ["Ripple Sage", "Hall-Song Chronicler"].each do |name|
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(type: "target", target: obj_id(game, name))
      resolve(game)
    end
    expect(game.pending_decision.kind).to eq("legend_rule")
    expect(chars(game, "Ripple Sage")).to have_attributes(name: "Nameless One", types: [:creature], supertypes: [:legendary])
  end

  it "set_types drops the subtypes of lost card types and keeps correlated ones (CR 205.1a)" do
    game = board(mine: ["Rattletrap Wagon"])
    base = engine(game).definition(engine(game).object(obj_id(game, "Rattletrap Wagon"))).printed_characteristics
    expect(engine(game).with_set_types(base, %i[artifact creature])).to have_attributes(subtypes: [:vehicle], power: 4)
    expect(engine(game).with_set_types(base.with(power: nil, toughness: nil), [:creature]))
      .to have_attributes(subtypes: [], power: 0, toughness: 0)
  end

  it "protection from each opponent: a permanent and its controller (CR 702.16k)" do
    game = board(mine: ["Oathsworn Paladin"], their_hand: ["Ember Dart"], their_mana: { R: 1 })
    game.submit(type: "pass")
    game.submit(type: "cast", object: ids_in(game, "bob", :hand).first)
    targets = game.legal_options.filter_map { it[:target] }
    expect(targets).not_to include(obj_id(game, "Oathsworn Paladin"), "player:alice")
    expect(targets).to include("player:bob")
  end

  it "hexproof from each of its colors leaves a colorless creature targetable (CR 702.11g)" do
    game = board(mine: ["Chromatic Mentor", "Rattletrap Wagon"])
    wagon = engine(game).object(obj_id(game, "Rattletrap Wagon"))
    expect(engine(game).protected_from?(wagon, engine(game).object(obj_id(game, "Chromatic Mentor")), :hexproof_from)).to be(false)
  end

  it "Copilot Gremlin crews with its toughness plus 1 (CR 702.122a)" do
    game = board(mine: ["Rattletrap Wagon", "Copilot Gremlin"])
    gremlin = engine(game).object(obj_id(game, "Copilot Gremlin"))
    expect(Enjine::Mechanics::Abilities::TappingPower.of(engine(game), gremlin, :crew)).to eq(4)
    game.submit(type: "activate", object: obj_id(game, "Rattletrap Wagon"), ability: "printed:0")
    game.submit(type: "cost", object: gremlin.id)
    resolve(game)
    expect(chars(game, "Rattletrap Wagon").creature?).to be(true)
  end

  it "Silencing Bell: opponents' creatures can't activate; your abilities and spells can't be countered (CR 101.2)" do
    game = board(mine: ["Silencing Bell", ["Copilot Gremlin", { controlled_since: 1 }]],
                 theirs: [["Copilot Gremlin", { controlled_since: 1 }]])
    theirs = game.state.battlefield.find { game.state.object(it).card == "copilot_gremlin" && game.state.object(it).controller == 1 }
    expect(engine(game).activation_forbidden?(1, engine(game).object(theirs))).to be(true)
    expect(engine(game).activation_forbidden?(0, engine(game).object(obj_id(game, "Silencing Bell")))).to be(false)
    game = board(mine: ["Silencing Bell", "Homing Glove", ["Copilot Gremlin", { controlled_since: 1 }]], mana: { C: 2 })
    glove = obj_id(game, "Homing Glove")
    game.submit(type: "activate", object: glove, ability: "printed:1")
    game.submit(type: "target", target: obj_id(game, "Copilot Gremlin"))
    resolve(game)
    ref = chars(game, "Copilot Gremlin").activated_abilities.first.ref
    game.submit(type: "activate", object: obj_id(game, "Copilot Gremlin"), ability: ref)
    game.submit(type: "target", target: "player:bob")
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) if game.pending_decision.kind == "pay_cost"
    expect(engine(game).counter!(game.state.stack.first)).to be(false)
    resolve(game)
    expect(game.state.players[1].life).to eq(19)
    expect(game.state.players[0].hand).to include(a_string_starting_with("homing_glove"))
  end

  it "for as long as you control it: control goes back once the source changes control (CR 611.2b)" do
    game = board(hand: ["Shackle Drone"], theirs: ["Copilot Gremlin"], mana: { U: 6 })
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    resolve(game)
    gremlin = engine(game).object(obj_id(game, "Copilot Gremlin"))
    expect(gremlin.controller).to eq(0)
    engine(game).move!(obj_id(game, "Shackle Drone"), :graveyard, reason: "destroy")
    expect(gremlin.controller).to eq(1)
  end

  it "two 'as this enters' choices for a land an effect puts onto the battlefield (CR 614.12, 614.12a)" do
    game = board(hand: ["Pathfinding"], library: ["Prismatic Crossing"], mana: { G: 1 })
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(game.legal_options.find { it[:type] == "pay_mana" })
    game.submit(type: "pass") while game.pending_decision.kind == "priority"
    game.submit(type: "find", object: obj_id(game, "Prismatic Crossing", zone: :library, player: "alice"))
    game.submit(type: "done") if game.legal_options.include?({ type: "done" })
    expect(game.pending_decision.kind).to eq("enter_choice")
    game.submit(type: "basic_land_type", basic_land_type: "plains")
    expect(game.legal_options.first).to eq({ type: "pay_life", life: 2 })
    game.submit(type: "enter_tapped")
    resolve(game)
    crossing = engine(game).object(obj_id(game, "Prismatic Crossing"))
    expect([crossing.tapped, engine(game).chars(crossing).subtypes, game.state.players[0].life]).to eq([true, [:plains], 20])
  end
end
