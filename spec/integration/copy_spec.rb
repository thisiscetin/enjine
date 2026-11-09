# frozen_string_literal: true

# Copying objects (CR 707): token copies (707.8), entering as a copy (707.5), becoming a copy for a
# duration (707.4, 613.2a), copying spells (707.10) and casting copies of cards (707.12), plus changeling
# (702.73a). Every card here is invented.
RSpec.describe "Copy effects (CR 707)" do
  let(:mimic) do
    { "name" => "Burrowing Mimic", "mana_cost" => "{2}{W}", "types" => ["creature"], "subtypes" => ["beast"],
      "power" => 1, "toughness" => 1, "keywords" => ["cant_block"],
      "abilities" => [{ "triggered" => { "when" => { "step_begins" => { "step" => "upkeep" } },
                                         "effects" => [{ "create_token_copy" => { "of" => "self" } }] } }] }
  end
  let(:herald) do
    { "name" => "Twin Herald", "mana_cost" => "{2}{U}", "types" => ["creature"], "supertypes" => ["legendary"],
      "subtypes" => ["human"], "power" => 2, "toughness" => 3 }
  end
  let(:doubling) do
    { "name" => "Doubling Rite", "mana_cost" => "{1}{U}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => [{ "creature" => { "controller" => "you" } }], "effects" => [
        { "create_token_copy" => { "of" => { "target" => 0 }, "except" => { "legendary" => false } } },
        { "grant" => { "keywords" => ["haste"], "to" => { "result" => 0 } } },
        { "delayed_trigger" => { "when" => { "step_begins" => { "step" => "end", "whose" => "each" } },
                                 "effects" => [{ "sacrifice" => { "to" => { "result" => 0 } } }] } }
      ] } }] }
  end
  let(:raid) do
    { "name" => "Mirror Raid", "mana_cost" => "{1}{U}{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => [{ "creature" => { "controller" => "opponent" } }], "effects" => [
        { "create_token_copy" => { "of" => { "target" => 0 }, "except" => { "keywords" => ["menace"] } } }
      ] } }] }
  end
  let(:forge) do
    { "name" => "Echo Forge", "mana_cost" => "{2}", "types" => ["artifact"],
      "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{2}" }, "tap"],
                                         "targets" => [{ "permanent" => { "token" => true, "controller" => "you" } }],
                                         "effects" => [{ "create_token_copy" => { "of" => { "target" => 0 },
                                                                                  "tapped" => true } }] } }] }
  end
  let(:saboteur) do
    { "name" => "Shifting Saboteur", "mana_cost" => "{1}{U}", "types" => ["creature"], "subtypes" => ["shapeshifter"],
      "power" => 0, "toughness" => 0,
      "abilities" => [{ "enter_as_copy" => { "of" => { "permanent" => { "any_of" => %w[artifact creature] } },
                                             "except" => { "legendary" => false }, "with_counters" => true } }] }
  end
  let(:greeter) do
    { "name" => "Cheerful Greeter", "mana_cost" => "{1}{W}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} }, "effects" => [{ "gain_life" => { "amount" => 2 } }] } }] }
  end
  let(:weaver) do
    { "name" => "Heirloom Weaver", "mana_cost" => "{1}{U}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [
        { "triggered" => { "when" => { "enters" => {} }, "effects" => [
          { "create_token" => { "token" => { "name" => "Woven Charm", "colors" => [], "types" => ["artifact"],
                                             "subtypes" => ["equipment"],
                                             "abilities" => [{ "static" => { "affects" => "attached",
                                                                             "pump" => { "power" => 1, "toughness" => 1 } } },
                                                             { "equip" => { "cost" => [{ "mana" => "{2}" }] } }] } } },
          { "attach" => { "to" => "self", "attachment" => { "result" => 0 } } }
        ] } },
        { "activated" => { "cost" => [{ "mana" => "{2}" }],
                           "targets" => [{ "permanent" => { "subtypes" => ["equipment"], "controller" => "you" } }],
                           "effects" => [{ "become_copy" => {
                             "to" => { "each" => { "permanent" => { "subtypes" => ["equipment"], "token" => true } },
                                       "controller" => "you" },
                             "of" => { "target" => 0 }
                           } }] } }
      ] }
  end
  let(:blade) do
    { "name" => "Gilded Blade", "mana_cost" => "{1}", "types" => ["artifact"], "subtypes" => ["equipment"],
      "abilities" => [{ "static" => { "affects" => "attached", "pump" => { "power" => 3, "toughness" => 0 } } },
                      { "equip" => { "cost" => [{ "mana" => "{1}" }] } }] }
  end
  let(:splicer) do
    { "name" => "Dread Splicer", "mana_cost" => "{3}{B}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "abilities" => [{ "triggered" => {
        "when" => { "enters" => {} },
        "targets" => [{ "graveyard_card" => { "controller" => "you", "any_of" => ["creature"] } }],
        "effects" => [
          { "exile" => { "to" => { "target" => 0 } } },
          { "create_token_copy" => { "of" => { "result" => 0 } } },
          { "grant" => { "keywords" => ["haste"], "to" => { "result" => 1 } } }
        ]
      } }] }
  end
  let(:ensign) do
    { "name" => "Phantom Ensign", "mana_cost" => "{1}{R}", "types" => ["creature"], "supertypes" => ["legendary"],
      "keywords" => ["haste"], "power" => 2, "toughness" => 1,
      "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{2}{R}" }, "exile_self_from_graveyard"], "timing" => "sorcery",
                                         "effects" => [{ "create_token_copy" => { "of" => "self" } }] } }] }
  end
  let(:badge) do
    { "name" => "Signal Badge", "mana_cost" => "{3}", "types" => ["artifact"], "subtypes" => %w[communicator equipment],
      "abilities" => [
        { "triggered" => { "when" => { "cast" => { "self" => true } }, "effects" => [{ "copy_spell" => { "of" => "self" } }] } },
        { "static" => { "affects" => "attached", "abilities" => [
          { "triggered" => { "when" => { "attacks" => { "subject" => "self" } },
                             "while" => { "at_least" => 1, "controls" => communicators },
                             "effects" => [{ "grant" => { "keywords" => ["cant_be_blocked"], "to" => "self" } }] } }
        ] } },
        { "equip" => { "cost" => [{ "mana" => "{2}" }] } }
      ] }
  end
  let(:communicators) do
    { "each" => { "creature" => { "other" => true, "attached_subtypes" => ["communicator"] } }, "controller" => "you" }
  end
  let(:bolt) do
    { "name" => "Arc Jolt", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                     "effects" => [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }] } }] }
  end
  let(:echo) do
    { "name" => "Resonant Echo", "mana_cost" => "{U}{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => [{ "spell" => { "controller" => "you" } }],
                                     "effects" => [{ "copy_spell" => { "of" => { "target" => 0 }, "new_targets" => true } }] } }] }
  end
  let(:diversity) do
    { "name" => "Prismatic Recall", "mana_cost" => "{3}{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => {
        "targets" => [{ "graveyard_card" => { "controller" => "you", "any_of" => %w[instant sorcery] } }],
        "effects" => [
          { "exile" => { "to" => { "target" => 0 } } },
          { "copy_card" => { "of" => { "result" => 0 }, "amount" => 2 } },
          { "cast_free" => { "to" => { "result" => 1 }, "count" => "any" } },
          { "exile_this_spell" => {} }
        ]
      } }] }
  end
  let(:trickster) do
    { "name" => "Trickster of Stacks", "mana_cost" => "{2}{R}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} }, "effects" => [
        { "exile_until" => { "until" => "nonland" } },
        { "grant_ability" => { "to" => { "result" => 0 }, "for" => { "not_types" => ["land"] }, "ability" => { "activated" => {
          "cost" => [{ "exile_from_hand" => {} }], "timing" => "your_turn", "zone" => "exile",
          "effects" => [{ "copy_card" => { "of" => "self" } }, { "cast" => { "to" => { "result" => 0 } } }]
        } } } }
      ] } }] }
  end
  let(:drifter) do
    { "name" => "Many-Faced Drifter", "mana_cost" => "{1}{U}", "types" => ["creature"], "subtypes" => ["shapeshifter"],
      "keywords" => ["changeling"], "power" => 1, "toughness" => 1 }
  end
  let(:tribal) do
    { "name" => "Kindred Banner", "mana_cost" => "{2}", "types" => ["artifact"],
      "abilities" => [{ "static" => { "affects" => { "each" => { "creature" => { "subtypes" => ["goblin"] } }, "controller" => "you" },
                                      "pump" => { "power" => 1, "toughness" => 1 } } }] }
  end
  let(:catalog) do
    catalog_with(mimic, herald, doubling, raid, forge, saboteur, greeter, weaver, blade, splicer, ensign, badge, bolt, echo,
                 diversity, trickster, drifter, tribal)
  end

  def board(alice: {}, bob: {}, turn: 3, active: "alice", step: :precombat_main)
    build_game(catalog) do
      turn turn, active: active, step: step
      [["alice", alice], ["bob", bob]].each do |name, zones|
        player(name) do
          zones.each { |zone, cards| Array(cards).each { public_send(zone, it) } }
          library "Island", count: 5 unless zones.key?(:library)
        end
      end
    end
  end

  def tap_for(game, land, color)
    id = game.state.battlefield.find { game.state.object(it).card == land && !game.state.object(it).tapped }
    game.submit(type: "activate_mana", object: id, ability: "intrinsic:#{land}")
    game.submit(type: "pay_mana", mana: color)
  end

  def cast(game, card, *targets)
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: "alice"))
    targets.each { game.submit(type: "target", target: it) }
  end

  def objects_of(game, card) = game.state.objects.values.select { it.card == Enjine::CardDefinition.slug(card) }
  def engine(game) = game.instance_variable_get(:@engine)
  def roundtrip(game) = Enjine::Game.import(game.export, catalog: catalog)

  describe "token copies (CR 707.8, 111.1)" do
    it "copies the permanent's copiable values but not its counters, tapped status or damage (CR 707.2)" do
      game = board(alice: { battlefield: ["Burrowing Mimic"] }, turn: 2, active: "bob", step: :end)
      mimic_id = obj_id(game, "Burrowing Mimic")
      game.state.object(mimic_id).counters["+1/+1"] = 2
      game.state.object(mimic_id).tapped = true
      skip_to(game, :draw, turn: 3)
      tokens = objects_of(game, "Burrowing Mimic").reject { it.id == mimic_id }
      expect(tokens.size).to eq(1)
      token = tokens.first
      expect(engine(game).token?(token)).to be(true)
      expect(token.counters).to be_empty
      expect(token.tapped).to be(false)
      expect(engine(game).chars(token)).to have_attributes(name: "Burrowing Mimic", power: 1, toughness: 1)
      expect(engine(game).chars(token).keyword?(:cant_block)).to be(true)
      expect(roundtrip(game).state.object(token.id).memory).to eq(token.memory)
    end

    it "a token copy of a token copy copies its copiable values too, and it is a token for filters (CR 707.2)" do
      game = board(alice: { battlefield: ["Burrowing Mimic", "Echo Forge", "Island", "Island"] }, turn: 2, active: "bob",
                   step: :end)
      skip_to(game, :precombat_main, turn: 3)
      token = objects_of(game, "Burrowing Mimic").find { engine(game).token?(it) }
      game.submit(type: "activate", object: obj_id(game, "Echo Forge"), ability: "printed:0")
      game.submit(type: "target", target: token.id)
      2.times { tap_for(game, "island", "U") }
      pass_both(game)
      copies = objects_of(game, "Burrowing Mimic").select { engine(game).token?(it) }
      expect(copies.size).to eq(2)
      expect(copies.map(&:tapped)).to contain_exactly(false, true) # CR 707.8 + "tapped"
    end

    it "copies with exceptions: not legendary, and gains a keyword; haste and a delayed sacrifice use its result" do
      game = board(alice: { battlefield: ["Twin Herald", "Island", "Island"], hand: ["Doubling Rite"] })
      herald = obj_id(game, "Twin Herald")
      cast(game, "Doubling Rite", herald)
      2.times { tap_for(game, "island", "U") }
      pass_both(game)
      heralds = objects_of(game, "Twin Herald")
      expect(heralds.size).to eq(2) # no legend rule: the copy isn't legendary (CR 707.9b)
      token = heralds.find { engine(game).token?(it) }
      expect(engine(game).chars(token).legendary?).to be(false)
      expect(engine(game).chars(token).keyword?(:haste)).to be(true)
      expect(engine(game).chars(herald).legendary?).to be(true)
      skip_to(game, :upkeep, turn: 4)
      expect(game.state.objects.key?(token.id)).to be(false) # sacrificed at the next end step, ceased to exist
    end

    it "a copy of an opponent's creature with menace, under your control" do
      game = board(alice: { battlefield: %w[Island Island Swamp], hand: ["Mirror Raid"] }, bob: { battlefield: ["Twin Herald"] })
      cast(game, "Mirror Raid", obj_id(game, "Twin Herald"))
      tap_for(game, "swamp", "B")
      2.times { tap_for(game, "island", "U") }
      pass_both(game)
      token = objects_of(game, "Twin Herald").find { engine(game).token?(it) }
      expect(token.controller).to eq(0)
      expect(engine(game).chars(token).keywords).to include(:menace)
      expect(engine(game).chars(token).legendary?).to be(true)
    end

    it "copies a card exiled from a graveyard, and a card that exiled itself to pay the cost (CR 608.2h)" do
      game = board(alice: { battlefield: %w[Swamp Swamp Swamp Swamp], hand: ["Dread Splicer"], graveyard: ["Twin Herald"] })
      cast(game, "Dread Splicer")
      4.times { tap_for(game, "swamp", "B") }
      pass_both(game)
      game.submit(type: "target", target: ids_in(game, "alice", :graveyard).first)
      pass_both(game)
      token = objects_of(game, "Twin Herald").find { it.zone == :battlefield }
      expect(engine(game).token?(token)).to be(true)
      expect(engine(game).chars(token).keyword?(:haste)).to be(true)

      game = board(alice: { battlefield: %w[Mountain Mountain Mountain], graveyard: ["Phantom Ensign"] })
      game.submit(type: "activate", object: ids_in(game, "alice", :graveyard).first, ability: "printed:0")
      3.times { tap_for(game, "mountain", "R") }
      pass_both(game)
      token = objects_of(game, "Phantom Ensign").find { it.zone == :battlefield }
      expect(engine(game).token?(token)).to be(true)
      expect(objects_of(game, "Phantom Ensign").map(&:zone)).to contain_exactly(:exile, :battlefield)
    end

    it "a token copy that leaves the battlefield ceases to exist (CR 704.5d)" do
      game = board(alice: { battlefield: %w[Island Island Swamp Mountain], hand: ["Mirror Raid", "Arc Jolt"] },
                   bob: { battlefield: ["Cheerful Greeter"] })
      cast(game, "Mirror Raid", obj_id(game, "Cheerful Greeter"))
      tap_for(game, "swamp", "B")
      2.times { tap_for(game, "island", "U") }
      pass_both(game)
      token = objects_of(game, "Cheerful Greeter").find { it.controller.zero? }
      pass_both(game) if game.state.stack.any? # its copied enter trigger
      cast(game, "Arc Jolt", token.id)
      tap_for(game, "mountain", "R")
      pass_both(game)
      expect(game.state.objects.key?(token.id)).to be(false)
      expect(objects_of(game, "Cheerful Greeter").size).to eq(1) # gone from the graveyard too
      expect(ids_in(game, "alice", :graveyard).map { game.state.object(it).card }).to contain_exactly("mirror_raid", "arc_jolt")
    end
  end

  describe "entering as a copy (CR 707.5)" do
    it "enters as a copy of the chosen permanent, not legendary, with its counters, and its enter abilities trigger" do
      game = board(alice: { battlefield: %w[Island Island], hand: ["Shifting Saboteur"] },
                   bob: { battlefield: ["Cheerful Greeter", "Twin Herald"] })
      game.state.object(obj_id(game, "Cheerful Greeter")).counters["+1/+1"] = 2
      cast(game, "Shifting Saboteur")
      2.times { tap_for(game, "island", "U") }
      pass_both(game)
      expect(game.pending_decision.kind).to eq("enter_choice")
      expect(game.legal_options).to include({ type: "dont_copy" }, { type: "copy", object: obj_id(game, "Cheerful Greeter") })
      game.submit(type: "copy", object: obj_id(game, "Cheerful Greeter"))
      copy = game.state.battlefield.map { game.state.object(it) }.find { it.controller.zero? && it.card == "cheerful_greeter" }
      expect(copy.id).to start_with("shifting_saboteur#")
      expect(copy.counters).to eq("+1/+1" => 2)
      expect(engine(game).power_toughness(copy)).to eq([4, 4])
      expect(engine(game).token?(copy)).to be(false)
      pass_both(game) # the copied enter trigger resolves
      expect(game.state.players[0].life).to eq(22)
      roundtrip(game)
      engine(game).move!(copy.id, :graveyard, reason: "test")
      expect(game.state.object(ids_in(game, "alice", :graveyard).last).card).to eq("shifting_saboteur")
    end

    it "copying a legendary permanent drops legendary; declining enters as itself" do
      game = board(alice: { battlefield: %w[Island Island], hand: ["Shifting Saboteur"] }, bob: { battlefield: ["Twin Herald"] })
      cast(game, "Shifting Saboteur")
      2.times { tap_for(game, "island", "U") }
      pass_both(game)
      game.submit(type: "copy", object: obj_id(game, "Twin Herald"))
      copy = game.state.battlefield.map { game.state.object(it) }.find { it.controller.zero? && it.card == "twin_herald" }
      expect(engine(game).chars(copy).legendary?).to be(false)

      game = board(alice: { battlefield: %w[Island Island], hand: ["Shifting Saboteur"] }, bob: { battlefield: ["Twin Herald"] })
      cast(game, "Shifting Saboteur")
      2.times { tap_for(game, "island", "U") }
      pass_both(game)
      game.submit(type: "dont_copy")
      expect(objects_of(game, "Shifting Saboteur").map(&:zone)).to eq([:graveyard]) # a 0/0 (CR 704.5f)
    end
  end

  describe "becoming a copy until end of turn (CR 707.4, 613.2a)" do
    it "an Equipment token becomes a copy of another Equipment, keeping its attachment, then reverts in cleanup" do
      game = board(alice: { battlefield: ["Island", "Island", "Island", "Island", "Gilded Blade"], hand: ["Heirloom Weaver"] })
      cast(game, "Heirloom Weaver")
      2.times { tap_for(game, "island", "U") }
      pass_both(game)
      pass_both(game) # enter trigger: create the Equipment token and attach it
      weaver = obj_id(game, "Heirloom Weaver")
      charm = game.state.battlefield.find { game.state.object(it).attached_to == weaver }
      expect(engine(game).power_toughness(weaver)).to eq([2, 2])
      game.submit(type: "activate", object: weaver, ability: "printed:1")
      game.submit(type: "target", target: obj_id(game, "Gilded Blade"))
      2.times { tap_for(game, "island", "U") }
      pass_both(game)
      expect(game.state.object(charm).card).to eq("gilded_blade")
      expect(game.state.object(charm).attached_to).to eq(weaver)
      expect(engine(game).power_toughness(weaver)).to eq([4, 1])
      expect(roundtrip(game).state.object(charm).memory).to eq(game.state.object(charm).memory)
      skip_to(game, :precombat_main, turn: 4)
      expect(game.state.object(charm).card).to start_with("woven_charm")
      expect(engine(game).power_toughness(weaver)).to eq([2, 2])
    end
  end

  describe "copying spells (CR 707.10)" do
    it "\"when you cast this spell, copy it\": the copy becomes a token as it resolves, and isn't cast (CR 608.3f)" do
      game = board(alice: { battlefield: %w[Island Island Island], hand: ["Signal Badge"] })
      cast(game, "Signal Badge")
      3.times { tap_for(game, "island", "U") }
      expect(game.state.stack.size).to eq(2) # the spell and its cast trigger
      pass_both(game)
      expect(game.state.stack.size).to eq(2) # the copy above the original
      copy = game.state.object(game.state.stack.first)
      expect(copy.memory["copy"]).to eq("spell")
      expect(roundtrip(game).state.object(copy.id).memory).to eq(copy.memory)
      pass_both(game, 2)
      badges = objects_of(game, "Signal Badge").select { it.zone == :battlefield }
      expect(badges.map { engine(game).token?(it) }).to contain_exactly(true, false)
    end

    it "a copy of a spell may get new targets; a copy that leaves the stack ceases to exist (CR 707.10a, 707.10c)" do
      game = board(alice: { battlefield: %w[Mountain Mountain Island], hand: ["Arc Jolt", "Resonant Echo"] },
                   bob: { battlefield: ["Cheerful Greeter"] })
      greeter = obj_id(game, "Cheerful Greeter")
      cast(game, "Arc Jolt", "player:bob")
      tap_for(game, "mountain", "R")
      jolt = game.state.stack.first
      cast(game, "Resonant Echo", jolt)
      tap_for(game, "island", "U")
      tap_for(game, "mountain", "R")
      pass_both(game)
      expect(game.pending_decision.kind).to eq("effect_choice")
      expect(game.legal_options).to include({ type: "target", target: "player:bob" }, { type: "target", target: greeter })
      game.submit(type: "target", target: greeter)
      copy = game.state.object(game.state.stack.first)
      expect(copy.targets).to eq([greeter])
      pass_both(game)
      expect(game.state.objects.key?(copy.id)).to be(false) # resolved into the graveyard, then ceased to exist
      expect(game.state.objects.key?(greeter)).to be(false)
      pass_both(game)
      expect(game.state.players[1].life).to eq(18)
    end

    it "the granted attack trigger needs another creature with a Communicator attached (attached_subtypes)" do
      game = board(alice: { battlefield: ["Signal Badge", "Signal Badge", "Cheerful Greeter", "Burrowing Mimic"] },
                   step: :beginning_of_combat)
      badges = objects_of(game, "Signal Badge").map(&:id)
      greeter = obj_id(game, "Cheerful Greeter")
      game.state.object(badges[0]).attached_to = greeter
      pass_both(game) # -> declare attackers
      game.submit(type: "attack", object: greeter, target: "player:bob")
      game.submit(type: "done")
      expect(game.state.stack).to be_empty # alone: no other creature with a Communicator attached

      game = board(alice: { battlefield: ["Signal Badge", "Signal Badge", "Cheerful Greeter", "Burrowing Mimic"] },
                   step: :beginning_of_combat)
      badges = objects_of(game, "Signal Badge").map(&:id)
      greeter = obj_id(game, "Cheerful Greeter")
      game.state.object(badges[0]).attached_to = greeter
      game.state.object(badges[1]).attached_to = obj_id(game, "Burrowing Mimic")
      engine(game).touch!
      pass_both(game) # -> declare attackers
      game.submit(type: "attack", object: greeter, target: "player:bob")
      game.submit(type: "done")
      expect(game.state.stack.size).to eq(1)
      pass_both(game)
      expect(engine(game).chars(greeter).keyword?(:cant_be_blocked)).to be(true)
    end
  end

  describe "casting copies of cards (CR 707.12)" do
    it "copies an exiled card twice and casts the copies one at a time without paying their mana costs" do
      game = board(alice: { battlefield: %w[Mountain Mountain Mountain Mountain], hand: ["Prismatic Recall"],
                            graveyard: ["Arc Jolt"] })
      cast(game, "Prismatic Recall", ids_in(game, "alice", :graveyard).first)
      4.times { tap_for(game, "mountain", "R") }
      pass_both(game)
      expect(game.pending_decision.kind).to eq("effect_choice")
      copies = game.legal_options.select { it[:type] == "cast" }.map { it[:object] }
      expect(copies.size).to eq(2)
      expect(copies.map { game.state.object(it).memory["copy"] }).to eq(%w[card card])
      game.submit(type: "cast", object: copies.first)
      game.submit(type: "target", target: "player:bob")
      game.submit(type: "done")
      pass_both(game)
      expect(game.state.players[1].life).to eq(18)
      expect(game.state.objects.key?(copies.last)).to be(false) # not cast: ceased to exist (CR 707.10a)
      expect(objects_of(game, "Arc Jolt").map(&:zone)).to eq([:exile]) # the original card
      expect(objects_of(game, "Prismatic Recall").map(&:zone)).to eq([:exile])
    end

    it "a card gains an ability that works only from exile: exile a card from hand, copy it, cast the copy paying" do
      game = board(alice: { battlefield: %w[Mountain Mountain Mountain Mountain], hand: ["Trickster of Stacks", "Island"],
                            library: ["Swamp", "Arc Jolt", "Island"] })
      cast(game, "Trickster of Stacks")
      3.times { tap_for(game, "mountain", "R") }
      pass_both(game)
      pass_both(game)
      expect(game.state.exile.map { game.state.object(it).card }).to contain_exactly("swamp", "arc_jolt")
      exiled = game.state.exile.find { game.state.object(it).card == "arc_jolt" }
      activations = game.legal_options.select { it[:type] == "activate" }
      expect(activations.map { it[:object] }).to eq([exiled]) # only the nonland card gained it (`for`)
      ref = activations.first[:ability]
      expect(ref).to start_with("granted:trickster_of_stacks:")
      roundtrip(game)
      game.submit(type: "activate", object: exiled, ability: ref)
      expect(game.pending_decision.kind).to eq("choose_cost")
      game.submit(type: game.legal_options.first[:type], **game.legal_options.first.except(:type))
      pass_both(game)
      expect(game.legal_options.map { it[:type] }).to include("cast", "done")
      copy = game.legal_options.find { it[:type] == "cast" }[:object]
      game.submit(type: "cast", object: copy)
      game.submit(type: "target", target: "player:bob")
      tap_for(game, "mountain", "R")
      pass_both(game)
      expect(game.state.players[1].life).to eq(18)
      expect(game.state.object(exiled).zone).to eq(:exile) # the original stays exiled
    end

    it "a cancelled cast puts the card copy back as a copy; declining leaves it to cease to exist (CR 734.1, 707.10a)" do
      game = board(alice: { battlefield: %w[Mountain Mountain Mountain Mountain], hand: ["Trickster of Stacks", "Island"],
                            library: ["Arc Jolt", "Island"] })
      cast(game, "Trickster of Stacks")
      3.times { tap_for(game, "mountain", "R") }
      pass_both(game, 2)
      ref = game.legal_options.find { it[:type] == "activate" }[:ability]
      game.submit(type: "pass")
      expect(game.legal_options.none? { it[:type] == "activate" }).to be(true) # only during its owner's turn
      game = board(alice: { battlefield: %w[Mountain Mountain Mountain Mountain], hand: ["Trickster of Stacks", "Island"],
                            library: ["Arc Jolt", "Island"] })
      cast(game, "Trickster of Stacks")
      3.times { tap_for(game, "mountain", "R") }
      pass_both(game, 2)
      exiled = game.state.exile.first
      game.submit(type: "activate", object: exiled, ability: ref)
      game.submit(type: game.legal_options.first[:type], **game.legal_options.first.except(:type))
      pass_both(game)
      copy = game.legal_options.find { it[:type] == "cast" }[:object]
      game.submit(type: "cast", object: copy)
      game.submit(type: "target", target: "player:bob")
      game.submit(type: "cancel") # declined: the copy is back in exile, then the ability finishes
      ceased = game.history.flat_map(&:events).grep(Enjine::Events::TokenCeased).map(&:object)
      expect(ceased).to include(copy) # still a card copy after the rewind, so it ceased to exist
      expect(game.state.objects.key?(copy)).to be(false)
      expect(game.state.exile).to include(exiled)
      expect(game.state.players[1].life).to eq(20)
    end
  end

  describe "changeling (CR 702.73a)" do
    it "is every creature type in every zone, for subtype filters and creature-type counts" do
      game = board(alice: { battlefield: ["Many-Faced Drifter", "Kindred Banner"], hand: ["Many-Faced Drifter"] })
      drifter = obj_id(game, "Many-Faced Drifter")
      expect(engine(game).chars(drifter).subtypes).to include(:goblin, :shapeshifter, :vorta)
      expect(engine(game).power_toughness(drifter)).to eq([2, 2])
      in_hand = ids_in(game, "alice", :hand).first
      expect(engine(game).chars(in_hand).subtypes).to include(:elf)
    end
  end
end
