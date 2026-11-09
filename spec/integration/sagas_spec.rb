# frozen_string_literal: true

# Sagas: CR 715 and 704.5s.
RSpec.describe "Sagas (CR 715, 704.5s, 505.4)" do
  let(:double_chapter) do
    { "name" => "Twofold Annals", "mana_cost" => "{1}{W}", "types" => ["enchantment"], "subtypes" => ["saga"],
      "abilities" => [{ "chapter" => { "chapter" => 1, "effects" => [{ "gain_life" => { "amount" => 1 } }] } },
                      { "chapter" => { "chapter" => 2, "effects" => [{ "gain_life" => { "amount" => 2 } }] } },
                      { "chapter" => { "chapter" => 3, "effects" => [{ "gain_life" => { "amount" => 4 } }] } }] }
  end
  let(:quill) do
    { "name" => "Hastening Quill", "mana_cost" => "{U}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["permanent"], "effects" => [
        { "add_counters" => { "counter" => "lore", "amount" => 2, "to" => { "target" => 0 } } }
      ] } }] }
  end
  let(:catalog) { catalog_with(double_chapter, quill) }

  def life(game, name) = game.view_for(:observer)["players"].find { it["name"] == name }["life"]
  def saga(game, card = "chronicle_of_embers") = game.state.battlefield.find { game.state.object(it).card == card }
  def lore(game, card = "chronicle_of_embers") = game.state.object(saga(game, card)).counters["lore"]
  def stack_names(game) = game.view_for(:observer)["stack"].map { it["name"] }

  def cast(game, card)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) })
  end

  def pay_all(game)
    while game.pending_decision.kind == "pay_cost"
      option = game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" }
      game.submit(option)
    end
  end

  def at_draw(saga_card, lore, active: "alice", bob_board: [])
    build_game(catalog) do
      turn 3, active: active, step: :draw
      player("alice") do
        battlefield saga_card, counters: { "lore" => lore }
        library "Forest", count: 3
      end
      player("bob") do
        bob_board.each { battlefield it }
        library "Forest", count: 3
      end
    end
  end

  it "enters with a lore counter, which triggers chapter I (CR 715.3a, 715.2b, 122.6)" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Chronicle of Embers"
        battlefield "Mountain", "Mountain"
        library "Forest", count: 3
      end
      player("bob") { library "Forest", count: 3 }
    end
    cast(game, "Chronicle of Embers")
    pay_all(game)
    pass_both(game) # the Saga resolves and enters
    expect(lore(game)).to eq(1)
    expect(stack_names(game)).to eq(["Chronicle of Embers ability"])
    pass_both(game)
    expect(life(game, "bob")).to eq(19)
    expect(saga(game)).not_to be_nil # not at its final chapter yet
  end

  it "adds a lore counter as the precombat main phase begins; chapter II targets as it goes on the stack (CR 715.3c)" do
    game = at_draw("Chronicle of Embers", 1, bob_board: ["Grizzly Bears"])
    bears = obj_id(game, "Grizzly Bears")
    pass_both(game) # the draw step ends
    expect(game.step).to eq(:precombat_main)
    expect(lore(game)).to eq(2)
    expect(game.pending_decision.kind).to eq("choose_target")
    expect(game.legal_options).to eq([{ type: "target", target: bears }]) # a trigger can't be cancelled
    game.submit(type: "target", target: bears)
    pass_both(game)
    expect(game.state.battlefield).not_to include(bears)
  end

  it "is sacrificed after its final chapter ability leaves the stack, not before (CR 715.4, 704.5s)" do
    game = at_draw("Chronicle of Embers", 2)
    id = saga(game)
    hand = ids_in(game, "alice", :hand).size
    pass_both(game)
    expect(lore(game)).to eq(3)
    expect(stack_names(game)).to eq(["Chronicle of Embers ability"])
    expect(game.state.battlefield).to include(id) # chapter III is still on the stack
    entry = nil
    2.times { entry = game.submit(type: "pass") }
    expect(ids_in(game, "alice", :hand).size).to eq(hand + 1)
    expect(game.state.battlefield).not_to include(id)
    expect(entry.events.find { it.is_a?(Enjine::Events::ZoneChanged) && it.old_id == id }.reason).to eq("sacrifice")
  end

  it "a chapter ability removed for lack of targets triggers nothing (CR 603.3d)" do
    game = at_draw("Chronicle of Embers", 1)
    pass_both(game) # chapter II has no creature to target
    expect(lore(game)).to eq(2)
    expect(game.state.stack).to be_empty
  end

  it "the turn-based action only counts the active player's Sagas (CR 505.4)" do
    game = at_draw("Chronicle of Embers", 1, active: "bob")
    pass_both(game)
    expect(lore(game)).to eq(1)
  end

  it "two lore counters at once trigger both chapters they pass (CR 715.2b), and it round-trips mid-way" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Hastening Quill"
        battlefield "Twofold Annals", counters: { "lore" => 1 }
        battlefield "Island"
        library "Forest", count: 3
      end
      player("bob") { library "Forest", count: 3 }
    end
    annals = saga(game, "twofold_annals")
    cast(game, "Hastening Quill")
    game.submit(type: "target", target: annals)
    pay_all(game)
    pass_both(game)
    expect(lore(game, "twofold_annals")).to eq(3)
    game.submit(game.legal_options.first) if game.pending_decision.kind == "order_triggers"
    expect(stack_names(game)).to eq(["Twofold Annals ability"] * 2)
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.state.to_h).to eq(game.state.to_h)
    pass_both(copy, 2)
    expect(life(copy, "alice")).to eq(26)
    expect(copy.state.battlefield).not_to include(annals) # final chapter (3) resolved: sacrificed
  end
end
