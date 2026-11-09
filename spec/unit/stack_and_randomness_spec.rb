# frozen_string_literal: true

# Validation and wording of cast filters on targets and zones (CR 603.2, 601.2a), stack ability filters
# (CR 113.7), random choices (CR 701.9b), coin flips (CR 705) and proliferate (CR 701.34a).
RSpec.describe "Stack, cast filter and randomness primitives" do
  def build(category, data, path = "x")
    errors = []
    [Enjine::Mechanics.build_entry(category, data, errors, path), errors]
  end

  def errors_of(category, data) = build(category, data)[1]

  describe "validation (path-addressed errors)" do
    it "rejects bad cast trigger filters" do
      expect(errors_of(:trigger, { "cast" => { "targets" => { "wizard" => {} } } }))
        .to include(a_string_matching(/x.cast.targets: unknown filter/))
      expect(errors_of(:trigger, { "cast" => { "from" => "deck", "not_from" => "sideboard" } }))
        .to eq(["x.cast.from: must be one of hand, graveyard, exile, library, outside",
                "x.cast.not_from: must be one of hand, graveyard, exile, library, outside"])
    end

    it "rejects a bad cost_modifier zone" do
      expect(errors_of(:ability, { "cost_modifier" => { "not_from" => "deck", "reduce" => 1 } }))
        .to eq(["x.cost_modifier.not_from: must be one of hand, graveyard, exile, library, outside"])
    end

    it "rejects bad stack_ability parameters" do
      expect(errors_of(:filter, { "stack_ability" => { "kind" => "static", "controller" => "each", "colour" => 1 } }))
        .to eq(['x.stack_ability: unknown parameter "colour"', "x.stack_ability.kind: must be one of activated, triggered",
                "x.stack_ability.controller: must be one of you, opponent"])
      expect(errors_of(:filter, { "stack_ability" => { "source" => { "wizard" => {} } } }))
        .to include(a_string_matching(/x.stack_ability.source: unknown filter/))
    end

    it "rejects bad random, coin and proliferate parameters" do
      expect(errors_of(:effect, { "discard" => { "amount" => 1, "random" => "yes" } })).to eq(["x.discard.random: must be true or false"])
      expect(errors_of(:effect, { "choose_cards" => { "from" => { "graveyard" => "you" }, "put" => "exile", "count" => "any",
                                                      "random" => true } }))
        .to eq(["x.choose_cards.count: must be a number to pick at random"])
      expect(errors_of(:effect, { "flip_coins" => { "count" => "tails" } })).to eq(["x.flip_coins.count: must be one of wins, heads"])
      expect(errors_of(:effect, { "flip_coins" => { "amount" => -1 } })).to include(a_string_matching(/x.flip_coins.amount/))
      expect(errors_of(:effect, { "proliferate" => { "to" => "you" } })).to eq(['x.proliferate: unknown parameter "to"'])
    end
  end

  it "describes the shapes in words" do
    words = lambda do |category, data|
      built, errors = build(category, data)
      raise errors.inspect unless errors.empty?

      built.to_s
    end
    expect(words.call(:trigger, { "cast" => { "targets" => "self", "from" => "graveyard" } }))
      .to eq("Whenever you cast a spell from a graveyard that targets this")
    expect(words.call(:trigger, { "cast" => { "from" => "hand" } })).to eq("Whenever you cast a spell from your hand")
    expect(words.call(:ability, { "cost_modifier" => { "from" => "exile", "increase" => 2, "caster" => "opponent" } }))
      .to eq("spells your opponents cast from exile cost {2} more")
    expect(words.call(:filter, { "stack_ability" => { "kind" => "triggered", "controller" => "opponent", "source" => "artifact" } }))
      .to eq("triggered ability an opponent controls from a source: artifact")
    expect(words.call(:filter, { "stack_ability" => { "controller" => "you" } })).to eq("activated or triggered ability you control")
    expect(words.call(:effect, { "proliferate" => { "amount" => 2 } })).to eq("proliferate 2 times")
    expect(words.call(:effect, { "flip_coins" => { "amount" => 2, "count" => "heads" } })).to eq("flip 2 coins (counting heads)")
  end
end
