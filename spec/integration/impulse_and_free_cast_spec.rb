# frozen_string_literal: true

# Exiling cards with permission to play them (CR 611.2, 601.3), casting during resolution without paying
# mana costs (CR 608.2g, 118.9) and discover (CR 701.57).
RSpec.describe "Impulse draw, free casts and discover" do
  let(:foresight) do
    { "name" => "Rash Foresight", "mana_cost" => "{1}{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [
        { "exile_top" => { "amount" => 2 } },
        { "play_permission" => { "to" => { "result" => 0 }, "duration" => "end_of_your_next_turn" } }
      ] } }] }
  end
  let(:gambit) do
    { "name" => "Prospector's Gambit", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "effects" => [
        { "exile_until" => { "until" => "nonland" } },
        { "play_permission" => { "to" => { "result" => 0 }, "not_types" => ["land"] } }
      ] } }] }
  end
  let(:annexer) do
    { "name" => "Border Annexer", "mana_cost" => "{3}{U}", "types" => ["creature"], "power" => 1, "toughness" => 5,
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} }, "effects" => [
        { "exile_top" => { "amount" => 3, "to" => "each_opponent" } },
        { "play_permission" => { "to" => { "result" => 0 }, "for" => { "types" => ["land"] }, "choose" => "one_per_owner",
                                 "duration" => "while_exiled" } }
      ] } }] }
  end
  let(:feast) do
    { "name" => "Feast Engine", "mana_cost" => "{3}", "types" => ["artifact"],
      "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{1}" }, "tap"], "effects" => [
        { "exile_top" => { "amount" => 3 } },
        { "cast_free" => { "to" => { "result" => 0 }, "max_mana_value" => 3, "count" => "any" } }
      ] } }] }
  end
  let(:warden) do
    { "name" => "Void Warden Rite", "mana_cost" => "{3}{U}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => ["opponent"], "effects" => [
        { "exile_until" => { "until" => "nonland", "to" => { "target" => 0 } } },
        { "cast_free" => { "to" => { "result" => 0 } } }
      ] } }] }
  end
  let(:bluff) do
    { "name" => "Sly Rebuttal", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "effects" => [{ "cast_free" => { "not_types" => ["creature"] } }] } }] }
  end
  let(:probe) do
    { "name" => "Deep Probe", "mana_cost" => "{2}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "discover" => { "amount" => 3 } }] } }] }
  end
  let(:catalog) { catalog_with(foresight, gambit, annexer, feast, warden, bluff, probe) }

  def board(alice: {}, bob: {}, turn: 3, active: "alice")
    build_game(catalog) do
      turn turn, active: active, step: :precombat_main
      [["alice", alice], ["bob", bob]].each do |name, zones|
        player(name) do
          zones.each { |zone, cards| Array(cards).each { public_send(zone, it) } }
          library "Forest", count: 5 unless zones.key?(:library)
        end
      end
    end
  end

  def pay!(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def cast!(game, card, player: "alice")
    game.submit(type: "cast", object: ids_in(game, player, :hand).find { game.state.object(it).card == card })
    pay!(game)
  end

  def cards(game, ids) = ids.map { game.state.object(it).card }

  it "exiles the top cards; they can be played until the end of the controller's next turn (CR 611.2, 514.2)" do
    game = board(alice: { hand: "Rash Foresight", battlefield: %w[Mountain Mountain Mountain],
                          library: ["Lightning Bolt", "Forest", "Island", "Island", "Island"] })
    cast!(game, "rash_foresight")
    pass_both(game)
    expect(cards(game, game.state.exile)).to eq(%w[forest lightning_bolt])
    land, bolt = game.state.exile
    effect = game.state.effects.find { it["kind"] == "permission" }
    via = "effect:#{effect["timestamp"]}"
    expect(game.legal_options).to include({ type: "play_land", object: land, via: via }, { type: "cast", object: bolt, via: via })
    expect(game.view_for("bob")["effects"].map { it["kind"] }).to eq(["permission"])
    skip_to(game, :precombat_main, turn: 4)
    expect(game.state.effects.size).to eq(1) # bob's turn doesn't end it
    game.submit(type: "pass")
    skip_to(game, :precombat_main, turn: 5)
    expect(game.legal_options).to include({ type: "cast", object: bolt, via: via })
    game.submit(type: "cast", object: bolt, via: via)
    game.submit(type: "target", target: "player:bob")
    pay!(game)
    expect(game.state.exile).to eq([land])
    skip_to(game, :precombat_main, turn: 6)
    expect(game.state.effects).to be_empty # ended in the cleanup of alice's next turn
  end

  it "exiles until a nonland card and lets only that card be played this turn" do
    game = board(alice: { hand: "Prospector's Gambit", battlefield: %w[Mountain Mountain],
                          library: ["Forest", "Island", "Lightning Bolt", "Forest"] })
    cast!(game, "prospectors_gambit")
    pass_both(game)
    expect(cards(game, game.state.exile)).to eq(%w[lightning_bolt island forest])
    expect(game.state.effects.first["affected"]).to eq([game.state.exile.first])
    expect(game.state.effects.first["duration"]).to eq("end_of_turn")
  end

  it "chooses one land card per opponent among the cards exiled; it stays playable while exiled" do
    game = board(alice: { hand: "Border Annexer", battlefield: %w[Island Island Island Island] },
                 bob: { library: ["Forest", "Lightning Bolt", "Mountain", "Island"] })
    cast!(game, "border_annexer")
    pass_both(game) # the creature resolves; its trigger goes on the stack
    pass_both(game)
    forest, _bolt, mountain = game.state.exile.reverse
    expect(game.pending_decision.kind).to eq("effect_choice")
    expect(game.legal_options).to eq([{ type: "choose", object: forest }, { type: "choose", object: mountain }])
    game.submit(type: "choose", object: mountain)
    effect = game.state.effects.find { it["kind"] == "permission" }
    expect(effect).to include("affected" => [mountain], "duration" => "while_exiled", "controller" => 0)
    option = { type: "play_land", object: mountain, via: "effect:#{effect["timestamp"]}" }
    expect(game.legal_options).to include(option)
    game.submit(option)
    expect(game.state.object(game.state.battlefield.first)).to have_attributes(card: "mountain", owner: 1, controller: 0)
  end

  it "casts any number of exiled cards free during resolution, without priority in between (CR 608.2g)" do
    game = board(alice: { battlefield: ["Feast Engine", "Forest"], library: ["Lightning Bolt", "Divination", "Hill Giant"] })
    game.submit(type: "activate", object: obj_id(game, "Feast Engine"), ability: "printed:0")
    pay!(game)
    pass_both(game)
    bolt, divination, giant = game.state.exile.reverse
    expect(game.legal_options).to eq([{ type: "cast", object: bolt }, { type: "cast", object: divination }, { type: "done" }])
    game.submit(type: "cast", object: bolt)
    expect(game.pending_decision.kind).to eq("choose_target")
    game.submit(type: "cancel") # a cancelled cast counts as declined
    expect(game.state.exile).to include(bolt)
    expect(game.legal_options).to eq([{ type: "cast", object: divination }, { type: "done" }])
    game.submit(type: "cast", object: divination) # nothing to choose: cast at once, back to the resolution
    expect(cards(game, game.state.stack)).to eq(["divination"]) # nothing left to cast: the resolution ended
    expect(game.state.exile).to contain_exactly(bolt, giant)
    expect(game.pending_decision.kind).to eq("priority")
  end

  it "goes straight back to the resolution after a free cast with choices, without priority (CR 608.2g)" do
    game = board(alice: { battlefield: ["Feast Engine", "Forest"], library: ["Lightning Bolt", "Divination", "Hill Giant"] })
    game.submit(type: "activate", object: obj_id(game, "Feast Engine"), ability: "printed:0")
    pay!(game)
    pass_both(game)
    game.submit(type: "cast", object: game.state.exile.last)
    game.submit(type: "target", target: "player:bob")
    expect(game.pending_decision.kind).to eq("effect_choice")
    game.submit(type: "done")
    expect(cards(game, game.state.stack)).to eq(["lightning_bolt"])
    expect(game.pending_decision.kind).to eq("priority")
  end

  it "survives export and import in the middle of a free cast" do
    game = board(alice: { battlefield: ["Feast Engine", "Forest"], library: ["Lightning Bolt", "Divination", "Hill Giant"] })
    game.submit(type: "activate", object: obj_id(game, "Feast Engine"), ability: "printed:0")
    pay!(game)
    pass_both(game)
    game.submit(type: "cast", object: game.state.exile.last)
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.state.to_h).to eq(game.state.to_h)
    copy.submit(type: "target", target: "player:bob")
    expect(copy.pending_decision.kind).to eq("effect_choice")
  end

  it "the controller casts an opponent's exiled card; it stays the opponent's card (CR 601.2a)" do
    game = board(alice: { hand: "Void Warden Rite", battlefield: %w[Island Island Island Island] },
                 bob: { library: ["Forest", "Grizzly Bears", "Forest"] })
    cast!(game, "void_warden_rite")
    game.submit(type: "target", target: "player:bob") if game.pending_decision.kind == "choose_target"
    pay!(game)
    pass_both(game)
    bears = game.state.exile.first
    expect(game.legal_options).to eq([{ type: "cast", object: bears }, { type: "done" }])
    game.submit(type: "cast", object: bears)
    pass_both(game)
    expect(game.state.object(game.state.battlefield.first)).to have_attributes(card: "grizzly_bears", owner: 1, controller: 0)
  end

  it "casts a matching spell from the hand free; creature spells aren't offered" do
    game = board(alice: { hand: ["Sly Rebuttal", "Grizzly Bears", "Divination"], battlefield: ["Mountain"] })
    cast!(game, "sly_rebuttal")
    pass_both(game)
    divination = ids_in(game, "alice", :hand).find { game.state.object(it).card == "divination" }
    expect(game.legal_options).to eq([{ type: "cast", object: divination }, { type: "done" }])
    entry = game.submit(type: "cast", object: divination)
    expect(entry.events.grep(Enjine::Events::SpellCast).first.during_resolution).to be(true)
    pass_both(game)
    expect(ids_in(game, "alice", :hand).size).to eq(3) # Bears + two drawn
  end

  it "discovers: exiles to a nonland card with mana value N or less, casts it free, bottoms the rest (CR 701.57a)" do
    game = board(alice: { hand: "Deep Probe", battlefield: %w[Forest Forest],
                          library: ["Forest", "Hill Giant", "Grizzly Bears", "Island"] })
    cast!(game, "deep_probe")
    pass_both(game)
    bears = game.state.exile.first
    expect(game.legal_options).to eq([{ type: "cast", object: bears }, { type: "hand", object: bears }])
    game.submit(type: "cast", object: bears)
    expect(cards(game, game.state.stack)).to eq(["grizzly_bears"])
    expect(cards(game, ids_in(game, "alice", :library))).to eq(%w[island forest hill_giant].first(1) +
                                                                 cards(game, ids_in(game, "alice", :library)).drop(1))
    expect(cards(game, ids_in(game, "alice", :library)).drop(1)).to contain_exactly("forest", "hill_giant")
    expect(game.state.exile).to be_empty
  end

  it "discovers into the hand when the player declines or cancels the cast" do
    game = board(alice: { hand: "Deep Probe", battlefield: %w[Forest Forest], library: ["Lightning Bolt", "Island"] })
    cast!(game, "deep_probe")
    pass_both(game)
    game.submit(type: "cast", object: game.state.exile.first)
    game.submit(type: "cancel")
    expect(cards(game, ids_in(game, "alice", :hand))).to eq(["lightning_bolt"])
    other = board(alice: { hand: "Deep Probe", battlefield: %w[Forest Forest], library: ["Grizzly Bears"] })
    cast!(other, "deep_probe")
    pass_both(other)
    other.submit(type: "hand", object: other.state.exile.first)
    expect(cards(other, ids_in(other, "alice", :hand))).to eq(["grizzly_bears"])
  end

  it "discovers nothing from a library without a matching card" do
    game = board(alice: { hand: "Deep Probe", battlefield: %w[Forest Forest], library: ["Forest", "Hill Giant"] })
    cast!(game, "deep_probe")
    pass_both(game)
    expect(cards(game, ids_in(game, "alice", :library))).to contain_exactly("forest", "hill_giant")
    expect(game.pending_decision.kind).to eq("priority")
  end
end
