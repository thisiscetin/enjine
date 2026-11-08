# frozen_string_literal: true

RSpec.describe Enjine::Rng do
  it "is deterministic for a seed" do
    a = described_class.from_seed(42)
    b = described_class.from_seed(42)
    expect(Array.new(10) { a.next_u32 }).to eq(Array.new(10) { b.next_u32 })
  end

  it "differs across seeds" do
    expect(described_class.from_seed(1).next_u32).not_to eq(described_class.from_seed(2).next_u32)
  end

  it "resumes exactly from its exported state" do
    a = described_class.from_seed(7)
    3.times { a.next_u32 }
    b = described_class.new(a.state)
    expect(Array.new(5) { b.rand(100) }).to eq(Array.new(5) { a.rand(100) })
  end

  it "returns integers in range" do
    rng = described_class.from_seed(3)
    values = Array.new(2_000) { rng.rand(6) }
    expect(values.uniq.sort).to eq((0..5).to_a)
  end

  it "rejects invalid bounds" do
    expect { described_class.from_seed(1).rand(0) }.to raise_error(ArgumentError)
    expect { described_class.from_seed(1).rand(2**33) }.to raise_error(ArgumentError)
  end

  it "shuffles into a permutation, reproducibly" do
    a = described_class.from_seed(9).shuffle!((1..20).to_a)
    b = described_class.from_seed(9).shuffle!((1..20).to_a)
    expect(a).to eq(b)
    expect(a.sort).to eq((1..20).to_a)
    expect(a).not_to eq((1..20).to_a)
  end
end
