# frozen_string_literal: true

# Validation and descriptions of the statics, grants and combat primitives of the known-gaps work: a cost
# tapping the granting permanent, "attacks alone", N/N tokens, chosen names, "hexproof from the chosen color",
# "can't become untapped" and "can't be attacked by".
RSpec.describe "Statics and combat gap primitives" do
  def errors_for(card)
    Enjine::CardDefinition.from_h(card)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def creature(*abilities)
    { "name" => "Test Beast", "mana_cost" => "{2}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "abilities" => abilities }
  end

  def spell(*effects)
    { "name" => "Test Spell", "mana_cost" => "{1}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => [], "effects" => effects } }] }
  end

  def trigger(data) = creature({ "triggered" => { "when" => data, "effects" => [{ "draw" => { "amount" => 1 } }] } })
  def ability(data) = Enjine::CardDefinition.from_h(creature(data)).abilities.first
  def effect(data) = Enjine::CardDefinition.from_h(spell(data)).spell_ability.effects.first
  def activated(cost) = { "activated" => { "cost" => cost, "effects" => [{ "draw" => { "amount" => 1 } }] } }

  describe "cost {\"tap\": \"granter\"}" do
    it "builds a granter cost, binds it and describes it" do
      cost = ability(activated([{ "tap" => "granter" }])).costs.first
      expect(cost).to be_a(Enjine::Mechanics::Costs::TapGranter)
      expect(cost.to_s).to eq("Tap the granting permanent")
      expect(cost.mana?).to be(false)
      expect(cost.for_granter(nil)).to equal(cost)
      expect(cost.for_granter("pole#1").granter).to eq("pole#1")
    end

    it "rejects other values" do
      expect(errors_for(creature(activated([{ "tap" => "self" }])))).to include(a_string_matching(/must be "tap" or/))
      expect(errors_for(creature(activated([{ "tap" => { "x" => 1 } }])))).to include(a_string_matching(/unknown parameter/))
    end
  end

  it "attacks alone: describes itself and rejects a non-boolean" do
    card = Enjine::CardDefinition.from_h(trigger({ "attacks" => { "subject" => { "each" => "creature", "controller" => "you" },
                                                                  "alone" => true } }))
    expect(card.abilities.first.trigger.to_s).to eq("Whenever creature you control attacks alone")
    expect(errors_for(trigger({ "attacks" => { "alone" => "yes" } }))).to include(a_string_matching(/alone: must be true or false/))
  end

  it "create_token size: an N/N description" do
    token = { "name" => "Spirit", "types" => ["creature"], "power" => 0, "toughness" => 0 }
    expect(effect({ "create_token" => { "token" => token, "size" => 3 } }).to_s).to start_with("create 1 3/3 Spirit token")
  end

  describe "chosen card names" do
    it "choose_card_name ability: types, look_at_hand and errors" do
      choice = ability({ "choose_card_name" => { "types" => ["land"], "look_at_hand" => "opponent" } })
      expect(choice.to_s).to eq("as this enters, look at an opponent's hand, then choose a land card name")
      expect(errors_for(creature({ "choose_card_name" => { "look_at_hand" => "you" } })))
        .to include(a_string_matching(/look_at_hand: must be "opponent"/))
      expect(errors_for(creature({ "choose_card_name" => { "types" => ["goblin"] } })))
        .to include(a_string_matching(/types: must be a list of card types/))
    end

    it "choose_card_name effect: remember and errors" do
      expect(effect({ "choose_card_name" => { "types" => ["land"], "remember" => "source" } }).to_s)
        .to eq("choose a card name (remembered by the source)")
      expect(errors_for(spell({ "choose_color" => { "remember" => "target" } }))).to include(a_string_matching(/remember: must be "source"/))
    end

    it "filters and player rules take name: chosen only" do
      static = { "static" => { "affects" => { "each" => { "land" => { "name" => "Forest" } } }, "keywords" => ["haste"] } }
      expect(errors_for(creature(static))).to include(a_string_matching(/name: must be "chosen"/))
      rule = { "player_rule" => { "rule" => "cant_gain_life", "name" => "chosen" } }
      expect(errors_for(creature(rule))).to include(a_string_matching(/only for cant_activate/))
      expect(ability({ "player_rule" => { "rule" => "cant_activate", "affects" => "each", "name" => "chosen" } }).to_s)
        .to eq("each player: cant activate (sources with the chosen name)")
    end
  end

  it "hexproof from the chosen color: unbound and bound" do
    hexproof = ability({ "hexproof_from" => "chosen_color" })
    expect(hexproof.to_s).to eq("Hexproof from the chosen color")
    expect(hexproof.with_chosen({})).to equal(hexproof)
    expect(hexproof.with_chosen({ "chosen_color" => "R" }).quality.colors).to eq([:R])
    expect(errors_for(creature({ "hexproof_from" => "chosen" }))).to include(a_string_matching(/chosen_color/))
  end

  it "become colors: \"chosen\" is accepted, other strings aren't" do
    expect(errors_for(spell({ "become" => { "colors" => "chosen", "to" => "self" } }))).to be_empty
    expect(errors_for(spell({ "become" => { "colors" => "red", "to" => "self" } }))).to include(a_string_matching(/colors/))
  end

  it "cant_be_attacked needs a filter; cant_be_blocked_by and tapping_power can be granted" do
    expect(errors_for(creature({ "player_rule" => { "rule" => "cant_be_attacked" } }))).to include(a_string_matching(/filter: required/))
    static = { "static" => { "affects" => { "each" => "creature", "controller" => "you" },
                             "abilities" => [{ "cant_be_blocked_by" => { "filter" => "creature" } }] } }
    expect(errors_for(creature(static))).to be_empty
    become = { "become" => { "abilities" => [{ "tapping_power" => { "for" => ["crew"], "plus" => 1 } }], "to" => "self" } }
    expect(errors_for(spell(become))).to be_empty
  end

  it "the cant_become_untapped keyword is registered" do
    expect(Enjine.registry.fetch(:keyword, "cant_become_untapped")).not_to be_nil
  end
end
