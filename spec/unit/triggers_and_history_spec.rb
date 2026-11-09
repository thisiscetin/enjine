# frozen_string_literal: true

# Validation of the trigger, history and stack primitives (invented data only): path-addressed errors and
# their descriptions.
RSpec.describe "Trigger, history and stack primitives: validation" do
  def build(category, data, path = "x", **context)
    errors = []
    built = Enjine::Mechanics.build_entry(category, data, errors, path, **context)
    [built, errors]
  end

  def errors_of(category, data, **context) = build(category, data, **context)[1]
  def amount_errors(data) = [].tap { Enjine::Mechanics::Amount.build(data, it, "x", targets_count: 0) }

  it "rejects bad trigger parameters (CR 603.6a, 305.1, 702.194a, 702.142b, 603.2)" do
    expect(errors_of(:trigger, { "enters" => { "from" => "moon" } })).to eq(["x.enters.from: must be one of hand, graveyard, exile, " \
                                                                             "library, stack, outside"])
    expect(errors_of(:trigger, { "plays_land" => { "not_from" => "moon" } }))
      .to eq(["x.plays_land.not_from: must be one of hand, graveyard, exile, library, outside"])
    expect(errors_of(:trigger, { "plays_land" => { "controller" => "me" } }))
      .to eq(["x.plays_land.controller: must be one of you, opponent, any"])
    expect(errors_of(:trigger, { "becomes_tapped" => { "for" => "crew" } })).to eq(["x.becomes_tapped.for: must be one of teamwork"])
    expect(errors_of(:trigger, { "activates_ability" => { "boast" => "yes" } }))
      .to eq(["x.activates_ability.boast: must be true or false"])
    expect(errors_of(:trigger, { "ability_triggers" => {} })).to eq(["x.ability_triggers.cause: must be one of attacks"])
    expect(errors_of(:trigger, { "cast" => { "single_target" => false } })).to eq(["x.cast.single_target: must be true"])
  end

  it "describes the triggers" do
    texts = [{ "enters" => { "from" => "exile" } }, { "plays_land" => { "not_from" => "hand" } },
             { "plays_land" => { "controller" => "opponent", "from" => "exile" } }, { "becomes_tapped" => { "for" => "teamwork" } },
             { "activates_ability" => { "boast" => true } }, { "ability_triggers" => { "cause" => "attacks" } },
             { "cast" => { "single_target" => true } }].map { build(:trigger, it)[0].to_s }
    expect(texts).to eq(["When this enters from exile", "Whenever you play a land from anywhere other than your hand",
                         "Whenever an opponent plays a land from exile", "Whenever this becomes tapped to pay a teamwork cost",
                         "Whenever you activate a boast ability",
                         "Whenever this attacking causes a triggered ability of it to trigger",
                         "Whenever you cast a spell with a single target"])
  end

  it "rejects bad amounts and selectors" do
    expect(amount_errors({ "lands_played_this_turn" => { "from" => "moon" } }))
      .to eq(["x.lands_played_this_turn.from: must be one of hand, graveyard, exile, library, outside"])
    expect(amount_errors({ "spells_cast_this_turn" => { "where" => "hand" } }))
      .to eq(["x.spells_cast_this_turn: unknown parameter \"where\""])
    expect(errors_of(:effect, { "draw" => { "amount" => 1, "to" => { "triggering" => "spell" } } }))
      .to eq(["x.draw.to.triggering: must be one of object, player, targets, ability"])
  end

  it "describes the amounts" do
    built = %w[lands_played_this_turn spells_cast_this_turn].map do |kind|
      Enjine::Mechanics::Amount.build({ kind => { "not_from" => "hand" } }, [], "x", targets_count: 0).to_s
    end
    expect(built).to eq(["the number of lands played from anywhere other than your hand this turn by you",
                         "the number of spells cast from anywhere other than your hand this turn by you"])
    expect(Enjine::Mechanics::Amount.build({ "noncombat_damage_last_turn" => "each_opponent" }, [], "x", targets_count: 0).to_s)
      .to eq("the noncombat damage last turn of each opponent")
  end

  it "rejects bad target specs and effect parameters (CR 115.1, 701.23, 706.1a, 115.7d)" do
    spell = { "spell" => { "targets" => ["permanent", { "filter" => "permanent", "shares_type_with" => 1 }], "effects" => [] } }
    expect(errors_of(:ability, spell)).to include("x.spell.targets[1].shares_type_with: must name an earlier target")
    expect(errors_of(:effect, { "search_library" => { "different_names" => "yes" } }))
      .to eq(["x.search_library.different_names: must be true or false"])
    expect(errors_of(:effect, { "roll_dice" => { "sides" => 1 } })).to eq(["x.roll_dice.sides: must be an integer >= 2"])
    expect(errors_of(:effect, { "choose_new_targets" => {} })).to eq(["x.choose_new_targets.of: required"])
    expect(errors_of(:effect, { "copy_spell" => { "of" => "self", "except" => { "keywords" => ["nope"] } } }))
      .to include(a_string_matching(/x.copy_spell.except.keywords/))
    expect(errors_of(:effect, { "draw" => { "amount" => 1, "if" => { "share_card_type" => [{ "target" => 3 }] } } }, targets_count: 1))
      .to eq(["x.draw.if.share_card_type[0].target: must refer to one of the 1 declared targets"])
  end

  it "rejects bad abilities (CR 611.3a, 705.3)" do
    expect(errors_of(:ability,
                     { "spell_keywords" => { "keywords" => [] } })).to eq(["x.spell_keywords.keywords: needs at least one keyword"])
    expect(errors_of(:ability, { "spell_keywords" => { "keywords" => ["zoom"], "from" => "moon" } }))
      .to contain_exactly("x.spell_keywords.from: must be one of hand, graveyard, exile, library, outside",
                          'x.spell_keywords.keywords: unknown keyword "zoom"')
    expect(build(:ability, { "spell_keywords" => { "from" => "hand", "keywords" => ["cascade"] } })[0].to_s)
      .to eq("Spells you cast from your hand have cascade")
    expect(build(:ability, "first_flips_win")[0].to_s).to start_with("The first time you flip")
    expect(build(:effect, { "roll_dice" => { "sides" => 20, "amount" => 2 } })[0].to_s).to eq("roll 2 d20")
    expect(build(:effect, { "choose_new_targets" => { "of" => { "triggering" => "object" } } })[0].to_s)
      .to eq("you may choose new targets for the triggering object")
  end
end
