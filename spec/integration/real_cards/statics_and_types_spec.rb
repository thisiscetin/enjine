# frozen_string_literal: true

# Real cards whose static abilities set names and types, protect players, restrict activation or change how
# creatures crew and station (spec/fixtures/cards/real/statics_and_types.json), written by hand in the card DSL.
# Creatures and Vehicles from creatures_combat_keywords.json and bending_and_mounts.json stand in as targets.
RSpec.describe "Real cards: statics, types and restrictions" do
  let(:cards) do
    %w[statics_and_types creatures_combat_keywords bending_and_mounts].flat_map { CardFixtures.real(it) }.uniq { it["name"] }
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
    expect([chars(game, unit).types, chars(game, unit).toughness, chars(game, unit).keywords]).to eq([%i[artifact creature], 4, %i[flying vigilance]])
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
end
