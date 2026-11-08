# frozen_string_literal: true

RSpec.describe Enjine::Mana do
  describe Enjine::Mana::Cost do
    it "parses generic and colored symbols" do
      cost = described_class.parse("{2}{R}{R}")
      expect(cost.generic).to eq(2)
      expect(cost.colored).to eq(R: 2)
      expect(cost.mana_value).to eq(4)
      expect(cost.to_s).to eq("{2}{R}{R}")
    end

    it "renders a zero cost as {0}" do
      expect(described_class.parse("{0}").to_s).to eq("{0}")
    end

    it "rejects unsupported symbols and junk" do
      expect { described_class.parse("{R/G}") }.to raise_error(ArgumentError, /unsupported mana symbol/)
      expect { described_class.parse("2R") }.to raise_error(ArgumentError, /unexpected characters/)
      expect { described_class.parse(3) }.to raise_error(ArgumentError, /must be a string/)
    end
  end

  describe ".parse_produce" do
    it "parses produced mana" do
      expect(described_class.parse_produce("{C}{C}", [], "p")).to eq(%i[C C])
    end

    it "reports invalid produced mana" do
      [nil, "", "G", "{2}"].each do |input|
        errors = []
        expect(described_class.parse_produce(input, errors, "p")).to be_nil
        expect(errors).not_to be_empty
      end
    end
  end
end
