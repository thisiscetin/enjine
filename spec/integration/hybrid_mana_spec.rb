# frozen_string_literal: true

# CR 107.4e: a hybrid symbol such as {R/G} is paid with either color; CR 601.2h: the player pays the
# total cost. CR 202.2d: the card is both colors.
RSpec.describe "Hybrid mana costs (CR 107.4e, 601.2f-h)" do
  let(:brute) do
    { "name" => "Spec Hybrid Brute", "mana_cost" => "{1}{R/G}{R/G}", "types" => ["creature"], "power" => 3, "toughness" => 3 }
  end
  let(:mixed) do
    { "name" => "Spec Mixed Charm", "mana_cost" => "{R/G}{G}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
  end
  let(:catalog) { catalog_with(brute, mixed) }

  def board(lands, hand: ["Spec Hybrid Brute"], pool: {})
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: pool) do
        hand(*hand)
        battlefield(*lands)
        library "Forest", count: 3
      end
      player("bob") { library "Forest", count: 3 }
    end
  end

  def pay_all(game)
    game.state.battlefield.reject { game.state.object(it).tapped }.each do |land|
      ref = mana_ref(game, land)
      game.submit(type: "activate_mana", object: land, ability: ref)
      type = game.legal_options.find { it[:type] == "pay_mana" }
      game.submit(type) if type
    end
  end

  it "casts with red, green or a mix paying the hybrid symbols" do
    [%w[Mountain Mountain Mountain], %w[Forest Forest Island], %w[Mountain Forest Island]].each do |lands|
      game = board(lands)
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      expect(game.pending_decision.details["remaining"]).to eq("{1}{R/G}{R/G}")
      pay_all(game)
      expect(game.state.stack.size).to eq(1), "with #{lands.join(", ")}"
    end
  end

  it "isn't castable when neither color can pay a hybrid symbol" do
    game = board(%w[Mountain Island Island])
    expect(option_types(game)).not_to include("cast")
    expect(board(%w[Mountain Forest Plains]).legal_options).to include(a_hash_including(type: "cast"))
  end

  it "spends a mana where it keeps the rest payable: green pays the hybrid only if red can't pay later" do
    game = board(%w[Forest Forest], hand: ["Spec Mixed Charm"])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    forest = game.state.battlefield.first
    game.submit(type: "activate_mana", object: forest, ability: mana_ref(game, forest))
    game.submit(type: "pay_mana", mana: "G")
    expect(game.pending_decision.details["remaining"]).to eq("{R/G}") # {G} first: exact color
    pay_all(game)
    expect(game.state.stack.size).to eq(1)

    with_red = board(%w[Forest], hand: ["Spec Mixed Charm"], pool: { G: 1, R: 0 })
    with_red.submit(type: "cast", object: ids_in(with_red, "alice", :hand).first)
    with_red.submit(type: "pay_mana", mana: "G")
    expect(with_red.pending_decision.details["remaining"]).to eq("{R/G}")
  end

  it "pays a hybrid symbol before generic so a later colored mana isn't stranded" do
    game = board(%w[Mountain Mountain Forest])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    mountain = game.state.battlefield.first
    game.submit(type: "activate_mana", object: mountain, ability: mana_ref(game, mountain))
    game.submit(type: "pay_mana", mana: "R")
    expect(game.pending_decision.details["remaining"]).to eq("{1}{R/G}")
  end

  it "a mana of neither hybrid color pays generic" do
    game = board(%w[Island Mountain Mountain])
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    island = obj_id(game, "Island")
    game.submit(type: "activate_mana", object: island, ability: mana_ref(game, island))
    game.submit(type: "pay_mana", mana: "U")
    expect(game.pending_decision.details["remaining"]).to eq("{R/G}{R/G}")
  end

  it "makes the card both colors for deck building" do
    expect(Enjine::DeckBuilder.colors_of(Enjine::CardDefinition.from_h(brute))).to eq(%i[R G])
  end
end
