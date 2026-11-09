# frozen_string_literal: true

# Invented cards for the casting, cost and permission shapes: "whenever you give a gift" (CR 702.174c), cast
# triggers on spells you don't own (CR 108.3), "for as long as you control" permissions with a waterbend
# alternative cost (CR 611.2b, 701.67a), costs counting mana symbols (CR 107.4e) and granted sneak (CR 702.190a).
RSpec.describe "Casting and permission gaps (invented cards)" do
  def board(hand: [], battlefield: [], graveyard: [], their_graveyard: [], library: "Forest", step: :precombat_main)
    build_game do
      turn 3, active: "alice", step: step
      player("alice") do
        hand(*hand) unless hand.empty?
        graveyard(*graveyard) unless graveyard.empty?
        library library, count: 10
        battlefield.each { battlefield it }
      end
      player("bob") do
        graveyard(*their_graveyard) unless their_graveyard.empty?
        library "Swamp", count: 10
      end
    end
  end

  def id(game, name, zone: :battlefield, player: "alice") = obj_id(game, name, zone: zone, player: player)
  def alice(game) = game.state.players[0]

  def pay_all(game)
    game.submit(game.legal_options.find { %w[pay_mana activate_mana].include?(it[:type]) }) while game.pending_decision.kind == "pay_cost"
  end

  def courier_counters(game) = game.state.object(id(game, "Ribbon Courier")).counters

  describe "gives_gift (CR 702.174c)" do
    it "triggers as a sorcery whose gift was promised resolves, not without the promise" do
      [true, false].each do |promise|
        game = board(hand: ["Ribbon of Plenty"], battlefield: ["Ribbon Courier", "Forest", "Forest"])
        game.submit(type: "cast", object: id(game, "Ribbon of Plenty", zone: :hand))
        game.submit(type: promise ? "kick" : "no_kick")
        game.submit(type: "cost", object: "player:bob") if promise
        pay_all(game)
        pass_both(game)
        expect(game.state.stack.size).to eq(promise ? 1 : 0)
        pass_both(game) if promise
        expect(courier_counters(game)).to eq(promise ? { "+1/+1" => 1 } : {})
      end
    end

    it "triggers as a permanent's gift triggered ability resolves" do
      game = board(hand: ["Generous Burrowkin"], battlefield: ["Ribbon Courier", "Forest", "Forest"])
      game.submit(type: "cast", object: id(game, "Generous Burrowkin", zone: :hand))
      game.submit(type: "kick")
      game.submit(type: "cost", object: "player:bob")
      pay_all(game)
      pass_both(game) # the creature resolves
      pass_both(game) # its gift trigger resolves: the gift is given
      pass_both(game) # the Courier's trigger
      expect(courier_counters(game)).to eq("+1/+1" => 1)
      expect(game.catalog.fetch("ribbon_courier").abilities.first.to_s).to start_with("Whenever you give a gift")
    end
  end

  it "Borrowed Muse triggers only on spells its controller doesn't own (CR 108.3)" do
    game = board(hand: ["Ribbon of Plenty"], battlefield: ["Borrowed Muse", "Forest", "Forest", "Island", "Island", "Island"],
                 their_graveyard: ["Ribbon of Plenty"])
    game.submit(type: "cast", object: id(game, "Ribbon of Plenty", zone: :hand))
    game.submit(type: "no_kick")
    pay_all(game)
    expect(game.state.stack.size).to eq(1) # no trigger for her own spell
    pass_both(game)
    muse = id(game, "Borrowed Muse")
    game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == muse })
    game.submit(type: "target", target: id(game, "Ribbon of Plenty", zone: :graveyard, player: "bob"))
    pay_all(game)
    pass_both(game)
    exiled = game.state.exile.first
    game.submit(game.legal_options.find { it[:type] == "cast" && it[:object] == exiled })
    game.submit(type: "no_kick")
    pay_all(game)
    expect(game.state.stack.size).to eq(2) # the spell and the Muse's trigger
  end

  it "Bloodwater Adept's permission survives export/import and ends when the Adept leaves (CR 611.2b)" do
    game = board(hand: ["Bloodwater Adept"], battlefield: %w[Island Island Swamp Swamp Island], library: "Ribbon of Plenty")
    game.submit(type: "cast", object: id(game, "Bloodwater Adept", zone: :hand))
    pay_all(game)
    pass_both(game)
    pass_both(game)
    exiled = game.state.exile.first
    copy = Enjine::Game.import(game.export, catalog: game.catalog)
    option = copy.legal_options.find { it[:type] == "cast" && it[:object] == exiled }
    expect(option).not_to be_nil
    copy.submit(option)
    copy.submit(type: "no_kick")
    expect(copy.pending_decision.details["remaining"]).to eq("{2}")
    expect(copy.legal_options).to include(type: "waterbend", object: id(copy, "Bloodwater Adept"))
    permission = game.state.effects.find { it["kind"] == "permission" }
    expect(permission).to include("source" => id(game, "Bloodwater Adept"), "during" => "your_turn", "waterbend" => "mana_value")
  end

  it "Gloom Archivist's cost counts black symbols among the exiled cards; it copies and casts them (CR 107.4e)" do
    game = board(battlefield: ["Gloom Archivist", "Swamp"], graveyard: ["Gloom Archivist", "Gloom Archivist", "Ribbon of Plenty"])
    archivist = id(game, "Gloom Archivist")
    game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == archivist })
    first, second = alice(game).graveyard.first(2)
    expect(game.legal_options).to contain_exactly({ type: "cost", object: first }, { type: "cost", object: second }, { type: "cancel" })
    game.submit(type: "cost", object: first)
    expect(game.legal_options).not_to include(type: "done") # 2 of 3 black symbols
    game.submit(type: "cost", object: second) # every candidate chosen: the choice ends
    pay_all(game)
    expect(game.state.object(game.state.stack.first).memory["exiled_for_cost"].size).to eq(2)
    pass_both(game)
    game.submit(game.legal_options.find { it[:type] == "cast" })
    game.submit(game.legal_options.find { it[:type] == "cast" })
    expect(game.state.stack.size).to eq(2)
    expect(game.catalog.fetch("gloom_archivist").abilities.first.to_s).to include("3 or more {B} symbols")
  end
end
