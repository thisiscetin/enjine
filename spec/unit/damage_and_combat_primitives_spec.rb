# frozen_string_literal: true

# Validation and descriptions of the damage replacement/prevention, damage trigger, combat flag,
# additional phase and token/dying replacement primitives.
RSpec.describe "Damage and combat primitives" do
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

  describe "damage replacement and prevention abilities (CR 614.1a, 614.9, 615)" do
    it "describe themselves" do
      expect(ability_text({ "damage_replacement" => { "by" => { "controller" => "you" }, "to" => { "controller" => "opponent" },
                                                      "multiply" => 2 } }))
        .to eq("damage by anything (yours) to anything (an opponent's): 2 times that damage instead")
      expect(ability_text({ "damage_replacement" => { "combat" => "noncombat", "plus" => 1 } }))
        .to eq("noncombat damage: that much plus 1 instead")
      expect(ability_text({ "damage_replacement" => { "to" => { "each" => "player", "controller" => "you" }, "redirect" => "attached" } }))
        .to eq("damage to player (yours): that damage to the attached creature instead")
      expect(ability_text({ "prevent_damage" => { "to" => "self", "combat" => "combat" } })).to eq("prevent all combat damage to this")
      expect(ability_text({ "prevent_damage" => { "by" => { "each" => "creature", "other" => true } } }))
        .to eq("prevent all damage by other creature")
      expect(ability_text({ "damage_unpreventable" => {} })).to eq("damage can't be prevented")
      expect(ability_text("double_tokens")).to eq("if tokens would be created under your control, twice that many are created instead")
      expect(ability_text({ "exile_if_dies" => { "affects" => { "each" => "creature", "controller" => "opponent" } } }))
        .to eq("if creatures opponents control would die, exile it instead")
    end

    it "report path-addressed errors" do
      expect(errors_for(creature({ "damage_replacement" => { "multiply" => 2, "plus" => 1 } })))
        .to include("abilities[0].damage_replacement: needs exactly one of multiply, plus, redirect")
      expect(errors_for(creature({ "damage_replacement" => { "multiply" => 1 } })))
        .to include("abilities[0].damage_replacement.multiply: must be an integer >= 2")
      expect(errors_for(creature({ "damage_replacement" => { "redirect" => "you" } })))
        .to include("abilities[0].damage_replacement.redirect: must be \"self\" or \"attached\"")
      expect(errors_for(creature({ "prevent_damage" => { "to" => "you", "combat" => "always", "x" => 1 } })))
        .to include("abilities[0].prevent_damage: unknown parameter \"x\"",
                    "abilities[0].prevent_damage.combat: must be one of combat, noncombat",
                    a_string_starting_with("abilities[0].prevent_damage.to: must be \"self\""))
      expect(errors_for(creature({ "prevent_damage" => { "by" => { "controller" => "them", "each" => "nope" } } })))
        .to include("abilities[0].prevent_damage.by.controller: must be one of you, opponent, any",
                    a_string_starting_with("abilities[0].prevent_damage.by.each: unknown filter"))
      expect(errors_for(creature({ "double_tokens" => { "count" => 3 } })))
        .to include("abilities[0].double_tokens: unknown parameter \"count\"")
    end
  end

  describe "prevention effects (CR 615.7, 615.12)" do
    it "describe themselves" do
      expect(effect_text({ "prevent_damage" => { "to" => { "target" => 0 }, "next" => 3 } }, targets: ["any_target"]))
        .to start_with("prevent the next 3 damage to")
      expect(effect_text({ "prevent_damage" => { "by" => { "target" => 0 }, "combat" => "combat" } }, targets: ["creature"]))
        .to start_with("prevent all combat damage by")
      expect(effect_text({ "damage_unpreventable" => { "combat" => "combat" } })).to eq("combat damage can't be prevented this turn")
      expect(effect_text({ "additional_phases" => { "phases" => %w[combat main] } }))
        .to eq("after this phase, additional combat and main phases")
    end

    it "report path-addressed errors" do
      expect(errors_for(spell({ "prevent_damage" => {} }))).to include("abilities[0].spell.effects[0].prevent_damage.to: required")
      expect(errors_for(spell({ "prevent_damage" => { "to" => "you", "next" => 0, "duration" => "forever" } })))
        .to include(a_string_starting_with("abilities[0].spell.effects[0].prevent_damage.next: must be an integer >= 1"),
                    a_string_starting_with("abilities[0].spell.effects[0].prevent_damage.duration: must be one of end_of_turn"))
      expect(errors_for(spell({ "additional_phases" => { "phases" => ["upkeep"] } })))
        .to include("abilities[0].spell.effects[0].additional_phases.phases: must be a non-empty list of \"combat\" | \"main\"")
      expect(errors_for(spell({ "deal_damage" => { "amount" => 1, "to" => "you", "if" => { "first_combat_phase" => 1 } } })))
        .to include("abilities[0].spell.effects[0].deal_damage.if.first_combat_phase: must be true or false")
    end
  end

  describe "damage and block triggers (CR 120.3, 509.3)" do
    it "describe themselves" do
      expect(trigger_text({ "dealt_damage" => {} })).to eq("Whenever this is dealt damage")
      expect(trigger_text({ "dealt_damage" => { "player" => "opponent", "noncombat" => true } }))
        .to eq("Whenever an opponent is dealt noncombat damage")
      expect(trigger_text({ "deals_damage" => { "noncombat" => true, "to" => "opponent" } }))
        .to eq("Whenever this deals noncombat damage to an opponent")
      expect(trigger_text({ "blocks" => { "blocking" => "creature" } })).to eq("Whenever this blocks a creature")
    end

    it "report path-addressed errors" do
      expect(errors_for(trigger({ "dealt_damage" => { "combat" => true, "noncombat" => true, "player" => "them" } })))
        .to include(a_string_ending_with("dealt_damage: combat and noncombat can't both be true"),
                    a_string_ending_with("dealt_damage.player: must be one of you, opponent, any"))
      expect(errors_for(trigger({ "dealt_damage" => { "player" => "you", "subject" => "self" } })))
        .to include(a_string_ending_with("dealt_damage: use subject or player, not both"))
      expect(errors_for(trigger({ "deals_damage" => { "noncombat" => "yes" } })))
        .to include(a_string_ending_with("deals_damage.noncombat: must be true or false"))
      expect(errors_for(trigger({ "blocks" => { "blocking" => "nope" } })))
        .to include(a_string_including("blocks.blocking: unknown filter"))
    end
  end
end
