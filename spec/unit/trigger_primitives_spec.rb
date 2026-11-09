# frozen_string_literal: true

# Invented test cards only.
RSpec.describe "Trigger, delayed, reflexive and entering-choice primitives" do
  def build(category, data, path = "x", **context)
    errors = []
    built = Enjine::Mechanics.build_entry(category, data, errors, path, **context)
    [built, errors]
  end

  def errors_of(category, data, **context) = build(category, data, **context)[1]

  let(:game) do
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") { battlefield "Grizzly Bears", "Forest" }
      player("bob") { battlefield "Hill Giant" }
    end
  end
  let(:engine) { game.instance_variable_get(:@engine) }
  let(:bears) { game.state.battlefield[0] }
  let(:giant) { game.state.battlefield[2] }
  let(:source) { { "id" => bears, "card" => "grizzly_bears", "controller" => 0 } }

  describe "validation (path-addressed errors)" do
    it "rejects bad trigger parameters" do
      expect(errors_of(:trigger, { "enters" => { "untapped" => "yes" } })).to eq(["x.enters.untapped: must be true or false"])
      expect(errors_of(:trigger, { "cast" => { "self" => false } })).to eq(["x.cast.self: must be true"])
      expect(errors_of(:trigger, { "cast" => { "name" => "Bob", "mana_value" => 3 } }))
        .to eq(['x.cast.name: must be "chosen"', 'x.cast.mana_value: must be "chosen"'])
      expect(errors_of(:trigger, { "cast" => { "spell" => "artifact" } }))
        .to eq(["x.cast.spell: must be one of creature, noncreature, instant_or_sorcery or a spell filter"])
      expect(errors_of(:trigger,
                       { "cast" => { "spell" => { "wizard" => {} } } })).to include(a_string_matching(/x.cast.spell: unknown filter/))
      expect(errors_of(:trigger,
                       { "becomes_target" => { "by" => "everyone" } })).to eq(["x.becomes_target.by: must be one of opponent, you, any"])
      expect(errors_of(:trigger, { "counters_placed" => { "counter" => "Not A Counter!" } }))
        .to include(a_string_matching(/x.counters_placed.counter:/))
      expect(errors_of(:trigger, { "leaves_graveyard" => { "batched" => "sometimes" } }))
        .to eq(["x.leaves_graveyard.batched: must be true or false"])
      expect(errors_of(:trigger, { "activates_ability" => { "name" => "Bears" } })).to eq(['x.activates_ability.name: must be "chosen"'])
      expect(errors_of(:trigger, { "becomes_tapped" => { "subject" => "nobody" } }))
        .to include(a_string_matching(/x.becomes_tapped.subject: must be "self", "attached", "watched"/))
    end

    it "rejects bad abilities" do
      expect(errors_of(:ability, { "triggered" => { "when" => { "enters" => {} }, "limit" => "twice", "zone" => "hand",
                                                    "effects" => [{ "draw" => { "amount" => 1 } }] } }))
        .to eq(["x.triggered.limit: must be one of once_each_turn", "x.triggered.zone: must be one of battlefield, graveyard"])
      expect(errors_of(:ability, { "additional_triggers" => { "cause" => "sunrise" } }))
        .to eq(["x.additional_triggers.cause: must be one of you_gain_life"])
      expect(errors_of(:ability, { "choose_number" => { "min" => 5, "max" => 2 } })).to eq(["x.choose_number.max: must be at least min"])
      expect(errors_of(:ability, { "choose_card_name" => { "not" => ["wizard"] } }))
        .to include(a_string_matching(/x.choose_card_name.not: must be a list of card types/))
      expect(errors_of(:ability, { "enters_tapped_unless" => {} })).to eq(["x.enters_tapped_unless.condition: required"])
    end

    it "validates pump durations and assimilate choices (CR 611.2a, 701.72c)" do
      expect(errors_of(:effect, { "pump" => { "power" => 1, "toughness" => 1, "to" => "self", "duration" => "forever" } }))
        .to eq(["x.pump.duration: must be one of end_of_turn, until_your_next_turn"])
      expect(errors_of(:effect, { "assimilate" => { "to" => "exiled_with", "choose" => "yes" } }))
        .to eq(["x.assimilate.choose: must be true or false"])
      expect(errors_of(:effect, { "assimilate" => { "to" => "exiled_with", "for" => { "types" => ["planet"] } } }))
        .to all(start_with("x.assimilate.for"))
      pump, errors = build(:effect, { "pump" => { "power" => -1, "toughness" => 0, "to" => "self", "duration" => "until_your_next_turn" } })
      expect([pump.to_s, errors]).to eq(["-1/+0 until your next turn → itself", []])
      assimilate, = build(:effect, { "assimilate" => { "to" => "exiled_with", "for" => { "types" => ["creature"] }, "choose" => true } })
      expect(assimilate.to_s).to start_with("assimilate one ")
      delayed, errors = build(:effect, { "delayed_trigger" => { "when" => { "step_begins" => { "step" => "beginning_of_combat" } },
                                                                "this_turn" => "once", "effects" => [{ "draw" => { "amount" => 1 } }] } })
      expect([delayed.class.primitive_name, errors]).to eq(["delayed_trigger", []])
    end

    it "rejects bad effect parameters" do
      expect(errors_of(:effect, { "draw" => { "amount" => 1, "to" => { "triggering" => "planet" } } }))
        .to eq(["x.draw.to.triggering: must be one of object, player, targets, ability"])
      expect(errors_of(:effect, { "return_to_battlefield" => { "to" => "watched", "counters" => [] } }))
        .to eq(["x.return_to_battlefield.counters: must be an object of counter name => count"])
      expect(errors_of(:effect, { "return_to_battlefield" => { "to" => "watched", "counters" => { "Bad!" => 0 } } }))
        .to include(a_string_matching(/counters.Bad!: /), "x.return_to_battlefield.counters.Bad!: must be a positive integer")
      expect(errors_of(:effect, { "delayed_trigger" => { "when" => { "enters" => {} }, "this_turn" => "yes",
                                                         "effects" => [{ "draw" => { "amount" => 1 } }] } }))
        .to eq(["x.delayed_trigger.this_turn: must be true, false or \"once\""])
      expect(errors_of(:effect,
                       { "reflexive_trigger" => { "effects" => [] } })).to eq(["x.reflexive_trigger.effects: needs at least one effect"])
      expect(errors_of(:effect, { "may" => { "chooser" => "nobody", "effects" => [{ "draw" => { "amount" => 1 } }] } }))
        .to include(a_string_matching(/x.may.chooser: must be/))
    end
  end

  describe "descriptions" do
    it "describes triggers" do
      texts = [{ "enters" => { "untapped" => true } }, { "cast" => { "self" => true } },
               { "cast" => { "controller" => "opponent", "name" => "chosen", "mana_value" => "chosen" } },
               { "cast" => { "controller" => "any" } },
               { "cast" => { "spell" => { "spell" => { "subtypes" => ["saga"] } } } },
               { "becomes_tapped" => { "subject" => "watched" } }, { "counters_placed" => {} },
               { "counters_placed" => { "counter" => "+1/+1" } }, { "becomes_target" => { "by" => "you" } },
               { "becomes_target" => {} }, { "leaves_graveyard" => {} },
               { "leaves_graveyard" => { "controller" => "opponent", "card" => "creature", "batched" => true } },
               { "activates_ability" => {} }, { "activates_ability" => { "controller" => "any", "name" => "chosen" } }]
              .map { build(:trigger, it)[0].to_s }
      expect(texts).to eq(["When this enters untapped", "When you cast this spell",
                           "Whenever an opponent casts a spell with the chosen name with mana value equal to the chosen number",
                           "Whenever a player casts a spell", "Whenever you cast a saga spell",
                           "Whenever that object becomes tapped", "Whenever one or more counters are put on this",
                           "Whenever one or more +1/+1 counters are put on this",
                           "Whenever this becomes the target of a spell or ability you control",
                           "Whenever this becomes the target of a spell or ability", "Whenever a card leaves your graveyard",
                           "Whenever one or more creatures leave an opponent's graveyard", "Whenever you activate an ability",
                           "Whenever a player activates an ability with the chosen name"])
    end

    it "describes abilities and effects" do
      abilities = [{ "triggered" => { "when" => { "dies" => {} }, "limit" => "once_each_turn", "zone" => "graveyard",
                                      "effects" => [{ "draw" => { "amount" => 1 } }] } },
                   { "additional_triggers" => { "cause" => "you_gain_life" } },
                   { "choose_number" => { "max" => 4 } }, { "choose_card_name" => { "not" => ["land"] } },
                   { "enters_tapped_unless" => { "condition" => { "your_turn" => true } } }].map { build(:ability, it)[0].to_s }
      expect(abilities).to eq(["When this dies, draw 1 → you (only once each turn) (from a graveyard)",
                               "triggered abilities of your permanents that trigger from you gaining life trigger an additional time",
                               "as this enters, choose a number from 0 to 4", "as this enters, choose a nonland card name",
                               "enters tapped unless it's your turn"])
      effects = [{ "delayed_trigger" => { "when" => { "dies" => { "subject" => "watched" } }, "watch" => { "target" => 0 },
                                          "this_turn" => true,
                                          "effects" => [{ "draw" => { "amount" => { "triggering" => "amount" } } }] } },
                 { "reflexive_trigger" => { "targets" => ["any_target"],
                                            "effects" => [{ "deal_damage" => { "amount" => 1, "to" => { "target" => 0 } } }] } },
                 { "may" => { "chooser" => "active_player", "effects" => [{ "draw" => { "amount" => 1 } }] } },
                 { "return_to_battlefield" => { "to" => "watched", "counters" => { "+1/+1" => 1 } } },
                 { "another_counter" => { "to" => { "triggering" => "object" } } },
                 { "lose_life" => { "amount" => 1, "to" => { "triggering" => "player" },
                                    "if" => { "triggering" => { "spell" => { "subtypes" => ["saga"] } } } } }]
                .map { build(:effect, it, targets_count: 1)[0].to_s }
      expect(effects).to eq(["delayed this turn: When that object dies, draw that many → you (watching target #1)",
                             "reflexive: When you do, deal damage 1 → target #1",
                             "active_player may have: draw 1 → you",
                             "return to the battlefield with 1 +1/+1 counter(s) → the watched object(s)",
                             "another counter of a kind already there → the triggering object",
                             "lose life 1 → the triggering player"])
      condition = Enjine::Mechanics::Condition.build({ "triggering" => "creature" }, [], "c")
      expect(condition.to_s).to eq("it's a creature")
    end
  end

  describe "runtime details" do
    def ctx(object = nil) = Enjine::Mechanics::EffectContext.new(0, bears, object, [], [])

    it "selects nothing without a triggering player or watched objects, and \"that many\" is 0" do
      selector = Enjine::Mechanics::Selector.build({ "triggering" => "player" }, [], "s", targets_count: 0)
      expect(selector.resolve(engine, ctx)).to eq([])
      expect(Enjine::Mechanics::Selector.build("watched", [], "s", targets_count: 0).resolve(engine, ctx)).to eq([])
      expect(Enjine::Mechanics::Amount.build({ "triggering" => "amount" }, [], "a", targets_count: 0).value(engine, ctx)).to eq(0)
      condition = Enjine::Mechanics::Condition.build({ "triggering" => "creature" }, [], "c")
      expect(condition.true?(engine, ctx)).to be(false)
    end

    it "matches counters placed only for the subject and the named counter" do
      trigger = build(:trigger, { "counters_placed" => { "counter" => "+1/+1" } })[0]
      placed = ->(obj, kind) { Enjine::Events::CountersChanged.new(object: obj, counter: kind, from: 0, to: 1) }
      expect(trigger.match?(engine, placed.call(bears, "+1/+1"), source)).to be(true)
      expect(trigger.match?(engine, placed.call(bears, "shield"), source)).to be(false)
      expect(trigger.match?(engine, placed.call(giant, "+1/+1"), source)).to be(false)
      any = build(:trigger, { "counters_placed" => {} })[0]
      entered = Enjine::Events::ZoneChanged.new(card: "grizzly_bears", old_id: "x", new_id: bears, owner: "alice", from: "hand",
                                                to: "battlefield", reason: "x")
      game.state.object(bears).counters.merge!("shield" => 1, "+1/+1" => 2)
      expect(any.occurrences(engine, entered, source).first).to include("amount" => 3)
    end

    it "matches targets only on the battlefield and only for the subject" do
      trigger = build(:trigger, { "becomes_target" => {} })[0]
      cast = ->(targets) { Enjine::Events::SpellCast.new(player: "bob", object: "z", card: "lightning_bolt", targets: targets) }
      expect(trigger.match?(engine, cast.call(["player:alice", giant]), source)).to be(false)
      expect(trigger.occurrences(engine, cast.call([bears, bears]), source).size).to eq(1)
    end

    it "matches activated abilities by source filter and controller" do
      trigger = build(:trigger, { "activates_ability" => { "controller" => "opponent", "source" => "creature" } })[0]
      activated = lambda do |player, card|
        Enjine::Events::AbilityActivated.new(player: player, object: "a", card: card, source: "s", ability: "printed:0", targets: [])
      end
      expect(trigger.match?(engine, activated.call("bob", "prodigal_pyromancer"), source)).to be(true)
      expect(trigger.match?(engine, activated.call("alice", "prodigal_pyromancer"), source)).to be(false)
      expect(trigger.match?(engine, activated.call("bob", "arc_lantern"), source)).to be(false)
    end

    it "a chosen-value match needs a choice to have been made" do
      trigger = build(:trigger, { "cast" => { "controller" => "any", "mana_value" => "chosen" } })[0]
      event = Enjine::Events::SpellCast.new(player: "bob", object: "z", card: "lightning_bolt", targets: [])
      expect(trigger.match?(engine, event, source)).to be(false)
      game.state.object(bears).memory["chosen_number"] = 1
      expect(trigger.match?(engine, event, source)).to be(true)
    end

    it "an additional-trigger ability ignores triggered abilities of other players' permanents" do
      ability = build(:ability, { "additional_triggers" => { "cause" => "you_gain_life" } })[0]
      gained = Enjine::Events::LifeChanged.new(player: "alice", from: 20, to: 21)
      holder = game.state.object(bears)
      expect(ability.additional_trigger?(engine, gained, holder, source)).to be(true)
      expect(ability.additional_trigger?(engine, gained, holder, source.merge("controller" => 1))).to be(false)
    end
  end
end
