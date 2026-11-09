# frozen_string_literal: true

RSpec.describe "Hexproof from and protection from a quality (CR 702.11d, 702.16)" do
  let(:catalog) do
    spell = lambda do |name, cost, effects, targets: ["creature"]|
      { "name" => name, "mana_cost" => cost, "types" => ["instant"],
        "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects } }] }
    end
    catalog_with(
      spell.call("Night Dart", "{B}", [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }]),
      spell.call("Dawn Dart", "{W}", [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }]),
      spell.call("Sun Ward", "{W}", [{ "become" => { "abilities" => [{ "protection_from" => { "colors" => ["W"] } }],
                                                     "to" => { "target" => 0 } } }]),
      { "name" => "Dawn Squire", "mana_cost" => "{W}", "colors" => ["W"], "types" => ["creature"], "power" => 1, "toughness" => 1 },
      { "name" => "Dawn Shackle", "mana_cost" => "{W}", "types" => ["enchantment"], "subtypes" => ["aura"],
        "abilities" => [{ "enchant" => "creature" },
                        { "static" => { "affects" => "attached", "pump" => { "power" => -1, "toughness" => 0 } } }] },
      { "name" => "Everwarded Titan", "mana_cost" => "{5}", "types" => ["creature"], "power" => 5, "toughness" => 5,
        "abilities" => [{ "protection_from" => "everything" }] }
    )
  end

  def board(alice: [], alice_hand: [], bob: [], bob_hand: [], mana: { W: 2, B: 2, R: 1 }, step: :precombat_main)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana) do
        hand(*alice_hand)
        alice.each { battlefield it }
        library "Forest", count: 10
      end
      player("bob", mana_pool: mana) do
        hand(*bob_hand)
        bob.each { battlefield it }
        library "Forest", count: 10
      end
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)

  # The targets offered for the card in `player`'s hand (the cast is then cancelled with a fresh game).
  def targets_for(game, card, player)
    game.submit(type: "pass") if player == "bob"
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: player))
    game.legal_options.filter_map { it[:target] }
  end

  it "hexproof from black: opponents' black spells can't target it; red ones and its controller's can (CR 702.11d)" do
    game = board(alice: ["Dawnguard Knight"], bob_hand: ["Night Dart"])
    expect(engine(game).castable?(1, obj_id(game, "Night Dart", zone: :hand, player: "bob"))).to be(false)
    game = board(alice: ["Dawnguard Knight"], bob_hand: ["Lightning Bolt"])
    expect(targets_for(game, "Lightning Bolt", "bob")).to include(obj_id(game, "Dawnguard Knight"))
    game = board(alice: ["Dawnguard Knight"], alice_hand: ["Night Dart"])
    expect(targets_for(game, "Night Dart", "alice")).to include(obj_id(game, "Dawnguard Knight"))
  end

  it "granted by an Equipment: hexproof from monocolored (CR 702.11d, 613.1f)" do
    game = board(alice: ["Grizzly Bears", "Prismward Blade"], bob_hand: ["Lightning Bolt"])
    bears = obj_id(game, "Grizzly Bears")
    game.state.object(obj_id(game, "Prismward Blade")).attached_to = bears
    engine(game).touch!
    expect(targets_for(game, "Lightning Bolt", "bob")).not_to include(bears)
    expect(engine(game).chars(bears).power).to eq(3)
  end

  it "protection from white: no white targets, damage, blockers or Auras, even its controller's (CR 702.16b-f)" do
    game = board(alice: ["Ashen Paladin"], alice_hand: ["Dawn Dart"])
    paladin = obj_id(game, "Ashen Paladin")
    expect(engine(game).castable?(0, obj_id(game, "Dawn Dart", zone: :hand, player: "alice"))).to be(false)
    expect(engine(game).targetable?(paladin, 0, targeter: obj_id(game, "Dawn Dart", zone: :hand, player: "alice"))).to be(false)
    game = board(alice: ["Ashen Paladin", "Dawn Squire"], bob: ["Dawn Squire", "Prodigal Pyromancer"])
    paladin = obj_id(game, "Ashen Paladin")
    white = game.state.battlefield.find { game.state.object(it).card == "dawn_squire" && game.state.object(it).controller == 1 }
    red = obj_id(game, "Prodigal Pyromancer")
    expect(engine(game).deal_damage!(white, paladin, 3)).to eq(0)
    expect(engine(game).deal_damage!(red, paladin, 1)).to eq(1)
    expect(engine(game).can_block?(white, paladin)).to be(false)
    expect(engine(game).can_block?(red, paladin)).to be(true)
  end

  it "an Aura with the quality falls off as protection is gained (CR 702.16c, 704.5m)" do
    game = board(alice: ["Grizzly Bears", "Dawn Shackle"], alice_hand: ["Sun Ward"])
    bears = obj_id(game, "Grizzly Bears")
    shackle = obj_id(game, "Dawn Shackle")
    game.state.object(shackle).attached_to = bears
    engine(game).touch!
    expect(engine(game).chars(bears).power).to eq(1)
    game.submit(type: "cast", object: obj_id(game, "Sun Ward", zone: :hand, player: "alice"))
    game.submit(type: "target", target: bears)
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
    game.submit(type: "pass") until game.state.stack.empty?
    expect(game.state.battlefield).not_to include(shackle)
    expect(ids_in(game, "alice", :graveyard).map { game.state.object(it).card }).to include("dawn_shackle", "sun_ward")
  end

  it "protection from everything: nothing targets, blocks or damages it (CR 702.16j)" do
    game = board(alice: ["Everwarded Titan"], alice_hand: ["Lightning Bolt"], bob: ["Grizzly Bears"])
    titan = obj_id(game, "Everwarded Titan")
    expect(targets_for(game, "Lightning Bolt", "alice")).not_to include(titan)
    expect(engine(game).can_block?(obj_id(game, "Grizzly Bears"), titan)).to be(false)
    expect(engine(game).deal_damage!(obj_id(game, "Grizzly Bears"), titan, 2)).to eq(0)
  end

  it "validates qualities with paths" do
    errors = lambda do |ability|
      Enjine::CardDefinition.from_h("name" => "X", "mana_cost" => "{1}", "types" => ["creature"], "power" => 1,
                                    "toughness" => 1, "abilities" => [ability])
      []
    rescue Enjine::InvalidCardDefinition => e
      e.errors
    end
    expect(errors.call("protection_from" => { "colors" => ["purple"] }))
      .to include('abilities[0].protection_from.colors: unknown color "purple" (W, U, B, R, G)')
    expect(errors.call("hexproof_from" => "nothing")).to include(a_string_starting_with("abilities[0].hexproof_from: must be"))
    expect(errors.call("hexproof_from" => { "color_count" => 1 }))
      .to include(a_string_starting_with("abilities[0].hexproof_from.color_count: must be"))
    expect(Enjine::Mechanics::CardSpec.build({ "colors" => ["B"], "color_count" => { "equal" => 1 } }, [], "s").to_s)
      .to eq("B card with number of colors equal 1")
  end
end
