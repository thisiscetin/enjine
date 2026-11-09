# frozen_string_literal: true

RSpec.describe Enjine::Catalog do
  let(:forest) { { "name" => "Forest", "types" => ["land"], "supertypes" => ["basic"], "subtypes" => ["forest"] } }

  it "looks cards up by name or id" do
    catalog = described_class.from_definitions([forest])
    expect(catalog.fetch("Forest").id).to eq("forest")
    expect(catalog["forest"]).to eq(catalog.fetch("Forest"))
    expect(catalog).to include("Forest")
    expect(catalog.ids).to eq(["forest"])
    expect(catalog.size).to eq(1)
    expect(catalog.to_a).to eq([forest])
    expect { catalog.fetch("Island") }.to raise_error(KeyError, /unknown card/)
  end

  it "accepts an identical definition twice" do
    catalog = described_class.from_definitions([forest, forest.dup])
    expect(catalog.size).to eq(1)
  end

  it "raises CatalogConflict for different definitions under one name" do
    catalog = described_class.from_definitions([forest])
    expect { catalog.add(forest.merge("supertypes" => [])) }.to raise_error(Enjine::CatalogConflict, /Forest/)
  end

  it "merges catalogs and can be frozen" do
    a = described_class.from_definitions([forest])
    b = CardFixtures.catalog
    expect(a.merge(b).ids.grep_v(/_token_/).size).to eq(CardFixtures.cards.size)
    a.freeze
    expect { a.add(CardFixtures.cards.last.merge("name" => "Other")) }.to raise_error(FrozenError)
  end
end
