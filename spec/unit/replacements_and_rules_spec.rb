# frozen_string_literal: true

# Validation and descriptions of the replacement, prevention, player-rule, control, combat-restriction,
# fight/bite and counter-removal primitives.
RSpec.describe "Replacement and rules primitives" do
  def errors_for(card)
    Enjine::CardDefinition.from_h(card)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def creature(*abilities, keywords: [])
    { "name" => "Test Beast", "mana_cost" => "{2}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "abilities" => abilities, "keywords" => keywords }
  end

  def spell(*effects, targets: [])
    { "name" => "Test Spell", "mana_cost" => "{1}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects } }] }
  end

  def ability_text(data) = Enjine::CardDefinition.from_h(creature(data)).abilities.first.to_s
  def effect_text(data, targets: []) = Enjine::CardDefinition.from_h(spell(data, targets: targets)).spell_ability.effects.first.to_s

  describe "static replacement abilities" do
    it "describe themselves" do
      expect(ability_text({ "draw_replacement" => { "amount" => 2 } })).to eq("if you would draw a card, draw 2 instead")
      expect(ability_text({ "destroy_replacement" => { "affects" => { "each" => "creature", "controller" => "you", "other" => true },
                                                       "remove_counters" => "+1/+1", "remove_damage" => true } }))
        .to eq("if other creatures you control would be destroyed, instead remove all +1/+1 counters and remove all damage")
      expect(ability_text({ "token_replacement" => { "token" => "Clue" } }))
        .to eq("if tokens would be created under your control, that many Clue tokens are created instead")
      expect(ability_text({ "enters_untapped" => { "affects" => { "each" => "land", "controller" => "you" } } }))
        .to eq("lands you control enter untapped")
      expect(ability_text({ "enters_attacking" => { "affects" => { "each" => { "creature" => { "token" => true } } } } }))
        .to eq("token creatures enter tapped and attacking while you control an attacking creature")
    end

    it "report path-addressed errors" do
      expect(errors_for(creature({ "draw_replacement" => { "amount" => 1 } })))
        .to include(a_string_matching(/abilities\[0\]\.draw_replacement\.amount: must be an integer >= 2/))
      expect(errors_for(creature({ "destroy_replacement" => { "affects" => "creature" } })))
        .to include(a_string_matching(/destroy_replacement\.affects: must be \{"each"/),
                    a_string_matching(%r{destroy_replacement: needs remove_counters and/or remove_damage}))
      expect(errors_for(creature({ "destroy_replacement" => { "affects" => { "each" => "creature", "controller" => "me" },
                                                              "remove_counters" => "Bad Name!" } })))
        .to include(a_string_matching(/affects\.controller: must be one of you, opponent, any/),
                    a_string_matching(/remove_counters: must be a counter name/))
      expect(errors_for(creature({ "token_replacement" => { "token" => "Gizmo" } })))
        .to include(a_string_matching(/token_replacement\.token: must be a predefined token/))
      expect(errors_for(creature({ "token_replacement" => { "token" => { "name" => "Blob" } } })))
        .to include(a_string_matching(/token_replacement\.token\.types: must be a non-empty list/))
      expect(errors_for(creature({ "enters_untapped" => { "affects" => { "each" => "land", "foo" => 1 } } })))
        .to include(a_string_matching(/enters_untapped\.affects: unknown parameter "foo"/))
    end

    it "register a replacement's token with the card, so catalogs know it" do
      defn = Enjine::CardDefinition.from_h(creature({ "token_replacement" => { "token" => "Food" } }))
      expect(defn.token_definitions.map(&:name)).to eq(["Food"])
    end
  end

  describe "replacement and rules effects" do
    it "describe themselves" do
      expect(effect_text({ "counter_bonus" => {} })).to eq("until end of turn, counters put on your permanents: that many plus 1")
      expect(effect_text({ "exile_if_dies" => { "to" => { "target" => 0 } } }, targets: ["creature"]))
        .to eq("if it would die this turn, exile it instead → target #1")
      expect(effect_text("exile_this_spell")).to eq("exile this spell")
      expect(effect_text({ "player_rule" => { "rule" => "hexproof" } })).to eq("hexproof (end of turn) → you")
      expect(effect_text("win_game")).to eq("win the game → you")
      expect(effect_text({ "lose_game" => { "to" => "each_opponent" } })).to eq("lose the game → each opponent")
      expect(effect_text("extra_turn")).to eq("take an extra turn after this one → you")
    end

    it "report path-addressed errors" do
      expect(errors_for(spell({ "player_rule" => { "rule" => "fly" } })))
        .to include(a_string_matching(/effects\[0\]\.player_rule\.rule: must be one of hexproof/))
      expect(errors_for(spell({ "player_rule" => { "rule" => "cant_sacrifice", "duration" => "forever" } })))
        .to include(a_string_matching(/player_rule\.rule: cant_sacrifice needs a static ability/),
                    a_string_matching(/player_rule\.duration: must be one of end_of_turn, until_your_next_turn/))
      expect(errors_for(spell({ "extra_turn" => { "if" => { "began_extra_turn" => false }, "amount" => 2 } })))
        .to include(a_string_matching(/extra_turn: unknown parameter "amount"/))
    end
  end

  describe "the player_rule static ability" do
    it "describes itself and validates its filter" do
      expect(ability_text({ "player_rule" => { "rule" => "cant_lose_for_life" } })).to eq("you: cant lose for life")
      expect(ability_text({ "player_rule" => { "rule" => "cant_sacrifice", "affects" => "each", "filter" => "artifact" } }))
        .to eq("each player: cant sacrifice (artifact)")
      expect(ability_text({ "player_rule" => { "rule" => "hexproof", "affects" => "opponents" } })).to eq("your opponents: hexproof")
      expect(ability_text({ "player_rule" => { "rule" => "cant_sacrifice", "filter" => { "permanent" => { "token" => true } } } }))
        .to eq("you: cant sacrifice (token permanent)")
      expect(errors_for(creature({ "player_rule" => { "rule" => "cant_sacrifice" } })))
        .to include(a_string_matching(/player_rule\.filter: required/))
      expect(errors_for(creature({ "player_rule" => { "rule" => "hexproof", "filter" => "land", "affects" => "all" } })))
        .to include(a_string_matching(/player_rule\.filter: only for cant_sacrifice/),
                    a_string_matching(/player_rule\.affects: must be one of you, opponents, each/))
    end
  end

  describe "combat restrictions" do
    it "describe themselves and validate" do
      expect(ability_text({ "cant_be_blocked_by" => { "filter" => { "creature" => { "power" => { "at_most" => 2 } } } } }))
        .to eq("can't be blocked by creature with power 2 or less")
      expect(ability_text({ "cant_be_blocked_by" => { "filter" => "creature" } })).to eq("can't be blocked by creature")
      expect(ability_text({ "cant_be_targeted_by" => { "abilities_from" => { "types" => ["artifact"] } } }))
        .to eq("can't be the target of abilities from artifact sources opponents control")
      expect(errors_for(creature({ "cant_be_blocked_by" => {} }))).to include(a_string_matching(/cant_be_blocked_by\.filter: required/))
      expect(errors_for(creature({ "cant_be_targeted_by" => {} })))
        .to include(a_string_matching(/cant_be_targeted_by\.abilities_from: required/))
      artifact = creature({ "cant_be_blocked_by" => { "filter" => "creature" } }).merge("types" => ["artifact"]).except("power",
                                                                                                                        "toughness")
      expect(errors_for(artifact)).to include(a_string_matching(/cant_be_blocked_by abilities need a creature card/))
    end
  end

  describe "fight, bite, counters, damage, control and subtypes" do
    it "describe themselves" do
      two = %w[creature creature]
      expect(effect_text({ "fight" => { "to" => { "target" => 0 }, "with" => { "target" => 1 } } }, targets: two))
        .to eq("target #1 fights target #2")
      expect(effect_text({ "bite" => { "from" => { "target" => 0 }, "to" => { "target" => 1 } } }, targets: two))
        .to eq("target #1 each deal damage equal to their power → target #2")
      expect(effect_text({ "remove_counters" => { "counter" => "+1/+1", "amount" => 2, "to" => "self" } }))
        .to eq("remove 2 +1/+1 counter(s) → itself")
      expect(effect_text({ "remove_all_counters" => { "to" => "self" } })).to eq("remove all counters → itself")
      expect(effect_text({ "remove_damage" => { "to" => "self" } })).to eq("remove all damage → itself")
      expect(effect_text({ "gain_control" => { "to" => { "target" => 0 }, "duration" => "end_of_turn" } }, targets: ["creature"]))
        .to eq("you gains control until end of turn → target #1")
      expect(effect_text({ "gain_control" => { "to" => { "target" => 0 }, "gains" => "each_opponent" } }, targets: ["creature"]))
        .to eq("each opponent gains control → target #1")
      expect(effect_text({ "add_subtypes" => { "subtypes" => ["warrior"], "to" => "self" } }))
        .to eq("becomes warrior in addition until end of turn → itself")
    end

    it "report path-addressed errors" do
      expect(errors_for(spell({ "fight" => { "to" => { "target" => 0 } } }, targets: ["creature"])))
        .to include(a_string_matching(/effects\[0\]\.fight\.with: required/))
      expect(errors_for(spell({ "bite" => { "from" => { "target" => 3 }, "to" => { "target" => 0 } } }, targets: ["creature"])))
        .to include(a_string_matching(/bite\.from\.target: must refer to one of the 1 declared targets/))
      expect(errors_for(spell({ "remove_counters" => { "counter" => "Bad!", "amount" => 1, "to" => "self" } })))
        .to include(a_string_matching(/remove_counters\.counter: must be a counter name/))
      expect(errors_for(spell({ "remove_all_counters" => { "counter" => "Bad!", "to" => "self" } })))
        .to include(a_string_matching(/remove_all_counters\.counter: must be a counter name/))
      expect(errors_for(spell({ "gain_control" => { "to" => "self", "duration" => "a_while" } })))
        .to include(a_string_matching(/gain_control\.duration: must be one of permanent, end_of_turn/))
      expect(errors_for(spell({ "add_subtypes" => { "subtypes" => [], "to" => "self" } })))
        .to include(a_string_matching(/add_subtypes\.subtypes: must be a non-empty list of lowercase subtypes/))
    end
  end

  describe "the began_extra_turn condition" do
    it "describes itself" do
      condition = Enjine::Mechanics::Condition.build({ "began_extra_turn" => true }, [], "if")
      expect(condition.to_s).to eq("you've begun an extra turn this game")
      expect(Enjine::Mechanics::Condition.build({ "began_extra_turn" => false }, [], "if").to_s)
        .to eq("you haven't begun an extra turn this game")
    end
  end
end
