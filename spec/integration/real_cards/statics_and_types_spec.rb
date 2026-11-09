# frozen_string_literal: true

# Real cards whose static abilities set names and types, protect players, restrict activation or change how
# creatures crew and station (spec/fixtures/cards/real/statics_and_types.json), written by hand in the card DSL.
# Creatures and Vehicles from creatures_combat_keywords.json and bending_and_mounts.json stand in as targets.
RSpec.describe "Real cards: statics, types and restrictions" do
  let(:cards) do
    %w[statics_and_types creatures_combat_keywords bending_and_mounts newest_sets].flat_map { CardFixtures.real(it) }.uniq { it["name"] }
  end
  let(:catalog) { Enjine::Catalog.from_definitions(cards) }

  def board(hand: [], mine: [], theirs: [], their_hand: [], mana: {}, their_mana: {}, step: :precombat_main)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana) do
        hand(*hand)
        mine.each { |card, opts| battlefield card, **(opts || {}) }
        library "Island", count: 10
      end
      player("bob", mana_pool: their_mana) do
        hand(*their_hand)
        theirs.each { |card, opts| battlefield card, **(opts || {}) }
        library "Island", count: 10
      end
    end
  end

  # Submits `action`, answers further decisions with `answers` in order, pays from the pool and passes until
  # the stack is empty.
  def play(game, action, *answers)
    game.submit(action)
    until game.over? || ((decision = game.pending_decision).kind == "priority" && game.state.stack.empty?)
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { it[:type] == "pay_mana" } || raise("can't pay"))
      else game.submit(answers.shift || raise("no answer for #{decision.kind}: #{game.legal_options}"))
      end
    end
    expect(answers).to be_empty
    game
  end

  def cast(game, card, *) = play(game, { type: "cast", object: obj_id(game, card, zone: :hand, player: "alice") }, *)
  def target(game, card) = { type: "target", target: obj_id(game, card) }
  def engine(game) = game.instance_variable_get(:@engine)
  def chars(game, id) = engine(game).chars(id)
  def player_ref(game, name) = Enjine::Mechanics::Filters.player_ref(engine(game), game.names.index(name))

  # Activates the crew, saddle or station ability of alice's `card`, tapping `creatures` for its cost.
  def tap_for(game, card, *creatures)
    source = obj_id(game, card)
    game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == source })
    creatures.each { game.submit(type: "cost", object: obj_id(game, it)) }
    expect(game.pending_decision.kind).not_to eq("choose_cost") # the cost is paid in full
    play(game, { type: "pass" })
  end

  # The targets bob is offered for a card in his hand.
  def bob_targets(game, card)
    game.submit(type: "pass")
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: "bob"))
    game.submit(type: "no_kick") if game.pending_decision.kind == "choose_kicker"
    game.legal_options.filter_map { it[:target] }
  end

  it "every card validates and keeps its rarity and printing" do
    CardFixtures.real("statics_and_types").each { expect(Enjine::CardDefinition.from_h(it).to_h).to include("printing", "rarity") }
  end

  it "Eaten by Piranhas: an artifact creature becomes only a black Skeleton creature, 1/1, no abilities (CR 205.1a)" do
    game = board(hand: ["Eaten by Piranhas"], theirs: ["Camera Launcher"], mana: { U: 2 })
    launcher = obj_id(game, "Camera Launcher")
    cast(game, "Eaten by Piranhas", target(game, "Camera Launcher"))
    c = chars(game, launcher)
    expect([c.types, c.subtypes, c.colors, c.abilities, c.power, c.toughness]).to eq([[:creature], [:skeleton], [:B], [], 1, 1])
  end

  it "Witness Protection: the enchanted creature is named Legitimate Businessperson (CR 612.8, 613.1c)" do
    game = board(hand: ["Witness Protection"], theirs: ["Vampire Nighthawk"], mana: { U: 1 })
    hawk = obj_id(game, "Vampire Nighthawk")
    cast(game, "Witness Protection", target(game, "Vampire Nighthawk"))
    c = chars(game, hawk)
    expect([c.name, c.colors, c.subtypes, c.keywords, c.power]).to eq(["Legitimate Businessperson", %i[W G], [:citizen], [], 1])
    expect(view_of(game, hawk)["name"]).to eq("Legitimate Businessperson")
  end

  it "Honest Work: a tapped Humble Merchant with '{T}: Add {C}' and no counters (CR 612.8, 613.1f)" do
    game = board(hand: ["Honest Work"], theirs: [["Vampire Nighthawk", { counters: { "+1/+1" => 2 } }]], mana: { U: 1 })
    hawk = obj_id(game, "Vampire Nighthawk")
    cast(game, "Honest Work", target(game, "Vampire Nighthawk"))
    c = chars(game, hawk)
    expect([c.name, c.types, c.subtypes, c.keywords, c.power, c.toughness]).to eq(["Humble Merchant", [:creature], [:citizen], [], 1, 1])
    expect(c.mana_abilities.size).to eq(1)
    expect(game.state.object(hawk).tapped).to be(true)
    expect(game.state.object(hawk).counters.values.sum).to eq(0)
  end

  it "Puppet Crafting: an artifact becomes a 5/5 Construct creature in addition to its other types (CR 205.1b, 613.4b)" do
    game = board(hand: ["Puppet Crafting"], theirs: ["Basilisk Collar"], mana: { G: 2 })
    collar = obj_id(game, "Basilisk Collar")
    cast(game, "Puppet Crafting", target(game, "Basilisk Collar"))
    c = chars(game, collar)
    expect([c.types, c.subtypes, c.power, c.toughness]).to eq([%i[artifact creature], %i[equipment construct], 5, 5])
  end

  it "Alacrian Armory: at the beginning of combat a Mount becomes saddled and a Vehicle an artifact creature (CR 702.171b)" do
    combat = lambda do |pick|
      game = board(mine: ["Alacrian Armory", "Gilded Ghoda", "Air Response Unit"])
      2.times { game.submit(type: "pass") }
      expect(game.pending_decision.kind).to eq("choose_target")
      play(game, target(game, pick))
    end
    game = combat.call("Air Response Unit")
    unit = obj_id(game, "Air Response Unit")
    expect(chars(game, unit)).to have_attributes(types: %i[artifact creature], toughness: 4, keywords: %i[flying vigilance])
    expect(engine(game).saddled?(game.state.object(obj_id(game, "Gilded Ghoda")))).to be(false)
    game = combat.call("Gilded Ghoda")
    expect(engine(game).saddled?(game.state.object(obj_id(game, "Gilded Ghoda")))).to be(true)
    expect(chars(game, obj_id(game, "Air Response Unit")).creature?).to be(false)
  end

  it "Absolute Virtue: you have protection from each of your opponents (CR 702.16b, 702.16e, 702.16k)" do
    game = board(mine: ["Absolute Virtue", "Vampire Nighthawk"], their_hand: ["Burst Lightning"], their_mana: { R: 1 })
    alice = player_ref(game, "alice")
    expect(bob_targets(game, "Burst Lightning")).to include(obj_id(game, "Vampire Nighthawk"), player_ref(game, "bob"))
    expect(bob_targets(board(mine: ["Absolute Virtue"], their_hand: ["Burst Lightning"], their_mana: { R: 1 }), "Burst Lightning"))
      .not_to include(alice)
    expect(engine(game).deal_damage!(game.state.stack.last, alice, 2)).to eq(0)
    expect(engine(game).deal_damage!(obj_id(game, "Vampire Nighthawk"), alice, 2)).to eq(2) # your own source
  end

  it "Figure of Fable: Scout, then Soldier, then a 7/8 Avatar with protection from each of your opponents (CR 702.16k)" do
    game = board(mine: ["Figure of Fable"], their_hand: ["Burst Lightning"], their_mana: { R: 1 }, mana: { G: 9, W: 9 })
    figure = obj_id(game, "Figure of Fable")
    activate = ->(i) { play(game, { type: "activate", object: figure, ability: "printed:#{i}" }) }
    activate.call(2) # not a Soldier yet: nothing happens
    expect(chars(game, figure).power).to eq(1)
    [0, 1, 2].each { activate.call(it) }
    c = chars(game, figure)
    expect([c.subtypes, c.power, c.toughness]).to eq([%i[kithkin avatar], 7, 8])
    expect(bob_targets(game, "Burst Lightning")).not_to include(figure)
    expect(engine(game).deal_damage!(game.state.stack.last, figure, 3)).to eq(0)
  end

  it "Tam, Mindful First-Year: other creatures have hexproof from each of their colors (CR 702.11d, 702.11g)" do
    game = board(mine: ["Tam, Mindful First-Year", "Gilded Ghoda", "Vampire Nighthawk"], their_hand: ["Burst Lightning"],
                 their_mana: { R: 1 })
    targets = bob_targets(game, "Burst Lightning")
    expect(targets).not_to include(obj_id(game, "Gilded Ghoda")) # red, like Burst Lightning
    expect(targets).to include(obj_id(game, "Vampire Nighthawk"), obj_id(game, "Tam, Mindful First-Year"))
    game = board(mine: ["Tam, Mindful First-Year", "Vampire Nighthawk"], their_hand: ["Burst Lightning"], their_mana: { R: 1 })
    play(game, { type: "activate", object: obj_id(game, "Tam, Mindful First-Year"), ability: "printed:1" },
         target(game, "Vampire Nighthawk"))
    expect(bob_targets(game, "Burst Lightning")).not_to include(obj_id(game, "Vampire Nighthawk")) # now all colors
  end

  it "Dynamite Diver: crews Vehicles as though its power were 2 greater (CR 702.122a)" do
    game = board(mine: ["Hulldrifter", "Dynamite Diver"])
    tap_for(game, "Hulldrifter", "Dynamite Diver") # crew 3 with a 1/1
    expect(chars(game, obj_id(game, "Hulldrifter")).creature?).to be(true)
  end

  it "Cloudspire Captain: saddles Mounts as though its power were 2 greater and pumps Mounts (CR 702.171a)" do
    game = board(mine: ["Gilded Ghoda", "Cloudspire Captain"])
    expect(chars(game, obj_id(game, "Gilded Ghoda")).power).to eq(3)
    tap_for(game, "Gilded Ghoda", "Cloudspire Captain")
    expect(engine(game).saddled?(game.state.object(obj_id(game, "Gilded Ghoda")))).to be(true)
    expect(Enjine::Mechanics::Abilities::TappingPower.of(engine(game), game.state.object(obj_id(game, "Cloudspire Captain")), :station))
      .to eq(2) # only for crew and saddle
  end

  it "Tapestry Warden: a creature with toughness greater than its power stations using its toughness (CR 702.184c)" do
    game = board(mine: ["Tapestry Warden", "Oberth-Class Starship", "Gleaming Barrier", "Juggernaut"])
    tap_for(game, "Oberth-Class Starship", "Gleaming Barrier") # 0/4
    expect(game.state.object(obj_id(game, "Oberth-Class Starship")).counters["charge"]).to eq(4)
    game = board(mine: ["Tapestry Warden", "Oberth-Class Starship", "Juggernaut"])
    tap_for(game, "Oberth-Class Starship", "Juggernaut") # 5/3: its power
    expect(game.state.object(obj_id(game, "Oberth-Class Starship")).counters["charge"]).to eq(5)
    expect(chars(game, obj_id(game, "Juggernaut")).keywords).to include(:assigns_damage_by_toughness)
  end

  it "Possession Engine: control and 'can't attack or block' last for as long as you control it (CR 611.2b)" do
    game = board(hand: ["Possession Engine"], theirs: ["Vampire Nighthawk"], mana: { U: 5 })
    hawk = obj_id(game, "Vampire Nighthawk")
    cast(game, "Possession Engine", target(game, "Vampire Nighthawk"))
    expect(game.state.object(hawk).controller).to eq(0)
    expect(chars(game, hawk).keywords).to include(:cant_attack, :cant_block)
    engine(game).gain_control!(game.state.object(obj_id(game, "Possession Engine")), 1)
    expect(game.state.object(hawk).controller).to eq(1)
    expect(chars(game, hawk).keywords).not_to include(:cant_attack)
    engine(game).gain_control!(game.state.object(obj_id(game, "Possession Engine")), 0) # it doesn't start again
    expect(game.state.object(hawk).controller).to eq(1)
  end

  it "Ty Lee, Chi Blocker: the creature doesn't untap for as long as you control Ty Lee (CR 611.2b, 502.3)" do
    game = board(hand: ["Ty Lee, Chi Blocker"], theirs: ["Vampire Nighthawk"], mana: { U: 3 })
    hawk = obj_id(game, "Vampire Nighthawk")
    cast(game, "Ty Lee, Chi Blocker", target(game, "Vampire Nighthawk"))
    expect([game.state.object(hawk).tapped, chars(game, hawk).keywords]).to eq([true, %i[flying deathtouch lifelink doesnt_untap]])
    engine(game).move!(obj_id(game, "Ty Lee, Chi Blocker"), :graveyard, reason: "destroy")
    expect(chars(game, hawk).keywords).not_to include(:doesnt_untap)
  end

  it "Clarion Conqueror: activated abilities of artifacts and creatures can't be activated, mana abilities too (CR 602.5, 605.3a)" do
    game = board(mine: ["Veloheart Bike", "Aetherjacket", "Island", "Gleaming Barrier"], theirs: ["Clarion Conqueror"])
    expect(game.legal_options.map { it[:object] }.uniq.compact).to eq([obj_id(game, "Island")]) # a land still taps for mana
    game = board(mine: ["Veloheart Bike", "Aetherjacket", "Gleaming Barrier"])
    expect(game.legal_options.map { it[:type] }).to include("activate", "activate_mana")
  end

  it "Stuck in Summoner's Sanctum: taps the permanent, which doesn't untap and can't activate abilities (CR 502.3, 602.5)" do
    game = board(hand: ["Stuck in Summoner's Sanctum"], mine: ["Veloheart Bike"], mana: { U: 3 })
    bike = obj_id(game, "Veloheart Bike")
    cast(game, "Stuck in Summoner's Sanctum", target(game, "Veloheart Bike"))
    expect(game.state.object(bike).tapped).to be(true)
    game.state.object(bike).tapped = false
    expect(game.legal_options.select { it[:object] == bike }).to be_empty
    expect(chars(game, bike).keywords).to include(:doesnt_untap)
  end

  it "Trusty Boomerang: the equipped creature's granted ability returns the Boomerang (CR 607.1a, 613.1f)" do
    game = board(mine: [["Vampire Nighthawk", { controlled_since: 1 }], "Trusty Boomerang"], theirs: ["Juggernaut"], mana: { C: 2 })
    hawk = obj_id(game, "Vampire Nighthawk")
    boomerang = obj_id(game, "Trusty Boomerang")
    play(game, { type: "activate", object: boomerang, ability: "printed:1" }, { type: "target", target: hawk }) # equip
    ref = chars(game, hawk).activated_abilities.first.ref
    expect(ref).to eq("granted:trusty_boomerang:printed:0:0@#{boomerang}")
    game.submit(type: "activate", object: hawk, ability: ref)
    game.submit(target(game, "Juggernaut"))
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) if game.pending_decision.kind == "pay_cost"
    game = Enjine::Game.import(JSON.parse(game.export), catalog: catalog) # the granter survives a snapshot
    play(game, { type: "pass" })
    expect(game.state.object(obj_id(game, "Juggernaut")).tapped).to be(true)
    expect(obj_id(game, "Trusty Boomerang", zone: :hand, player: "alice")).not_to be_nil
  end

  it "an Equipment attached after Eaten by Piranhas gets a new timestamp, so its abilities stay (CR 613.7e, 613.7a)" do
    game = board(hand: ["Eaten by Piranhas"], mine: ["Swiftfoot Boots", "Gleaming Barrier"], mana: { U: 2, C: 1 })
    wall = obj_id(game, "Gleaming Barrier")
    cast(game, "Eaten by Piranhas", target(game, "Gleaming Barrier"))
    expect(chars(game, wall).keywords).to eq([])
    play(game, { type: "activate", object: obj_id(game, "Swiftfoot Boots"), ability: "printed:1" }, target(game, "Gleaming Barrier"))
    expect(chars(game, wall).keywords).to eq(%i[hexproof haste])
  end

  it "Multiversal Passage: two 'as this enters' choices in printed order, a basic land type then life (CR 614.12)" do
    game = board(hand: ["Multiversal Passage"])
    game.submit(type: "play_land", object: obj_id(game, "Multiversal Passage", zone: :hand, player: "alice"))
    expect(game.legal_options).to include({ type: "basic_land_type", basic_land_type: "forest" })
    game.submit(type: "basic_land_type", basic_land_type: "forest")
    game = Enjine::Game.import(JSON.parse(game.export), catalog: catalog) # between the two choices
    expect(game.legal_options).to eq([{ type: "pay_life", life: 2 }, { type: "enter_tapped" }])
    game.submit(type: "pay_life", life: 2)
    land = game.state.object(obj_id(game, "Multiversal Passage"))
    expect([land.tapped, chars(game, land.id).subtypes, game.state.players[0].life]).to eq([false, [:forest], 18])
    expect(chars(game, land.id).mana_abilities.size).to eq(1)
    game = board(hand: ["Multiversal Passage"])
    game.submit(type: "play_land", object: obj_id(game, "Multiversal Passage", zone: :hand, player: "alice"))
    game.submit(type: "basic_land_type", basic_land_type: "island")
    game.submit(type: "enter_tapped")
    expect(game.state.object(obj_id(game, "Multiversal Passage")).tapped).to be(true)
  end
end
