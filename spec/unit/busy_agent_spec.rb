# frozen_string_literal: true

RSpec.describe Enjine::Agents::Busy do
  def decision(*options) = Struct.new(:options).new(options)

  it "plays a land when it can, else casts or activates, and otherwise chooses like Agents::Random" do
    agent = described_class.new(seed: 1)
    land = { type: "play_land", object: 1 }
    cast = { type: "cast", object: 2 }
    pass = { type: "pass" }
    picks = Array.new(200) { agent.choose(decision(pass, cast, land)) }
    expect(picks.count(land)).to be > 150
    expect(picks).to include(pass)
    picks = Array.new(200) { agent.choose(decision(pass, cast)) }
    expect(picks.count(cast)).to be > 150
    expect(picks).to include(pass)
    expect(described_class.new(seed: 1, eagerness: 0).choose(decision(pass))).to eq(pass)
  end
end
