# frozen_string_literal: true

# "As this enters" choices for permanents an effect puts onto the battlefield (CR 614.12, 614.12a, 614.12b):
# the controller-to-be chooses for each permanent in turn, as an enter_choice decision with `effect: true`,
# and then they all enter at once.
RSpec.describe "'As this enters' choices for permanents put onto the battlefield by effects (CR 614.12a)" do
  let(:sentinel) do
    { "name" => "Numbered Sentinel", "mana_cost" => "{2}", "types" => %w[artifact creature], "power" => 2, "toughness" => 2,
      "abilities" => [{ "choose_number" => { "min" => 0, "max" => 3 } }] }
  end
  let(:idol) do
    { "name" => "Naming Idol", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "choose_card_name" => { "not" => ["land"] } }] }
  end
  let(:golem) do
    { "name" => "Toll Golem", "mana_cost" => "{1}", "types" => %w[artifact creature], "power" => 1, "toughness" => 1,
      "abilities" => [{ "enters_tapped_unless_pay_life" => { "life" => 3 } }] }
  end
  let(:recall) do
    { "name" => "Recall Rite", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => [{ "graveyard_card" => { "controller" => "you", "any_of" => ["artifact"] } }],
                                     "effects" => [{ "return_to_battlefield" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:archive) do
    { "name" => "Archive Unsealing", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "exile_top" => { "amount" => 4 } },
                                                   { "return_to_battlefield" => { "to" => { "result" => 0 }, "under" => "you" } },
                                                   { "gain_life" => { "amount" => 1 } }] } }] }
  end
  let(:mint) do
    { "name" => "Cipher Mint", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "create_token" => { "amount" => 2, "token" => {
        "name" => "Cipher", "types" => ["artifact"], "abilities" => [{ "choose_number" => { "max" => 2 } }]
      } } }] } }] }
  end
  let(:seek) do
    { "name" => "Seek the Relic", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "search_library" => { "for" => { "types" => ["artifact"] },
                                                                           "put" => "battlefield" } }] } }] }
  end
  let(:pick) do
    { "name" => "Pick a Relic", "mana_cost" => "{B}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "choose_cards" => {
        "from" => { "hand" => "you" }, "for" => { "types" => ["artifact"] }, "put" => "battlefield"
      } }] } }] }
  end
  let(:catalog) { catalog_with(sentinel, idol, golem, recall, archive, mint, seek, pick) }

  def game_with(spell, life: 20, graveyard: [], library: [], hand: [])
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", life: life) do
        hand spell
        hand(*hand) unless hand.empty?
        battlefield "Swamp"
        graveyard(*graveyard) unless graveyard.empty?
        library(*library) unless library.empty?
      end
      player("bob") { library "Forest", count: 2 }
    end
  end

  def cast(game, spell, targets: nil)
    id = ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(spell) }
    game.submit(type: "cast", object: id)
    game.submit(type: "target", target: targets) if targets
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
    pass_both(game)
  end

  def memory(game, card) = game.state.object(obj_id(game, card)).memory

  it "asks for the choice of a card returned from a graveyard, before it enters (survives a snapshot)" do
    game = game_with("Recall Rite", graveyard: ["Numbered Sentinel"])
    cast(game, "Recall Rite", targets: ids_in(game, "alice", :graveyard).first)
    expect(game.pending_decision).to have_attributes(kind: "enter_choice", player: "alice",
                                                     details: a_hash_including("effect" => true))
    expect(game.state.battlefield.map { game.state.object(it).card }).not_to include("numbered_sentinel")
    expect(game.legal_options).to eq((0..3).map { { type: "number", number: it } })

    copy = Enjine::Game.import(game.export, catalog: catalog)
    expect(copy.pending_decision).to eq(game.pending_decision)
    copy.submit(type: "number", number: 2)
    expect(memory(copy, "Numbered Sentinel")).to include("chosen_number" => 2)
    expect(copy.pending_decision.kind).to eq("priority")
  end

  it "asks for each card in turn, then they enter at the same time (CR 614.12a)" do
    game = game_with("Archive Unsealing", library: ["Numbered Sentinel", "Naming Idol", "Lightning Bolt", "Swamp"])
    cast(game, "Archive Unsealing")
    expect(game.state.object(game.pending_decision.details["object"])).to have_attributes(card: "numbered_sentinel", zone: :exile)
    game.submit(type: "number", number: 1)
    expect(game.state.battlefield.map { game.state.object(it).card }).not_to include("numbered_sentinel")
    expect(game.pending_decision).to have_attributes(kind: "enter_choice")
    expect(game.legal_options).to include({ type: "name", name: "Numbered Sentinel" })
    game.submit(type: "name", name: "Numbered Sentinel")
    expect(memory(game, "Numbered Sentinel")).to include("chosen_number" => 1)
    expect(memory(game, "Naming Idol")).to include("chosen_name" => "Numbered Sentinel")
    expect(obj_id(game, "Swamp", zone: :battlefield)).to be_a(String)
    expect(game.state.exile.map { game.state.object(it).card }).to eq(["lightning_bolt"])
    expect(game.state.players[0].life).to eq(21) # the rest of the effect list ran after the choices
  end

  it "doesn't offer life payments that together are more than the player has (CR 614.12b)" do
    game = game_with("Archive Unsealing", life: 5, library: ["Toll Golem", "Toll Golem", "Swamp", "Swamp"])
    cast(game, "Archive Unsealing")
    expect(game.legal_options).to eq([{ type: "pay_life", life: 3 }, { type: "enter_tapped" }])
    game.submit(type: "pay_life", life: 3)
    expect(game.legal_options).to eq([{ type: "enter_tapped" }])
    game.submit(type: "enter_tapped")
    golems = game.state.battlefield.select { game.state.object(it).card == "toll_golem" }
    expect(golems.map { game.state.object(it).tapped }).to contain_exactly(false, true)
    expect(game.state.players[0].life).to eq(3)
  end

  it "asks for each token before any is created" do
    game = game_with("Cipher Mint")
    cast(game, "Cipher Mint")
    expect(game.pending_decision.details).to include("effect" => true, "card" => a_string_starting_with("cipher_token"))
    game.submit(type: "number", number: 0)
    expect(game.state.battlefield.count { game.catalog.fetch(game.state.object(it).card).token? }).to eq(0)
    game.submit(type: "number", number: 2)
    tokens = game.state.battlefield.select { game.catalog.fetch(game.state.object(it).card).token? }
    expect(tokens.map { game.state.object(it).memory["chosen_number"] }).to contain_exactly(0, 2)
  end

  it "asks for a card found by a search or chosen from a hand" do
    game = game_with("Seek the Relic", library: ["Swamp", "Naming Idol"])
    cast(game, "Seek the Relic")
    game.submit(game.legal_options.find { it[:object] }) while game.pending_decision.kind == "effect_choice"
    expect(game.pending_decision.kind).to eq("enter_choice")
    game.submit(type: "name", name: "Seek the Relic")
    expect(memory(game, "Naming Idol")).to include("chosen_name" => "Seek the Relic")

    game = game_with("Pick a Relic", hand: ["Numbered Sentinel"])
    cast(game, "Pick a Relic")
    game.submit(game.legal_options.find { it[:object] }) while game.pending_decision.kind == "effect_choice"
    game.submit(type: "number", number: 3)
    expect(memory(game, "Numbered Sentinel")).to include("chosen_number" => 3)
  end
end
