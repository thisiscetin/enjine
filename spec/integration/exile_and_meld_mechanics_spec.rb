# frozen_string_literal: true

# Invented cards for hideaway (CR 702.75a), paradigm (CR 702.192a), foretell (CR 702.143), suspend (CR 702.62),
# devour (CR 702.82) and meld (CR 701.42, 713): the edges the real-card scenarios don't reach.
RSpec.describe "Exile, suspend and meld mechanics" do
  let(:cards) do
    [
      { "name" => "Spec Hidden Vault", "types" => ["land"],
        "abilities" => [{ "hideaway" => { "amount" => 3 } }, { "mana" => { "cost" => ["tap"], "produce" => "{C}" } },
                        { "activated" => { "cost" => ["tap"],
                                           "effects" => [{ "cast_free" => { "to" => "exiled_with", "play" => true } }] } }] }
    ]
  end
  let(:catalog) { catalog_with(*cards) }

  def board(hand: [], field: [], library: ["Forest"], lands_played: 0, active: "alice", mana: {})
    build_game(catalog) do
      turn 3, active: active, step: :precombat_main
      player("alice", lands_played: lands_played, mana_pool: mana) do
        hand(*hand) unless hand.empty?
        field.each { battlefield it }
        library(*library, count: 5)
      end
      player("bob") { library "Forest", count: 5 }
    end
  end

  def resolve_all(game)
    game.submit(type: "pass") while game.pending_decision.kind == "priority" && !game.state.stack.empty?
  end

  def hand_card(game, name) = ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(name) }

  describe "foretell (CR 702.143a, 116.2h) with Portent Spark (fixture)" do
    it "is a special action during your turn; cancelling its payment changes nothing" do
      expect(option_types(board(hand: ["Portent Spark"], mana: { C: 1 }))).not_to include("special_action") # can't pay {2}
      game = board(hand: ["Portent Spark"], mana: { C: 2 })
      spark = hand_card(game, "Portent Spark")
      game.submit(type: "special_action", object: spark, ability: "printed:1")
      expect(game.pending_decision.kind).to eq("pay_cost")
      game.submit(type: "cancel")
      expect(game.pending_decision.kind).to eq("priority")
      expect(game.state.players[0].hand).to eq([spark])
      expect(game.state.players[0].mana_pool[:C]).to eq(2)
    end

    it "isn't offered on an opponent's turn" do
      game = build_game(catalog) do
        turn 3, active: "bob", step: :precombat_main
        player("alice", mana_pool: { C: 1, R: 1 }) { hand "Portent Spark" }
        player("bob") { library "Forest", count: 5 }
        priority "alice"
      end
      expect(option_types(game)).to include("cast")
      expect(option_types(game)).not_to include("special_action")
    end

    it "a foretold spell knows it was cast with foretell" do
      game = board(hand: ["Portent Spark"], mana: { C: 2, R: 1 })
      game.submit(type: "special_action", object: hand_card(game, "Portent Spark"), ability: "printed:1")
      2.times { game.submit(type: "pay_mana", mana: "C") }
      exiled = game.state.exile.first
      game.state.object(exiled).memory["foretold"] = 2 # foretold on an earlier turn
      game = Enjine::Game.import(game.export, catalog: catalog) # round-trips
      game.submit(type: "cast", object: exiled, via: "alt:printed:1")
      game.submit(type: "target", target: "player:bob")
      game.submit(type: "pay_mana", mana: "R")
      resolve_all(game)
      expect(game.state.players[1].life).to eq(17)
    end
  end

  describe "hideaway (CR 702.75a) and playing a land while resolving (CR 305.2a, 305.3)" do
    def hide(game)
      game.submit(type: "play_land", object: hand_card(game, "Spec Hidden Vault"))
      resolve_all(game)
      game.submit(game.legal_options.find { it[:type] == "take" })
      { type: "activate", object: obj_id(game, "Spec Hidden Vault"), ability: "printed:2" }
    end

    it "plays the exiled land only with a land play left, and it counts as one" do
      game = board(hand: ["Spec Hidden Vault"])
      activate = hide(game)
      expect(game.state.players[0].library.size).to eq(4) # three looked at: one exiled, two to the bottom
      game.submit(activate)
      resolve_all(game)
      expect(game.state.exile.size).to eq(1) # the land play is used up: nothing to play
    end

    it "plays the land on a later turn and turns it face up" do
      game = board(hand: ["Spec Hidden Vault"])
      activate = hide(game)
      game.state.players[0].lands_played = 0
      game.submit(activate)
      resolve_all(game)
      expect(game.legal_options.map { it[:type] }).to eq(%w[play_land done])
      game.submit(type: "play_land", object: game.state.exile.first)
      expect(game.state.exile).to be_empty
      expect(game.state.players[0].lands_played).to eq(1)
      expect(game.state.battlefield.map { game.state.object(it).card }).to include("forest")
    end

    it "validates dig's face_down and link" do
      bad = { "name" => "Spec Bad Dig", "mana_cost" => "{1}", "types" => ["sorcery"],
              "abilities" => [{ "spell" => { "effects" => [{ "dig" => { "amount" => 2, "face_down" => true } }] } }] }
      expect { Enjine::CardDefinition.from_h(bad) }
        .to raise_error(Enjine::InvalidCardDefinition, /abilities\[0\]\.spell\.effects\[0\]\.dig: face_down and link need put: "exile"/)
      bad2 = { "name" => "Spec Bad Hideaway", "types" => ["land"], "abilities" => [{ "hideaway" => {} }] }
      expect { Enjine::CardDefinition.from_h(bad2) }
        .to raise_error(Enjine::InvalidCardDefinition, /abilities\[0\]\.hideaway\.amount: required/)
    end
  end
end
