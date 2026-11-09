# frozen_string_literal: true

# Validation of the copy primitives (CR 707) and the pieces they need: changeling, exile_from_hand,
# grant_ability, activated `zone`, attach `attachment` and the attached_subtypes filter.
RSpec.describe "Copy primitives (validation)" do
  def spell(*effects, targets: [])
    { "name" => "Test Spell", "mana_cost" => "{1}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects } }] }
  end

  def creature(*abilities, **extra)
    { "name" => "Test Shifter", "mana_cost" => "{1}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => abilities }.merge(extra.transform_keys(&:to_s))
  end

  def draw_ability = { "activated" => { "cost" => [{ "mana" => "{1}" }], "effects" => [{ "draw" => { "amount" => 1 } }] } }

  def errors_for(data)
    Enjine::CardDefinition.from_h(data)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  describe "create_token_copy" do
    it "accepts a target, self or a result with exceptions" do
      expect(errors_for(spell({ "create_token_copy" => { "of" => { "target" => 0 }, "amount" => 2, "tapped" => true,
                                                         "except" => { "legendary" => false, "keywords" => ["menace"],
                                                                       "types" => ["artifact"], "subtypes" => ["golem"],
                                                                       "supertypes" => ["legendary"], "name" => "Echo",
                                                                       "power" => 1, "toughness" => 1, "colors" => [] } } },
                              targets: ["creature"]))).to be_empty
      defn = Enjine::CardDefinition.from_h(creature({ "triggered" => { "when" => { "enters" => {} },
                                                                       "effects" => [{ "create_token_copy" => { "of" => "self" } }] } }))
      effect = defn.all_effects.first
      expect(effect.to_s).to eq("create 1 token copy of itself → you")
    end

    it "reports path-addressed errors" do
      errors = errors_for(spell({ "create_token_copy" => { "tapped" => 1, "except" => { "legendary" => true, "keywords" => ["zzz"],
                                                                                        "subtypes" => ["Bad Type!"],
                                                                                        "name" => "", "power" => "x",
                                                                                        "colors" => ["Q"], "wings" => 1 } } }))
      path = "abilities[0].spell.effects[0].create_token_copy"
      expect(errors).to include("#{path}.of: required", "#{path}.tapped: must be true or false",
                                "#{path}.except.legendary: must be false (\"it isn't legendary\")",
                                "#{path}.except.name: must be a non-empty string", "#{path}.except.power: must be an integer",
                                "#{path}.except: unknown parameter \"wings\"",
                                "#{path}.except.subtypes: must be a non-empty list of lowercase subtypes",
                                "#{path}.except.colors: must be a list of W, U, B, R, G ([] for colorless)")
      expect(errors.grep(/except.keywords: must be a non-empty list of keywords/)).not_to be_empty
      expect(errors_for(spell({ "create_token_copy" => { "of" => "self", "except" => "menace" } })))
        .to include(a_string_starting_with("abilities[0].spell.effects[0].create_token_copy.except: must be an object"))
    end

    it "describes its exceptions" do
      text = Enjine::Mechanics::CopyExcept.to_s("legendary" => false, "keywords" => ["menace"], "power" => 2)
      expect(text).to eq(" (except not legendary, power 2, keywords menace)")
    end
  end

  describe "become_copy, copy_spell, copy_card, cast and grant_ability" do
    it "accepts their documented examples" do
      %i[create_token_copy become_copy copy_spell copy_card cast grant_ability].each do |name|
        klass = Enjine.registry.fetch(:effect, name.to_s)
        targets = klass.example.to_s.include?("target") ? ["creature"] : []
        data = spell(klass.example, targets: targets)
        data = spell({ "exile_top" => { "amount" => 1 } }, klass.example) if klass.example.to_s.include?("result")
        expect(errors_for(data)).to eq([]), "#{name}: #{errors_for(data)}"
      end
    end

    it "reports bad durations, flags and abilities" do
      path = "abilities[0].spell.effects[0]"
      expect(errors_for(spell({ "become_copy" => { "to" => "self", "of" => "self", "duration" => "forever" } })))
        .to include("#{path}.become_copy.duration: must be one of end_of_turn, permanent")
      expect(errors_for(spell({ "copy_spell" => { "of" => "self", "new_targets" => "yes" } })))
        .to include("#{path}.copy_spell.new_targets: must be true or false")
      expect(errors_for(spell({ "grant_ability" => { "to" => "self", "duration" => "a_while" } })))
        .to include("#{path}.grant_ability.ability: required", "#{path}.grant_ability.duration: must be one of permanent, end_of_turn")
      expect(errors_for(spell({ "copy_card" => {} }))).to include("#{path}.copy_card.of: required")
    end

    it "describes themselves" do
      defn = Enjine::CardDefinition.from_h(spell(
                                             { "exile_top" => { "amount" => 1 } },
                                             { "copy_card" => { "of" => { "result" => 0 }, "amount" => 2 } },
                                             { "cast" => { "to" => { "result" => 1 } } },
                                             { "copy_spell" => { "of" => "self", "amount" => 2, "new_targets" => true } },
                                             { "become_copy" => { "to" => "self", "of" => "self", "except" => { "legendary" => false } } },
                                             { "grant_ability" => { "to" => "self", "duration" => "end_of_turn",
                                                                    "ability" => draw_ability } }
                                           ))
      texts = defn.all_effects.map(&:to_s)
      expect(texts).to include("copy the object(s) from effect #1 2 times", a_string_starting_with("you may cast a card"),
                               "copy itself 2 times (new targets) → you",
                               "becomes a copy of itself (except not legendary) (end of turn) → itself",
                               a_string_including("until end of turn"))
      expect(texts.join).not_to include(" free")
      granted = defn.all_effects.find { it.respond_to?(:granted_ability) }
      expect(defn.ability(granted.ref)).to equal(granted.granted_ability)
    end
  end

  describe "enter_as_copy" do
    it "validates its filter, exceptions and flag" do
      ok = creature({ "enter_as_copy" => { "of" => "creature", "except" => { "legendary" => false }, "with_counters" => true } })
      expect(errors_for(ok)).to be_empty
      ability = Enjine::CardDefinition.from_h(ok).abilities.first
      expect(ability.to_s).to eq("you may have it enter as a copy of a creature (except not legendary) with its counters")
      expect(ability.enters_for({})).to be_nil
      errors = errors_for(creature({ "enter_as_copy" => { "with_counters" => 1 } }))
      expect(errors).to include("abilities[0].enter_as_copy.of: required",
                                "abilities[0].enter_as_copy.with_counters: must be true or false")
    end
  end

  describe "changeling (CR 702.73a)" do
    it "makes a card every creature type in any zone" do
      printed = Enjine::CardDefinition.from_h(creature(keywords: ["changeling"])).printed_characteristics
      chars = Enjine::Mechanics::Keywords::Changeling.apply(printed)
      expect(chars.subtypes).to include(:goblin, :time_lord, :jemhadar)
    end
  end

  describe "exile_from_hand, activated zone and attach attachment" do
    it "validates the cost and the zone" do
      ok = creature({ "activated" => { "cost" => [{ "exile_from_hand" => { "count" => 2, "card" => { "types" => ["land"] } } }],
                                       "zone" => "exile", "effects" => [{ "draw" => { "amount" => 1 } }] } })
      expect(errors_for(ok)).to be_empty
      ability = Enjine::CardDefinition.from_h(ok).abilities.first
      expect(ability.zone).to eq(:exile)
      expect(ability.costs.first.to_s).to eq("Exile 2 land cards from your hand")
      path = "abilities[0].activated"
      bad = lambda do |cost, zone|
        errors_for(creature({ "activated" => { "cost" => cost, "zone" => zone, "effects" => [{ "draw" => { "amount" => 1 } }] } }))
      end
      expect(bad.call([{ "mana" => "{1}" }], "library")).to include("#{path}.zone: must be one of exile, graveyard, hand")
      expect(bad.call(["discard_self"], "exile")).to include("#{path}.zone: its costs are paid from the hand")
      expect(bad.call(["tap"], "exile")).to include("#{path}.zone: an ability of a card in the exile can't tap or sacrifice it")
      expect(bad.call([{ "exile_from_hand" => { "bogus" => 1 } }], nil))
        .to include("#{path}.cost[0].exile_from_hand: unknown parameter \"bogus\"")
    end

    it "lets attach name the attachment and a single non-target permanent" do
      ok = creature({ "triggered" => { "when" => { "enters" => {} }, "effects" => [
                      { "create_token" => { "token" => { "name" => "Test Charm", "types" => ["artifact"], "subtypes" => ["equipment"] } } },
                      { "attach" => { "to" => "self", "attachment" => { "result" => 0 } } }
                    ] } })
      expect(errors_for(ok)).to be_empty
      bad = creature({ "triggered" => { "when" => { "enters" => {} },
                                        "effects" => [{ "attach" => { "to" => { "each" => "creature" } } }] } })
      expect(errors_for(bad).first).to include("attach.to: must be {\"target\": n}, \"self\" or {\"result\": n}")
    end

    it "filters by attached subtypes" do
      filter = Enjine::Mechanics.build_entry(:filter, { "creature" => { "attached_subtypes" => ["communicator"] } }, [], "f")
      expect(filter.to_s).to eq("creature with a communicator attached")
      expect(filter.live_keys).to eq(["attached_subtypes"])
      errors = []
      Enjine::Mechanics.build_entry(:filter, { "creature" => { "attached_subtypes" => [] } }, errors, "f")
      expect(errors.first).to include("attached_subtypes: must be a non-empty list of lowercase subtypes")
    end
  end
end
