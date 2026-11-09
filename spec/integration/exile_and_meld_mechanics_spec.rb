# frozen_string_literal: true

# Invented cards for hideaway (CR 702.75a), paradigm (CR 702.192a), foretell (CR 702.143), suspend (CR 702.62),
# devour (CR 702.82) and meld (CR 701.42, 713): the edges the real-card scenarios don't reach.
RSpec.describe "Exile, suspend and meld mechanics" do
  let(:cards) do
    [
      { "name" => "Spec Hidden Vault", "types" => ["land"],
        "abilities" => [{ "hideaway" => { "amount" => 3 } }, { "mana" => { "cost" => ["tap"], "produce" => "{C}" } },
                        { "activated" => { "cost" => ["tap"], "effects" => [{ "cast_free" => { "to" => "exiled_with", "play" => true } }] } }] }
    ]
  end
  let(:catalog) { catalog_with(*cards) }

  def board(hand: [], field: [], library: ["Forest"], lands_played: 0, active: "alice")
    build_game(catalog) do
      turn 3, active: active, step: :precombat_main
      player("alice", lands_played: lands_played) do
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
      expect { Enjine::CardDefinition.from_h(bad2) }.to raise_error(Enjine::InvalidCardDefinition, /abilities\[0\]\.hideaway\.amount: required/)
    end
  end
end
