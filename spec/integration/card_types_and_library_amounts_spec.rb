# frozen_string_literal: true

# Amounts: card types among cards (delirium and "*" power, CR 205.2a, 604.3), the greatest mana value among
# objects (CR 202.3) and the number of cards in a library (CR 401.1).
RSpec.describe "Amounts: card types among cards, greatest mana value, library size" do
  let(:graveyard_cards) { { "each" => { "graveyard_card" => {} }, "controller" => "any" } }
  let(:lurker) do
    { "name" => "Spec Grave Lurker", "mana_cost" => "{1}{G}", "types" => ["creature"],
      "power" => { "card_types" => graveyard_cards },
      "toughness" => { "plus" => [{ "card_types" => graveyard_cards }, 1] } }
  end
  let(:omen) do
    { "name" => "Spec Delirious Omen", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [
        { "draw" => { "amount" => 1 } },
        { "draw" => { "amount" => 1, "if" => { "amount" => { "card_types" => { "each" => { "graveyard_card" => {} },
                                                                               "controller" => "you" } },
                                               "at_least" => 4 } } }
      ] } }] }
  end
  let(:halving) do
    { "name" => "Spec Halving Tide", "mana_cost" => "{U}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => ["player"], "effects" => [
        { "mill" => { "to" => { "target" => 0 },
                      "amount" => { "divide" => [{ "plus" => [{ "library_size" => { "target" => 0 } }, 1] }, 2] } } }
      ] } }] }
  end
  let(:measure) do
    { "name" => "Spec Measure of Might", "mana_cost" => "{W}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [
        { "gain_life" => { "amount" => { "greatest_mana_value" => { "each" => "creature", "controller" => "you" } } } }
      ] } }] }
  end
  let(:catalog) { catalog_with(lurker, omen, halving, measure) }

  def engine(game) = game.instance_variable_get(:@engine)
  def player(game, name) = game.state.players[game.names.index(name)]

  def board(hand: [], alice_graveyard: [], bob_graveyard: [], alice_battlefield: [], bob_library: 5, mana: {})
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: mana) do
        alice_battlefield.each { battlefield it }
        hand(*hand)
        graveyard(*alice_graveyard)
        library "Forest", count: 5
      end
      player("bob") do
        graveyard(*bob_graveyard)
        library "Forest", count: bob_library
      end
    end
  end

  # Passes priority and pays from the pool until the stack is empty; answers targets with `targets`.
  def cast(game, card, target: nil)
    id = ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) }
    game.submit(type: "cast", object: id)
    until (decision = game.pending_decision).kind == "priority" && game.state.stack.empty?
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { it[:type] == "pay_mana" } || raise("can't pay"))
      else game.submit(game.legal_options.find { target.nil? || it.values.include?(target) } || raise(decision.kind))
      end
    end
    game
  end

  describe "card_types (CR 205.2a)" do
    it "defines power and toughness from the card types among cards in all graveyards, each type once (CR 604.3)" do
      game = board(alice_battlefield: ["Spec Grave Lurker"], alice_graveyard: ["Forest", "Forest", "Grizzly Bears"],
                   bob_graveyard: ["Goblin Warcry"])
      lurker = engine(game).object(obj_id(game, "Spec Grave Lurker"))
      # land, creature, kindred, instant: Forest twice counts once.
      expect(engine(game).power(lurker)).to eq(4)
      expect(engine(game).toughness(lurker)).to eq(5)
    end

    it "is 0 with empty graveyards: a 0/1" do
      game = board(alice_battlefield: ["Spec Grave Lurker"])
      lurker = engine(game).object(obj_id(game, "Spec Grave Lurker"))
      expect([engine(game).power(lurker), engine(game).toughness(lurker)]).to eq([0, 1])
    end

    it "counts itself while it's in a graveyard, in every zone (CR 604.3)" do
      game = board(alice_graveyard: ["Spec Grave Lurker", "Forest"])
      lurker = engine(game).object(obj_id(game, "Spec Grave Lurker", zone: :graveyard, player: "alice"))
      expect(engine(game).power(lurker)).to eq(2) # creature and land
    end

    it "follows cards moving into a graveyard mid-game (CR 613.4a: recomputed, not cached)" do
      game = board(hand: ["Spec Halving Tide"], alice_battlefield: ["Spec Grave Lurker"], mana: { U: 1 })
      lurker = engine(game).object(obj_id(game, "Spec Grave Lurker"))
      expect(engine(game).power(lurker)).to eq(0)
      cast(game, "Spec Halving Tide", target: "player:bob")
      expect(engine(game).power(lurker)).to eq(2) # the sorcery (sorcery) and milled Forests (land)
    end

    it "checks delirium: four or more card types among cards in your graveyard" do
      game = cast(board(hand: ["Spec Delirious Omen"], alice_graveyard: ["Forest", "Grizzly Bears", "Arc Lantern"],
                        bob_graveyard: ["Ash Warden"], mana: { B: 1 }), "Spec Delirious Omen")
      expect(player(game, "alice").hand.size).to eq(1) # three types in alice's graveyard: one card
      game = cast(board(hand: ["Spec Delirious Omen"], alice_graveyard: ["Forest", "Grizzly Bears", "Arc Lantern", "Ambush Writ"],
                        mana: { B: 1 }), "Spec Delirious Omen")
      expect(player(game, "alice").hand.size).to eq(2)
    end
  end

  describe "library_size (CR 401.1)" do
    it "mills half a target player's library, rounded up (CR 107.1a)" do
      game = cast(board(hand: ["Spec Halving Tide"], bob_library: 5, mana: { U: 1 }), "Spec Halving Tide",
                  target: "player:bob")
      expect(player(game, "bob").library.size).to eq(2)
      expect(player(game, "bob").graveyard.size).to eq(3)
    end
  end

  describe "greatest_mana_value (CR 202.3)" do
    it "reads the greatest mana value among the selected objects, 0 for none" do
      game = cast(board(hand: ["Spec Measure of Might"], alice_battlefield: ["Grizzly Bears", "Craw Wurm"], mana: { W: 1 }),
                  "Spec Measure of Might")
      expect(player(game, "alice").life).to eq(20 + 6)
      game = cast(board(hand: ["Spec Measure of Might"], mana: { W: 1 }), "Spec Measure of Might")
      expect(player(game, "alice").life).to eq(20)
    end
  end
end
