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
      expect { described_class.parse("{B/P}") }.to raise_error(ArgumentError, /unsupported mana symbol/)
      expect { described_class.parse("{G/G}") }.to raise_error(ArgumentError, /two different colors/)
      expect { described_class.parse("2R") }.to raise_error(ArgumentError, /unexpected characters/)
      expect { described_class.parse(3) }.to raise_error(ArgumentError, /must be a string/)
    end
  end

  describe "hybrid symbols (CR 107.4e, 202.2d, 202.3f)" do
    it "parses two-color hybrid symbols in printed order and round-trips" do
      cost = Enjine::Mana::Cost.parse("{2}{R/G}{R/G}")
      expect(cost.hybrid).to eq([%i[R G], %i[R G]])
      expect(cost.to_s).to eq("{2}{R/G}{R/G}")
      expect(Enjine::Mana::Cost.parse("{G/W}{G/W}").to_s).to eq("{G/W}{G/W}")
      expect(Enjine::Mana::Cost.parse(cost.to_s)).to eq(cost)
    end

    it "counts each hybrid symbol as 1 toward mana value (its largest component)" do
      expect(Enjine::Mana::Cost.parse("{3}{W/U}{W/U}").mana_value).to eq(5)
      expect(Enjine::Mana::Cost.parse("{B/R}{B/R}").mana_value).to eq(2)
    end

    it "is all of its components' colors, with colored symbols, in WUBRG order" do
      expect(Enjine::Mana::Cost.parse("{1}{U/B}{U/B}").colors).to eq(%i[U B])
      expect(Enjine::Mana::Cost.parse("{G/W}{R}").colors).to eq(%i[W R G])
      expect(Enjine::Mana::Cost.parse("{3}").colors).to eq([])
    end

    it "lists what can pay each colored or hybrid symbol, and keeps hybrids when X is announced or costs are summed" do
      cost = Enjine::Mana::Cost.parse("{X}{R/G}{B}")
      expect(cost.requirements).to eq([%i[B], %i[R G]])
      expect(cost.with_x(2).to_s).to eq("{2}{R/G}{B}")
      expect(described_class.sum_costs([cost, Enjine::Mana::Cost.parse("{U/B}")]).to_s).to eq("{X}{R/G}{U/B}{B}")
    end

    it "doesn't count hybrid as colorless: a hybrid-only cost renders without {0}" do
      expect(Enjine::Mana::Cost.parse("{W/U}").to_s).to eq("{W/U}")
    end

    it "parses monocolored hybrid {2/W}: mana value 2, white, payable as {W} or {2} (CR 107.4e, 202.3f, 601.2b)" do
      cost = Enjine::Mana::Cost.parse("{1}{2/W}{2/U}")
      expect(cost.to_s).to eq("{1}{2/W}{2/U}")
      expect(Enjine::Mana::Cost.parse(cost.to_s)).to eq(cost)
      expect([cost.mana_value, cost.colors, cost.requirements]).to eq([5, %i[W U], []])
      expect(cost.equivalents.map(&:to_s)).to eq(%w[{1}{W}{U} {3}{W} {3}{U} {5}])
      expect(Enjine::Mana::Cost.parse("{R/G}").equivalents.map(&:to_s)).to eq(["{R/G}"])
      errors = []
      described_class.parse_cost("{W/2}", errors, "c")
      expect(errors).to eq(["c: unsupported mana symbol {W/2}"])
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
