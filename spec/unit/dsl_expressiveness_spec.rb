# frozen_string_literal: true

# Data validation for the small DSL shapes of spec/integration/dsl_expressiveness_spec.rb and battles_spec.rb:
# life-gain replacements (CR 614.1a), batched triggers and damage recipients (CR 603.2c, 120.3), the chosen name in
# card specs (CR 201.4) and choose_cards' chooser (CR 608.2d).
RSpec.describe "DSL expressiveness validation (unit)" do
  def errors_of(category, data) = [].tap { Enjine::Mechanics.build_entry(category, data, it, "x") }

  it "rejects bad life_gain_replacement data (CR 614.1a)" do
    expect(errors_of(:ability, { "life_gain_replacement" => { "player" => "nobody", "multiply" => 2 } }))
      .to eq(["x.life_gain_replacement.player: must be one of you, opponent, any"])
    expect(errors_of(:ability, { "life_gain_replacement" => {} }))
      .to eq(["x.life_gain_replacement: needs exactly one of multiply, plus, lose"])
    expect(errors_of(:ability, { "life_gain_replacement" => { "lose" => "yes" } }))
      .to eq(["x.life_gain_replacement.lose: must be true"])
    expect(errors_of(:ability, { "life_gain_replacement" => { "multiply" => 1 } }).first).to include("multiply")
  end

  it "rejects bad batched flags and damage recipients (CR 603.2c, 120.3)" do
    expect(errors_of(:trigger, { "dies" => { "batched" => "yes" } })).to eq(["x.dies.batched: must be true or false"])
    expect(errors_of(:trigger, { "enters" => { "batched" => 1 } })).to eq(["x.enters.batched: must be true or false"])
    expect(errors_of(:trigger, { "deals_damage" => { "to" => %w[player moon] } }))
      .to eq(["x.deals_damage.to: must be one of player, opponent, you, creature, planeswalker, battle, permanent, any, " \
              "or a list of them"])
    expect(errors_of(:trigger, { "deals_damage" => { "to" => [] } }).size).to eq(1)
  end

  it "describes batched enters and dies triggers" do
    texts = [{ "enters" => { "batched" => true, "subject" => { "each" => "creature" }, "from" => "graveyard" } },
             { "dies" => { "batched" => true, "subject" => { "each" => "creature" } } }, { "dies" => {} }].map do
      Enjine::Mechanics.build_entry(:trigger, it, [], "x").to_s
    end
    expect(texts).to eq(["When one or more of creature enter from graveyard", "Whenever one or more of creature die",
                         "When this dies"])
  end

  it "accepts the chosen name in card specs and cost_modifier spells (CR 201.4)" do
    expect(errors_of(:effect, { "reveal_until" => { "for" => { "name" => "chosen" } } })).to eq([])
    expect(errors_of(:ability, { "cost_modifier" => { "spells" => { "name" => "chosen" }, "increase" => 1 } })).to eq([])
    expect(errors_of(:effect, { "reveal_until" => { "for" => { "name" => "" } } })).to eq(["x.reveal_until.for.name: must be a card name"])
  end

  it "accepts kindred and battle in spell filters (CR 308, 310)" do
    expect(errors_of(:trigger, { "cast" => { "spell" => { "spell" => { "any_of" => %w[kindred battle] } } } })).to eq([])
  end
end
