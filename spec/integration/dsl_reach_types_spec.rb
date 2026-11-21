# frozen_string_literal: true

# Setting card types (CR 205.1a) and creature types (CR 205.3d) from an effect, and returning a card as something
# else from the moment it enters (CR 614.1c): docs/plans/dsl-gaps.md, ranking of 2026-11-20, change 5.
RSpec.describe "DSL reach: become set_types, creature-type forms, return as" do
  def engine(game) = game.instance_variable_get(:@engine)
  def pay(game) = (game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost")
  def chars(game, card) = engine(game).chars(obj_id(game, card))

  def monitor_findings(game)
    Enjine::RulesMonitor.new(game)
                        .check!(Enjine::HistoryEntry.new(seq: 0, turn: 3, step: "x", player: nil, kind: nil, option: nil, events: []))
  end

  def spell(name, effects, targets: ["creature"])
    { "name" => name, "mana_cost" => "{B}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects } }] }
  end

  # Enduring-style: "When this creature dies, if it was a creature, return it to the battlefield under its owner's
  # control. It's an enchantment. (It's not a creature.)"
  let(:lasting_fox) do
    { "name" => "Lasting Fox", "mana_cost" => "{2}{W}", "types" => %w[enchantment creature], "subtypes" => ["fox"],
      "power" => 3, "toughness" => 3,
      "abilities" => [{ "triggered" => { "when" => { "dies" => {} }, "if" => { "triggering" => "creature" },
                                         "effects" => [{ "return_to_battlefield" => {
                                           "to" => { "triggering" => "object" }, "as" => { "set_types" => ["enchantment"] }
                                         } }] } }] }
  end
  let(:greeter) do
    { "name" => "Creature Greeter", "mana_cost" => "{G}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "enters" => { "subject" => { "each" => "creature" } } },
                                         "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
  end
  let(:doom) { spell("Doom Bolt", [{ "destroy" => { "to" => { "target" => 0 } } }]) }
  let(:unmake) { spell("Unmake", [{ "destroy" => { "to" => { "target" => 0 } } }], targets: ["permanent"]) }
  let(:treasure_curse) do
    spell("Treasure Curse", [{ "become" => { "set_types" => ["artifact"], "subtypes" => ["treasure"], "loses_abilities" => true,
                                             "duration" => "indefinite", "to" => { "target" => 0 } } }])
  end
  let(:blank_slate) { spell("Blank Slate", [{ "become" => { "creature_types" => [], "to" => { "target" => 0 } } }]) }
  let(:every_kin) { spell("Every Kin", [{ "become" => { "all_creature_types" => true, "to" => { "target" => 0 } } }]) }

  def board(hand, battlefield: [])
    build_game(catalog_with(lasting_fox, greeter, doom, unmake, treasure_curse, blank_slate, every_kin)) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: { B: 2 }) do
        battlefield(*battlefield) unless battlefield.empty?
        hand(*Array(hand))
        library "Swamp", count: 5
      end
      player("bob") { library "Swamp", count: 5 }
    end
  end

  def cast_at(game, card, target)
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: "alice"))
    game.submit(type: "target", target: obj_id(game, target))
    pay(game)
    game.submit(type: "pass") until game.state.stack.empty? && game.pending_decision.kind == "priority"
  end

  describe "return_to_battlefield as (CR 614.1c, 205.1a)" do
    it "returns a dead creature as only an enchantment, without its creature types or power" do
      game = board("Doom Bolt", battlefield: ["Lasting Fox"])
      cast_at(game, "Doom Bolt", "Lasting Fox")
      fox = chars(game, "Lasting Fox")
      expect(fox.types).to eq([:enchantment])
      expect(fox.subtypes).to be_empty
      expect([fox.power, fox.toughness]).to eq([nil, nil])
      expect(monitor_findings(game)).to be_empty
    end

    it "is an enchantment as it enters: 'whenever a creature enters' doesn't see it" do
      game = board("Doom Bolt", battlefield: ["Lasting Fox", "Creature Greeter"])
      cast_at(game, "Doom Bolt", "Lasting Fox")
      expect(game.state.zone_list(:battlefield, 0).map { game.state.object(it).card }).to include("lasting_fox")
      expect(game.state.players[0].life).to eq(20)
    end

    it "stays an enchantment through the turn, and put into the graveyard as a noncreature it stays there (CR 700.4)" do
      game = board(["Doom Bolt", "Unmake"], battlefield: ["Lasting Fox"])
      cast_at(game, "Doom Bolt", "Lasting Fox")
      engine(game).cleanup_turn!
      expect(chars(game, "Lasting Fox").creature?).to be(false)
      cast_at(game, "Unmake", "Lasting Fox")
      expect(game.state.zone_list(:graveyard, 0).map { game.state.object(it).card }).to include("lasting_fox")
      expect(game.state.battlefield).to be_empty
    end

    it "validates and reads as the card does" do
      text = Enjine::CardDefinition.from_h(lasting_fox).abilities.first.to_s
      expect(text).to include("return to the battlefield as it becomes only enchantment")
      bad = lambda do |as|
        spell("Bad Return", [{ "return_to_battlefield" => { "to" => { "target" => 0 }, "as" => as } }])
      end
      expect { Enjine::CardDefinition.from_h(bad.call({ "abilities" => [] })) }
        .to raise_error(Enjine::InvalidCardDefinition, /as: unknown parameter "abilities"/)
      expect { Enjine::CardDefinition.from_h(bad.call("enchantment")) }
        .to raise_error(Enjine::InvalidCardDefinition, /as: must be an object/)
      expect { Enjine::CardDefinition.from_h(bad.call({ "set_types" => ["instant"] })) }
        .to raise_error(Enjine::InvalidCardDefinition, /set_types: must be a non-empty list of types/)
    end
  end

  describe "become set_types (CR 205.1a)" do
    it "makes a creature a Treasure artifact that is no longer a creature" do
      game = board("Treasure Curse", battlefield: ["Grizzly Bears"])
      cast_at(game, "Treasure Curse", "Grizzly Bears")
      bears = chars(game, "Grizzly Bears")
      expect(bears.types).to eq([:artifact])
      expect(bears.subtypes).to eq([:treasure])
      expect(bears.power).to be_nil
      expect(monitor_findings(game)).to be_empty
    end

    it "applies in timestamp order with types added later (CR 613.7a)" do
      game = board("Treasure Curse", battlefield: ["Grizzly Bears"])
      cast_at(game, "Treasure Curse", "Grizzly Bears")
      bears = obj_id(game, "Grizzly Bears")
      ctx = Enjine::Mechanics::EffectContext.new(0, bears, bears, [], [])
      engine(game).add_continuous_effect!("add_types", ctx, [bears], "types" => ["creature"], "supertypes" => [], "subtypes" => [])
      expect(engine(game).chars(bears).types).to contain_exactly(:artifact, :creature)
      expect(engine(game).chars(bears).power).to eq(2) # printed P/T again (CR 301.7b)
    end
  end

  describe "creature-type forms (CR 205.3d)" do
    it "creature_types [] loses all creature types and keeps it a creature" do
      game = board("Blank Slate", battlefield: ["Grizzly Bears"])
      cast_at(game, "Blank Slate", "Grizzly Bears")
      expect(chars(game, "Grizzly Bears").subtypes).to be_empty
      expect(chars(game, "Grizzly Bears").creature?).to be(true)
    end

    it "all_creature_types gives every creature type" do
      game = board("Every Kin", battlefield: ["Grizzly Bears"])
      cast_at(game, "Every Kin", "Grizzly Bears")
      expect(chars(game, "Grizzly Bears").subtypes).to include(:bear, :elf, :zombie, :sliver)
    end

    it "reads as the card does and refuses both forms at once" do
      expect(Enjine::CardDefinition.from_h(blank_slate).abilities.first.to_s).to include("becomes no creature types")
      expect(Enjine::CardDefinition.from_h(every_kin).abilities.first.to_s).to include("becomes all creature types")
      expect(Enjine::CardDefinition.from_h(treasure_curse).abilities.first.to_s).to include("only artifact")
      both = spell("Both", [{ "become" => { "creature_types" => ["elf"], "all_creature_types" => true, "to" => { "target" => 0 } } }])
      expect { Enjine::CardDefinition.from_h(both) }
        .to raise_error(Enjine::InvalidCardDefinition, /creature_types and all_creature_types exclude each other/)
      wrong = spell("Wrong", [{ "become" => { "all_creature_types" => false, "to" => { "target" => 0 } } }])
      expect { Enjine::CardDefinition.from_h(wrong) }.to raise_error(Enjine::InvalidCardDefinition, /all_creature_types: must be true/)
    end
  end
end
