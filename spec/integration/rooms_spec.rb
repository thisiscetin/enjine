# frozen_string_literal: true

# Room cards: split cards with a shared type line, doors that unlock (CR 709.5). Invented test cards only.
RSpec.describe "Rooms (CR 709.3-709.5, 116.2m)" do
  let(:room) do
    { "name" => "Spec Annex // Spec Chamber", "layout" => "room", "faces" => [
      { "name" => "Spec Annex", "mana_cost" => "{1}{B}", "types" => ["enchantment"], "subtypes" => ["room"],
        "abilities" => [{ "triggered" => { "when" => { "step_begins" => { "step" => "end", "whose" => "your" } },
                                           "effects" => [{ "draw" => { "amount" => 1 } }] } }] },
      { "name" => "Spec Chamber", "mana_cost" => "{2}{B}", "types" => ["enchantment"], "subtypes" => ["room"],
        "abilities" => [{ "triggered" => { "when" => { "unlocks_door" => {} },
                                           "effects" => [{ "create_token" => { "token" => { "name" => "Demon", "types" => ["creature"],
                                                                                            "subtypes" => ["demon"], "colors" => ["B"],
                                                                                            "power" => 6, "toughness" => 6 } } }] } }] }
    ] }
  end
  let(:scavenger) do
    { "name" => "Spec Scavenger", "mana_cost" => "{W}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "unlocks_door" => { "door" => "any", "fully" => true,
                                                                         "subject" => { "each" => "permanent", "controller" => "you" } } },
                                         "effects" => [{ "gain_life" => { "amount" => 3 } }] } }] }
  end
  let(:reanimate) do
    { "name" => "Spec Return", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => [{ "graveyard_card" => { "controller" => "you" } }],
                                     "effects" => [{ "return_to_battlefield" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:catalog) { catalog_with(room, scavenger, reanimate) }

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, name) = game.view_for(:observer)["players"].find { it["name"] == name }["life"]
  def room_in_play(game) = game.state.battlefield.find { game.state.object(it).card.start_with?("spec_annex") }

  def board(hand: ["Spec Annex // Spec Chamber"], field: [], graveyard: [], step: :precombat_main)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice") do
        hand.each { hand it }
        graveyard.each { graveyard it }
        ((["Swamp"] * 6) + field).each { battlefield it }
        library "Forest", count: 10
      end
      player("bob") { library "Forest", count: 10 }
    end
  end

  def pay_all(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  it "has both halves combined in the hand (CR 709.4, 709.4b) and is cast as one door (CR 709.3)" do
    game = board
    card = ids_in(game, "alice", :hand).first
    chars = engine(game).chars(game.state.object(card))
    expect(chars.name).to eq("Spec Annex // Spec Chamber")
    expect(chars.mana_cost.mana_value).to eq(5)
    casts = game.legal_options.select { it[:type] == "cast" && it[:object] == card }
    expect(casts.map { it[:face] }).to contain_exactly(1, 2)
    game.submit(casts.find { it[:face] == 1 })
    pay_all(game)
    spell = engine(game).chars(game.state.object(game.state.stack.first))
    expect([spell.name, spell.mana_cost.mana_value]).to eq(["Spec Annex", 2]) # CR 709.3b
    pass_both(game)
    perm = game.state.object(room_in_play(game))
    expect(engine(game).unlocked_doors(perm)).to eq(["left"])
    expect(engine(game).chars(perm).name).to eq("Spec Annex")
    expect(Enjine::Mechanics::Amount.mana_value(engine(game), perm)).to eq(2) # the locked door's mana cost doesn't count
    expect(game.view_for("bob")["battlefield"].find { it["id"] == perm.id }["unlocked"]).to eq(["left"])
  end

  it "unlocks a locked door as a sorcery-speed special action for its mana cost; its unlock trigger fires (CR 709.5e, 709.5h)" do
    game = board(field: ["Spec Scavenger"])
    game.submit(game.legal_options.find { it[:type] == "cast" && it[:face] == 1 })
    pay_all(game)
    expect(game.legal_options.select { it[:type] == "unlock" }).to be_empty # the stack isn't empty
    pass_both(game)
    perm = room_in_play(game)
    option = { type: "unlock", object: perm, door: "right" }
    expect(game.legal_options).to include(option)
    expect(game.legal_options).not_to include(type: "unlock", object: perm, door: "left")
    game.submit(option)
    pay_all(game)
    obj = game.state.object(perm)
    expect(engine(game).unlocked_doors(obj)).to eq(%w[left right])
    expect(engine(game).chars(obj).name).to eq("Spec Annex // Spec Chamber")
    expect(Enjine::Mechanics::Amount.mana_value(engine(game), obj)).to eq(5)
    game.submit(game.legal_options.first) if game.pending_decision.kind == "order_triggers"
    expect(game.view_for(:observer)["stack"].map { it["name"] }).to contain_exactly("Spec Annex // Spec Chamber ability",
                                                                                    "Spec Scavenger ability")
    pass_both(game, 2)
    expect(game.state.battlefield.map { game.state.object(it).card }.grep(/demon/).size).to eq(1)
    expect(life(game, "alice")).to eq(23) # fully unlocked (CR 709.5i)
  end

  it "casting the door with an unlock trigger triggers it as the permanent enters (CR 709.5h)" do
    game = board
    game.submit(game.legal_options.find { it[:type] == "cast" && it[:face] == 2 })
    pay_all(game)
    pass_both(game)
    expect(game.view_for(:observer)["stack"].map { it["name"] }).to eq(["Spec Chamber ability"])
    pass_both(game)
    expect(game.state.battlefield.map { game.state.object(it).card }.grep(/demon/).size).to eq(1)
  end

  it "enters with both doors locked when it isn't cast (CR 709.5d): no name and mana value 0, both doors unlockable" do
    game = board(hand: ["Spec Return"], graveyard: ["Spec Annex // Spec Chamber"])
    game.submit(game.legal_options.find { it[:type] == "cast" })
    game.submit(type: "target", target: ids_in(game, "alice", :graveyard).first)
    pay_all(game)
    pass_both(game)
    obj = game.state.object(room_in_play(game))
    expect(engine(game).unlocked_doors(obj)).to eq([])
    expect(engine(game).chars(obj).name).to eq("")
    expect(engine(game).chars(obj).abilities).to be_empty
    expect(Enjine::Mechanics::Amount.mana_value(engine(game), obj)).to eq(0)
    expect(game.legal_options.select { it[:type] == "unlock" }.map { it[:door] }).to contain_exactly("left", "right")
    expect(engine(game).lock_door!(obj, "left")).to be(false)
    engine(game).unlock_door!(obj, "left")
    expect(engine(game).lock_door!(obj, "left")).to be(true) # CR 709.5g
    expect(engine(game).unlocked_doors(obj)).to eq([])
  end

  it "goes back to its combined characteristics off the battlefield, and round-trips through export/import" do
    game = board
    game.submit(game.legal_options.find { it[:type] == "cast" && it[:face] == 1 })
    pay_all(game)
    pass_both(game)
    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.state.object(room_in_play(copy)).card).to eq("spec_annex/1")
    fresh = engine(game).move!(room_in_play(game), :graveyard, reason: "test")
    expect(fresh.card).to eq("spec_annex")
  end

  it "validates a Room's doors (CR 709.5, 709.5a)" do
    bad = room.merge("faces" => [room["faces"][0], room["faces"][1].merge("subtypes" => ["saga"])])
    expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition, /share one type line/)
    named = room.merge("name" => "Wrong // Name")
    expect { Enjine::CardDefinition.from_h(named) }.to raise_error(Enjine::InvalidCardDefinition, /doors' names/)
    defn = Enjine::CardDefinition.from_h(room)
    expect(Enjine::CardDefinition.from_h(defn.to_h)).to eq(defn)
    stray = { "name" => "Spec Stray", "mana_cost" => "{1}", "types" => ["artifact"],
              "abilities" => [{ "triggered" => { "when" => { "unlocks_door" => {} }, "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
    expect { Enjine::CardDefinition.from_h(stray) }.to raise_error(Enjine::InvalidCardDefinition, /door/)
  end
end
