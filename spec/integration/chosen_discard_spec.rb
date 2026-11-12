# frozen_string_literal: true

# "Target opponent reveals their hand. You choose a nonland card from it. That player discards that card."
# choose_cards from a hand with `put: discard`: the owner discards the chosen card (CR 701.9a), so discard
# triggers see it; it isn't merely put into the graveyard.
RSpec.describe "Discarding a card another player chooses (CR 701.9a)" do
  let(:pry) do
    { "name" => "Spec Prying Gaze", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => ["opponent"], "effects" => [
        { "choose_cards" => { "from" => { "hand" => { "target" => 0 } }, "for" => { "not_types" => ["land"] },
                              "reveal" => "all", "put" => "discard" } }
      ] } }] }
  end
  let(:rummager) do
    { "name" => "Spec Hand Rummager", "mana_cost" => "{1}{B}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "discards" => { "controller" => "opponent" } },
                                         "effects" => [{ "gain_life" => { "amount" => 3 } }] } }] }
  end
  let(:catalog) { catalog_with(pry, rummager) }

  def board(bob_hand:)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: { B: 1 }) do
        battlefield "Spec Hand Rummager"
        hand "Spec Prying Gaze"
        library "Forest", count: 3
      end
      player("bob") do
        hand(*bob_hand)
        library "Forest", count: 3
      end
    end
  end

  def card(game, id) = game.state.object(id).card

  # Casts the spell; alice answers her choice with `pick` (a card name), bob passes.
  def cast(game, pick: nil)
    events = []
    game.subscribe { events << it }
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    offered = nil
    until (decision = game.pending_decision).kind == "priority" && game.state.stack.empty?
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { it[:type] == "pay_mana" })
      when "effect_choice"
        offered ||= game.legal_options.filter_map { it[:object] && card(game, it[:object]) }
        game.submit(game.legal_options.find { it[:object] && card(game, it[:object]) == pick } || game.legal_options.first)
      else game.submit(game.legal_options.first)
      end
    end
    [events, offered]
  end

  it "reveals the hand, lets the caster choose a nonland card, and that player discards it" do
    game = board(bob_hand: ["Forest", "Grizzly Bears", "Hill Giant"])
    events, offered = cast(game, pick: "hill_giant")
    expect(offered).to contain_exactly("grizzly_bears", "hill_giant")
    bob = game.state.players[1]
    expect(bob.graveyard.map { card(game, it) }).to eq(["hill_giant"])
    expect(bob.hand.map { card(game, it) }).to contain_exactly("forest", "grizzly_bears")
    expect(events.count { it.type.to_s == "card_revealed" }).to eq(3)
    expect(game.state.players[0].life).to eq(23) # the discard trigger saw it
  end

  it "discards nothing when no card matches" do
    game = board(bob_hand: ["Forest"])
    cast(game)
    expect(game.state.players[1].hand.size).to eq(1)
    expect(game.state.players[0].life).to eq(20)
  end

  it "takes cards only from a hand" do
    bad = pry.merge("name" => "Spec Bad Gaze", "abilities" => [{ "spell" => { "effects" => [
                      { "choose_cards" => { "from" => { "graveyard" => "you" }, "for" => "card", "put" => "discard" } }
                    ] } }])
    expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition, /put: discard takes cards from a hand/)
  end
end
