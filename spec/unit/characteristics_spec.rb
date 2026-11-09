# frozen_string_literal: true

RSpec.describe Enjine::Characteristics do
  it "answers type, keyword and ability questions" do
    chars = Enjine::CardDefinition.from_h(CardFixtures.cards.find do
      it["name"] == "Vessa, Rally Captain"
    end).printed_characteristics
    expect(chars).to be_planeswalker
    expect(chars).not_to be_land
    expect(chars.type?(:planeswalker)).to be(true)
    expect(chars.keyword?(:flash)).to be(false)
    expect(chars.ability("printed:9")).to be_nil
    expect(chars.mana_abilities).to eq([])
    expect(chars.triggered_abilities).to eq([])
  end
end
