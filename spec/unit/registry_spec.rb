# frozen_string_literal: true

RSpec.describe Enjine::Registry do
  subject(:registry) { described_class.new }

  let(:klass) do
    Class.new(Enjine::Primitive) do
      def self.category = :cost
      def self.primitive_name = "probe"
    end
  end

  it "registers and fetches primitives by category and name" do
    registry.register(klass)
    expect(registry.fetch(:cost, :probe)).to be(klass)
    expect(registry.names(:cost)).to eq(["probe"])
    expect(registry.each(:cost).to_a).to eq([klass])
  end

  it "refuses a second class under the same name" do
    registry.register(klass)
    registry.register(klass)
    other = Class.new(klass)
    expect { registry.register(other) }.to raise_error(ArgumentError, /already registered/)
  end

  it "rejects unknown categories" do
    expect { Class.new(Enjine::Primitive) { primitive :spell, :x, description: "" } }
      .to raise_error(ArgumentError, /unknown category/)
  end
end
