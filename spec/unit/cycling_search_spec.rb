# frozen_string_literal: true

RSpec.describe "Cycling, card specs and library search: validation (unit)" do
  def errors_for(data)
    errors = []
    Enjine::Mechanics.build_entry(:ability, data, errors, "a")
    errors
  end

  def spec_errors(data)
    errors = []
    Enjine::Mechanics::CardSpec.build(data, errors, "s")
    errors
  end

  def search(params)
    { "spell" => { "effects" => [{ "search_library" => params }] } }
  end

  it "card specs report unknown keys, names and malformed lists by path (CR 701.23a)" do
    expect(spec_errors(42))
      .to eq(['s: must be "card" or an object (types, not_types, subtypes, supertypes, name, any_of, permanent, mana_value)'])
    expect(spec_errors({})).to eq(["s: needs at least one of types, not_types, subtypes, supertypes, name, any_of, permanent, mana_value"])
    expect(spec_errors({ "types" => "land" })).to eq(["s.types: must be a list"])
    expect(spec_errors({ "supertypes" => ["ancient"] })).to eq(['s.supertypes: unknown supertype "ancient"'])
    expect(spec_errors({ "subtypes" => ["Bad Type!"] })).to eq(['s.subtypes: invalid subtype "Bad Type!"'])
    expect(spec_errors({ "name" => "" })).to eq(["s.name: must be a card name"])
    expect(spec_errors({ "any_of" => [{ "types" => ["land"] }] })).to eq(["s.any_of: must list at least two specs"])
    expect(spec_errors({ "any_of" => [{ "types" => ["land"] }, { "bogus" => 1 }] }))
      .to eq(['s.any_of[1]: unknown parameter "bogus"'])
    expect(spec_errors("card")).to be_empty
  end

  it "describes card specs" do
    describe = ->(data) { Enjine::Mechanics::CardSpec.build(data, [], "s").to_s }
    expect(describe.call("card")).to eq("card")
    expect(describe.call({ "supertypes" => ["basic"], "types" => ["land"] })).to eq("basic land card")
    expect(describe.call({ "subtypes" => ["swamp"] })).to eq("Swamp card")
    expect(describe.call({ "name" => "Quiet Tutor" })).to eq("card named Quiet Tutor")
    expect(describe.call({ "any_of" => [{ "subtypes" => ["aura"] }, { "types" => ["artifact"] }] })).to eq("Aura or artifact card")
  end

  it "search_library validates count, put, tapped and reveal" do
    expect(errors_for(search({ "count" => 0 })))
      .to eq(['a.spell.effects[0].search_library.count: must be a positive integer, "any" or an amount'])
    expect(errors_for(search({ "put" => "exile" }))).to eq(["a.spell.effects[0].search_library.put: must be one of hand, battlefield"])
    expect(errors_for(search({ "reveal" => "yes" }))).to eq(["a.spell.effects[0].search_library.reveal: must be true or false"])
    expect(errors_for(search({ "tapped" => true })))
      .to eq(["a.spell.effects[0].search_library.tapped: only cards put onto the battlefield can enter tapped"])
    expect(errors_for(search({ "to" => "you" }))).to eq(['a.spell.effects[0].search_library: unknown parameter "to"'])
    expect(errors_for(search({ "count" => "any", "for" => { "name" => "Quiet Tutor" } }))).to be_empty
  end

  it "cycling needs a cost, validates its spec and describes itself (CR 702.29a, 702.29e)" do
    expect(errors_for({ "cycling" => {} })).to eq(["a.cycling.cost: required"])
    expect(errors_for({ "cycling" => { "cost" => "{1}", "for" => { "types" => ["spaceship"] } } }))
      .to eq(['a.cycling.for.types: unknown type "spaceship"'])
    expect(errors_for({ "cycling" => { "cost" => "{1}", "extra" => 1 } })).to eq(['a.cycling: unknown parameter "extra"'])
    plain = Enjine::Mechanics.build_entry(:ability, { "cycling" => { "cost" => "{2}" } }, [], "a")
    typed = Enjine::Mechanics.build_entry(:ability, { "cycling" => { "cost" => "{1}{B}", "for" => { "subtypes" => ["swamp"] } } }, [], "a")
    expect([plain.to_s, typed.to_s]).to eq(["Cycling {2}", "Swampcycling {1}{B}"])
    expect([plain.cycling?, plain.kind, plain.zone, typed.spec.to_s]).to eq([true, :activated, :hand, "Swamp card"])
    expect(typed.effects.first.to_s).to eq("search your library for up to 1 Swamp card, reveal → hand, shuffle")
  end

  it "a hand-only cost can't be combined with tap or sacrifice (CR 113.6m)" do
    expect(errors_for({ "activated" => { "cost" => %w[discard_self tap], "effects" => [{ "draw" => { "amount" => 1 } }] } }))
      .to eq(["a.activated.cost: a cost paid from the hand can't be combined with tap or sacrifice"])
    expect(errors_for({ "activated" => { "cost" => [{ "discard_self" => { "x" => 1 } }], "effects" => [] } }))
      .to eq(['a.activated.cost[0].discard_self: unknown parameter "x"'])
    expect(Enjine::Mechanics::Costs::DiscardSelf::INSTANCE.to_s).to eq("Discard this card")
  end
end
