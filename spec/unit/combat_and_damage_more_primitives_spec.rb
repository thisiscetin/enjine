# frozen_string_literal: true

# Validation and descriptions of block-only restrictions, first-attack triggers, attack restrictions of added
# combats, prevention follow-ups and chosen sources, damage effects tied to players and ending the turn.
RSpec.describe "Combat and damage primitives (more)" do
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

  def trigger(data) = creature({ "triggered" => { "when" => data, "effects" => [{ "draw" => { "amount" => 1, "to" => "you" } }] } })
  def ability_text(data) = Enjine::CardDefinition.from_h(creature(data)).abilities.first.to_s
  def trigger_text(data) = Enjine::CardDefinition.from_h(trigger(data)).abilities.first.trigger.to_s
  def effect_text(data, targets: []) = Enjine::CardDefinition.from_h(spell(data, targets: targets)).spell_ability.effects.first.to_s

  let(:gain) { [{ "gain_life" => { "amount" => 2, "to" => "you" } }] }

  it "describe themselves" do
    expect(ability_text({ "can_block_only" => { "filter" => { "creature" => { "keywords" => ["flying"] } } } }))
      .to start_with("can block only")
    expect(ability_text({ "can_block_only" => { "filter" => "creature" } })).to eq("can block only creature")
    expect(trigger_text({ "attacks" => { "first_time_this_turn" => true } })).to eq("Whenever this attacks for the first time each turn")
    expect(trigger_text({ "player_attacks" => { "attacking_power" => { "at_least" => 12 }, "first_time_this_turn" => true } }))
      .to eq("Whenever you attack with total power 12 or greater for the first time each turn")
    expect(trigger_text({ "player_attacks" => { "controller" => "opponent" } })).to eq("Whenever an opponent attacks")
    expect(effect_text({ "additional_phases" => { "phases" => ["combat"], "attackers" => { "creature" => { "types" => ["land"] } } } }))
      .to start_with("after this phase, additional combat phase (only")
    expect(ability_text({ "prevent_damage" => { "to" => "self", "then" => gain } })).to start_with("prevent all damage to this, then")
    expect(ability_text({ "exile_if_dies" => { "affects" => { "each" => "creature" }, "then" => gain } }))
      .to include("exile it instead, then")
    expect(effect_text({ "prevent_damage" => { "to" => "you", "by" => "chosen_source", "next_time" => true, "then" => gain } }))
      .to start_with("prevent the next time damage to you by a source of your choice then")
    expect(effect_text({ "prevent_damage" => { "to_each" => { "each" => "creature", "controller" => "you" } } }))
      .to start_with("prevent all damage to creature")
    expect(effect_text({ "damage_replacement" => { "to" => { "triggering" => "player" }, "permanents" => true, "multiply" => 2 } }))
      .to eq("damage to the triggering player and their permanents: 2 times that damage instead")
    expect(effect_text({ "damage_replacement" => { "to" => "each_opponent", "combat" => "combat", "plus" => 1 } }))
      .to end_with("that much plus 1 instead")
    expect(effect_text("end_the_turn")).to eq("end the turn")
    expect(effect_text({ "reflexive_trigger" => { "if" => { "your_turn" => true }, "effects" => gain } }))
      .to start_with("reflexive:")
  end

  it "report path-addressed errors" do
    expect(errors_for(creature({ "can_block_only" => {} }))).to include("abilities[0].can_block_only.filter: required")
    expect(errors_for(creature({ "can_block_only" => { "filter" => "nope" } })))
      .to include(a_string_starting_with("abilities[0].can_block_only.filter: unknown filter"))
    expect(errors_for(trigger({ "attacks" => { "first_time_this_turn" => "yes" } })))
      .to include("abilities[0].triggered.when.attacks.first_time_this_turn: must be true or false")
    expect(errors_for(trigger({ "player_attacks" => { "attacking_power" => 12, "first_time_this_turn" => 1 } })))
      .to include("abilities[0].triggered.when.player_attacks.attacking_power: must be {\"at_least\": n}",
                  "abilities[0].triggered.when.player_attacks.first_time_this_turn: must be true or false")
    expect(errors_for(spell({ "additional_phases" => { "phases" => ["combat"], "attackers" => "nope" } })))
      .to include(a_string_starting_with("abilities[0].spell.effects[0].additional_phases.attackers: unknown filter"))
    expect(errors_for(creature({ "prevent_damage" => { "to" => "self", "then" => [] } })))
      .to include("abilities[0].prevent_damage.then: needs at least one effect")
    expect(errors_for(creature({ "exile_if_dies" => { "affects" => { "each" => "creature" }, "then" => [{ "nope" => {} }] } })))
      .to include(a_string_starting_with("abilities[0].exile_if_dies.then[0]: unknown effect"))
    expect(errors_for(spell({ "prevent_damage" => { "to_each" => "self", "next" => 2, "next_time" => true } })))
      .to include("abilities[0].spell.effects[0].prevent_damage.to_each: must be a damage scope {\"each\": filter, \"controller\": ...}",
                  "abilities[0].spell.effects[0].prevent_damage: next and next_time can't be combined")
    expect(errors_for(spell({ "prevent_damage" => { "by" => "chosen_source", "next_time" => "once" } })))
      .to include("abilities[0].spell.effects[0].prevent_damage.next_time: must be true or false")
    expect(errors_for(spell({ "damage_replacement" => { "to" => "you", "multiply" => 2, "plus" => 1, "duration" => "forever",
                                                        "permanents" => 1 } })))
      .to include("abilities[0].spell.effects[0].damage_replacement: needs exactly one of multiply, plus",
                  "abilities[0].spell.effects[0].damage_replacement.duration: must be one of end_of_turn, until_your_next_turn",
                  "abilities[0].spell.effects[0].damage_replacement.permanents: must be true or false")
    expect(errors_for(spell({ "end_the_turn" => { "x" => 1 } })))
      .to include("abilities[0].spell.effects[0].end_the_turn: unknown parameter \"x\"")
    expect(errors_for(creature(keywords: ["keeps_damage"]))).to eq([]) # the keyword exists
    expect(errors_for(creature({ "static" => { "affects" => { "each" => { "creature" => { "entered_this_turn" => "no" } } },
                                               "pump" => { "power" => 1, "toughness" => 0 } } })))
      .to include(a_string_ending_with("entered_this_turn: must be true or false"))
  end
end
