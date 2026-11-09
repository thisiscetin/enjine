# frozen_string_literal: true

RSpec.describe "Keyword alternative costs and convoke: card data validation (unit)" do
  def errors_for(card)
    Enjine::CardDefinition.from_h({ "name" => "Probe Card", "mana_cost" => "{R}" }.merge(card))
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def card(types, abilities, keywords: [])
    extra = types.include?("creature") ? { "power" => 1, "toughness" => 1 } : {}
    { "types" => types, "abilities" => abilities, "keywords" => keywords }.merge(extra)
  end

  def sorcery(*abilities) = card(["sorcery"], [{ "spell" => { "effects" => [{ "draw" => { "amount" => 1 } }] } }, *abilities])
  def text(data) = Enjine::CardDefinition.from_h({ "name" => "Probe Card", "mana_cost" => "{R}" }.merge(data)).abilities.map(&:to_s)

  it "checks the cost: required, a mana string or a list of mana and chosen costs (CR 118.9)" do
    expect(errors_for(sorcery({ "flashback" => {} }))).to eq(["abilities[1].flashback.cost: required"])
    expect(errors_for(sorcery({ "flashback" => { "cost" => "2R", "x" => 1 } })))
      .to eq(["abilities[1].flashback: unknown parameter \"x\"", "abilities[1].flashback.cost: unexpected characters in \"2R\""])
    expect(errors_for(sorcery({ "harmonize" => { "cost" => [] } })))
      .to eq(["abilities[1].harmonize.cost: must be a mana cost string or a non-empty list of costs"])
    expect(errors_for(sorcery({ "flashback" => { "cost" => [{ "mana" => "{1}" }, "tap"] } })))
      .to eq(["abilities[1].flashback.cost[1]: an alternative cost must be mana or a chosen cost (tap, sacrifice, ...)"])
    expect(errors_for(sorcery({ "warp" => { "cost" => 3 } }))).to eq(["abilities[1].warp.cost: must be a list"])
    expect(errors_for(sorcery("mayhem"))).to eq([])
  end

  it "limits flashback to instants and sorceries and evoke to permanents (CR 702.34a, 702.74a)" do
    expect(errors_for(card(["creature"], [{ "flashback" => { "cost" => "{2}" } }])))
      .to eq(["abilities[0]: flashback abilities need a instant/sorcery card"])
    expect(errors_for(sorcery({ "evoke" => { "cost" => "{R}" } })))
      .to eq(["abilities[1]: evoke abilities need a artifact/creature/enchantment/planeswalker card"])
  end

  it "describes each keyword; evoke brings its sacrifice trigger" do
    expect(text(sorcery({ "flashback" => { "cost" => [{ "mana" => "{U}" }, { "tap_permanents" => { "count" => 2 } }] } },
                        { "mayhem" => { "cost" => "{1}{R}" } }, "mayhem", { "harmonize" => { "cost" => "{4}{G}" } },
                        { "web_slinging" => { "cost" => "{W}" } }, { "sneak" => { "cost" => "{B}" } },
                        { "warp" => { "cost" => "{R}" } })).drop(1))
      .to eq(["Flashback {U}, Tap 2 untapped creatures you control", "Mayhem {1}{R}", "Mayhem", "Harmonize {4}{G}",
              "Web-Slinging {W}", "Sneak {B}", "Warp {R}"])
    expect(text(card(["creature"], [{ "evoke" => { "cost" => "{R}" } }])))
      .to eq(["Evoke {R}", "When this enters, if its evoke cost was paid, sacrifice → itself"])
  end

  it "checks cast_with, cast_from and cast_with_this_turn conditions" do
    cond = ->(c) { sorcery.merge("abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 1, "if" => c } }] } }]) }
    expect(errors_for(cond.call({ "cast_with" => "kicker" })))
      .to eq(["abilities[0].spell.effects[0].draw.if.cast_with: must be one of " \
              "#{Enjine::Mechanics::Condition::CastHow::KEYWORDS.join(", ")}"])
    expect(errors_for(cond.call({ "cast_from" => "battlefield", "x" => 1 })))
      .to eq(["abilities[0].spell.effects[0].draw.if: unknown parameter \"x\"",
              "abilities[0].spell.effects[0].draw.if.cast_from: must be one of hand, graveyard, exile, library, outside"])
    expect(errors_for(cond.call({ "cast_with_this_turn" => "warp" }))).to eq([])
    conditions = [{ "cast_with" => "web_slinging" }, { "cast_from" => "hand" }, { "cast_from" => "graveyard" },
                  { "cast_with_this_turn" => "warp" }]
    expect(conditions.map { Enjine::Mechanics::Condition.build(it, [], "if").to_s })
      .to eq(["its web-slinging cost was paid", "it was cast from a hand", "it was cast from a graveyard",
              "a spell was cast with warp this turn"])
  end

  it "accepts convoke as a keyword (CR 702.51)" do
    expect(errors_for(sorcery.merge("keywords" => ["convoke"]))).to eq([])
  end
end
