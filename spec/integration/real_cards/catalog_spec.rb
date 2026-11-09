# frozen_string_literal: true

# The real-card fixtures as a whole (spec/fixtures/cards/real): structured card data only, each card in a
# Standard set with its printing and rarity, and a reprint in another family's file the same card (one catalog
# holds them all). Random decks of them play to the end with the rules monitor on.
RSpec.describe "Real card fixtures" do
  let(:standard) { %w[trk fra hob msh sos tmt ecl tla spm eoe fin tdm dft fdn] }
  let(:files) { Dir[File.join(CardFixtures::ROOT, "spec/fixtures/cards/real/*.json")].map { File.basename(it, ".json") } }

  it "are valid card data, one catalog for every family (reprints share their rules data)" do
    expect { Enjine::Catalog.from_definitions(files.flat_map { CardFixtures.real(it) }) }.not_to raise_error
  end

  it "carry a Standard printing and a rarity, and no printed text" do
    CardFixtures.real_cards.each do |card|
      expect(card).to include("rarity" => a_kind_of(String), "printing" => a_hash_including("set" => satisfy { standard.include?(it) }))
      expect(JSON.generate(card)).not_to match(/"(rules_text|oracle_text|flavor_text|reminder_text)"/)
    end
  end

  it "build random decks that play to the end without a rules finding" do
    builder = Enjine::DeckBuilder.new(CardFixtures.real_cards)
    players = [3, 4].map { Enjine::Player.new(name: "p#{it}", deck: builder.build(colors: 2, seed: it)) }
    result = Enjine::Fuzz.run(Enjine::Setup.new(*players), games: 2, seed: 5)
    expect(result.outcomes.values.sum).to eq(2)
  end
end
