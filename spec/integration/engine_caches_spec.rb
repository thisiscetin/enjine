# frozen_string_literal: true

# The caches keyed on Engine::Zones#zones_version (the token scan, graveyard trigger holders) hold only while
# no object appears, moves or ceases to exist, and the off-board quick nos only while nothing grants abilities.
RSpec.describe "Engine caches" do
  def engine(game) = game.instance_variable_get(:@engine)

  let(:game) do
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        battlefield "Grizzly Bears"
        hand "Lightning Bolt"
        library "Mountain", count: 5
      end
      player("bob") { library "Mountain", count: 5 }
    end
  end

  it "changes the zones version when an object moves, ceases to exist or the state is replaced" do
    eng = engine(game)
    before = eng.zones_version
    expect(eng.zones_version).to eq(before) # nothing happened
    eng.move!(obj_id(game, "Grizzly Bears"), :graveyard, reason: "destroy")
    moved = eng.zones_version
    expect(moved).not_to eq(before)
    gone = game.state.objects.keys.find { game.state.objects[it].zone == :library }
    game.state.zone_list(:library, 0).delete(gone)
    game.state.objects.delete(gone)
    expect(eng.zones_version).not_to eq(moved)
    eng.state = game.state.fork
    expect(eng.zones_version).not_to eq(moved)
  end

  it "removes a token that leaves the battlefield even after a scan found nothing" do
    token = Enjine::CardDefinition.token(Enjine::Tokens.fetch("Treasure"))
    game.catalog.add(token)
    eng = engine(game)
    made = eng.create_token!(token, 0)
    expect(eng.remove_tokens_outside_battlefield!).to be(false) # cached: nothing outside the battlefield
    eng.move!(made.id, :graveyard, reason: "sacrifice")
    expect(eng.remove_tokens_outside_battlefield!).to be(true)
    expect(game.state.zone_list(:graveyard, 0)).to be_empty
  end

  it "skips a graveyard card for permissions and activations only while nothing grants abilities" do
    eng = engine(game)
    eng.move!(obj_id(game, "Grizzly Bears"), :graveyard, reason: "destroy")
    bears = eng.object(obj_id(game, "Grizzly Bears", zone: :graveyard, player: "alice"))
    expect(eng.unplayable_elsewhere?(bears)).to be(true)
    expect(eng.no_activations_here?(bears)).to be(true)
    expect(eng.own_abilities_only?).to be(true)
    game.state.effects << { "kind" => "card_ability", "timestamp" => 99, "controller" => 0, "affected" => [bears.id],
                            "duration" => "permanent", "card" => "lightning_bolt", "ability" => "printed:0" }
    expect(eng.own_abilities_only?).to be(false)
  end
end
