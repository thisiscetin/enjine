# frozen_string_literal: true

# Validation and descriptions of the casting, cost and permission shapes: computed ward life, cast triggers by
# owner, casting from a graveyard while resolving, flash by an optional cost (CR 601.3c), "for as long as you
# control" permissions, granted alternative costs, chosen-type and same-name card specs, symbol-counting costs.
RSpec.describe "Casting and permission gaps: card data (unit)" do
  def card(abilities, extra = {})
    { "name" => "Spec Unit Card", "mana_cost" => "{1}", "types" => ["sorcery"], "abilities" => abilities }.merge(extra)
  end

  def creature(abilities) = card(abilities, "types" => ["creature"], "power" => 1, "toughness" => 1)
  def draw = [{ "draw" => { "amount" => 1 } }]
  def spell(effects) = { "spell" => { "effects" => effects } }

  def errors_for(data)
    Enjine::CardDefinition.from_h(data)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def texts(data) = Enjine::CardDefinition.from_h(data).abilities.map(&:to_s)

  it "validates and describes the new cost shapes" do
    expect(texts(creature([{ "ward" => { "cost" => [{ "pay_life" => { "power" => "self" } }] } }])))
      .to eq(["Ward—Pay life equal to the power of itself"])
    expect(errors_for(card([{ "additional_cost" => { "cost" => [{ "mana" => "{1}" }], "flash" => true } }, spell(draw)])))
      .to eq(["abilities[0].additional_cost.flash: needs optional: true"])
    flash = { "additional_cost" => { "cost" => [{ "mana" => "{1}" }], "optional" => true, "flash" => true } }
    expect(texts(card([flash, spell(draw)])).first).to end_with("(as though it had flash if you do)")
    bad = { "exile_from_graveyard" => { "count" => "any" } }
    expect(errors_for(creature([{ "activated" => { "cost" => [bad], "effects" => draw } }])))
      .to eq(["abilities[0].activated.cost[0].exile_from_graveyard.count: \"any\" needs `symbols`"])
    bad = { "exile_from_graveyard" => { "count" => "any", "symbols" => { "color" => "P", "at_least" => 2 } } }
    expect(errors_for(creature([{ "activated" => { "cost" => [bad], "effects" => draw } }])))
      .to include(a_string_starting_with("abilities[0].activated.cost[0].exile_from_graveyard.symbols: must be"))
    costs = [{ "choose_creature_type" => {} }, { "remove_counters" => { "count" => 2, "self" => true } }]
    expect(texts(creature([{ "activated" => { "cost" => costs, "effects" => draw } }])).first)
      .to start_with("Choose a creature type, Remove 2 counters from this")
  end

  it "validates triggers, cast effects, permissions and grants" do
    expect(errors_for(creature([{ "triggered" => { "when" => { "cast" => { "owner" => "them" } }, "effects" => draw } }])))
      .to eq(["abilities[0].triggered.when.cast.owner: must be one of you, not_you"])
    expect(texts(creature([{ "triggered" => { "when" => { "cast" => { "owner" => "you" } }, "effects" => draw } }])).first)
      .to start_with("Whenever you cast a spell you own")
    expect(texts(card([spell([{ "cast" => { "from" => "graveyard", "count" => 3 } }])])).first).to include("up to 3 card from graveyard")
    expect(errors_for(card([spell([{ "play_permission" => { "to" => "you", "during" => "night", "waterbend" => "{2}" } }])])))
      .to eq(["abilities[0].spell.effects[0].play_permission.during: must be \"your_turn\"",
              "abilities[0].spell.effects[0].play_permission.waterbend: must be \"mana_value\""])
    expect(errors_for(creature([{ "cards_have" => { "zone" => "library", "ability" => { "warp" => { "cost" => "{1}" } } } }])))
      .to eq(["abilities[0].cards_have.zone: must be one of graveyard, hand, exile",
              "abilities[0].cards_have.ability: must be one of flashback, harmonize, mayhem, web_slinging, sneak, miracle"])
    expect(texts(creature([{ "cards_have" => { "cards" => { "types" => ["creature"] },
                                               "ability" => { "sneak" => { "cost" => "{1}" } } } }])))
      .to eq(["Creature cards in your graveyard have Sneak {1}"])
    expect(texts(creature([{ "triggered" => { "when" => { "gives_gift" => { "controller" => "any" } }, "effects" => draw } }])).first)
      .to start_with("Whenever a player gives a gift")
  end

  it "validates search battlefield_instead and the card spec relations" do
    search = { "search_library" => { "put" => "battlefield", "battlefield_instead" => { "for" => "card", "when" => true } } }
    expect(errors_for(card([spell([search])])))
      .to eq(["abilities[0].spell.effects[0].search_library.battlefield_instead: unknown parameter \"when\"",
              "abilities[0].spell.effects[0].search_library.battlefield_instead: only a search that puts cards into a hand"])
    expect(errors_for(card([spell([{ "search_library" => { "battlefield_instead" => 1 } }])])))
      .to eq(["abilities[0].spell.effects[0].search_library.battlefield_instead: must be {\"if\": condition, \"for\": card spec}"])
    spec = Enjine::Mechanics::CardSpec.build({ "types" => ["creature"], "subtypes" => "chosen",
                                               "same_name_as" => { "permanent" => { "controller" => "you" } } }, [], "x")
    expect(spec.to_s).to eq("chosen-type creature card with the same name as a permanent you control")
    expect(spec.unrelated.to_s).to eq("creature card")
    expect(spec.any?).to be(false)
  end
end
