# frozen_string_literal: true

# Converted Star Trek cards that play cards from other zones: beam me up (CR 702.196), graveyard casting,
# impulse draw and discover (CR 701.57). Card data comes from lib/enjine/sets/trk.json.
RSpec.describe "Star Trek play permissions (trk)" do
  let(:set_cards) { Enjine::Sets.load("trk").cards }
  let(:catalog) do
    wanted = ["Scotty, Miracle Worker", "Energize", "Storied Veteran", "Reckless Impulse", "U.S.S. Discovery, at Black Alert",
              "Encounter the Unknown", "Shields Up!"]
    catalog_with(*set_cards.select { wanted.include?(it.name) })
  end

  def pay!(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def board(alice)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        alice.each { |zone, cards| Array(cards).each { public_send(zone, it) } }
        library "Forest", count: 5 unless alice.key?(:library)
      end
      player("bob") do
        battlefield "Grizzly Bears"
        library "Forest", count: 5
      end
    end
  end

  def card(game, slug, zone) = ids_in(game, "alice", zone).find { game.state.object(it).card == slug }

  it "Energize beams up from the graveyard; Scotty also grants beam me up for its mana cost but can't pay it" do
    game = board(battlefield: ["Scotty, Miracle Worker", "Island", "Island", "Island", "Island"], graveyard: ["Energize"])
    energize = card(game, "energize", :graveyard)
    scotty = obj_id(game, "Scotty, Miracle Worker")
    casts = game.legal_options.select { it[:type] == "cast" }
    expect(casts).to eq([{ type: "cast", object: energize, via: "beam:printed:1" }]) # no other creature for Scotty's way
    game.submit(casts.first)
    game.submit(type: "target", target: obj_id(game, "Grizzly Bears"))
    expect(game.legal_options).to eq([{ type: "cost", object: scotty }, { type: "cancel" }]) # its own beam may return Scotty
    game.submit(type: "cost", object: scotty)
    pay!(game)
    pass_both(game)
    expect(game.state.exile.map { game.state.object(it).card }).to eq(["energize"])
    expect(ids_in(game, "bob", :hand).size).to eq(1)
  end

  it "Storied Veteran is cast from the graveyard and enters with a finality counter" do
    game = board(battlefield: ["Swamp"], graveyard: ["Storied Veteran"])
    game.submit(type: "cast", object: card(game, "storied_veteran", :graveyard), via: "self:printed:0")
    pay!(game)
    pass_both(game)
    expect(game.state.object(obj_id(game, "Storied Veteran")).counters).to eq("finality" => 1)
  end

  it "Reckless Impulse and Encounter the Unknown exile two cards to play until the end of the next turn" do
    game = board(hand: ["Reckless Impulse"], battlefield: %w[Mountain Mountain], library: %w[Mountain Forest Island])
    game.submit(type: "cast", object: card(game, "reckless_impulse", :hand))
    pay!(game)
    pass_both(game)
    expect(game.state.effects).to contain_exactly(a_hash_including("kind" => "permission", "duration" => "end_of_your_next_turn"))
    encounter = board(hand: ["Encounter the Unknown"], battlefield: %w[Mountain Mountain Mountain])
    encounter.submit(type: "cast", object: card(encounter, "encounter_the_unknown", :hand))
    encounter.submit(type: "mode", mode: 1)
    pay!(encounter)
    pass_both(encounter)
    expect(encounter.state.battlefield.map { encounter.state.object(it).card }).not_to include("grizzly_bears")
    expect(encounter.view_for(:observer)["players"].map { it["life"] }).to eq([18, 18])
  end

  it "U.S.S. Discovery discovers 5 as it enters" do
    game = board(hand: ["U.S.S. Discovery, at Black Alert"], battlefield: %w[Forest Forest Forest Forest Forest],
                 library: ["Forest", "Encounter the Unknown", "Forest"])
    game.submit(type: "cast", object: card(game, "u_s_s_discovery_at_black_alert", :hand))
    pay!(game)
    pass_both(game) # the Spacecraft resolves, its trigger goes on the stack
    pass_both(game)
    expect(game.legal_options.map { it[:type] }).to eq(%w[cast hand])
  end

  it "Shields Up! puts a +1/+1 counter only on a creature" do
    game = board(hand: ["Shields Up!"], battlefield: ["Plains", "Plains", "Grizzly Bears"])
    bears = obj_id(game, "Grizzly Bears")
    game.submit(type: "cast", object: card(game, "shields_up", :hand))
    game.submit(type: "target", target: bears)
    pay!(game)
    pass_both(game)
    expect(game.state.object(bears).counters).to eq("+1/+1" => 1)
    expect(game.view_for(:observer)["battlefield"].find { it["id"] == bears }["keywords"]).to be_nil # printed only
    expect(game.state.effects.first["keywords"]).to eq(%w[hexproof indestructible])
  end
end
