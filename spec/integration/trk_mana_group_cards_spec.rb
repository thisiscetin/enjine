# frozen_string_literal: true

require "enjine/sets"

# Converted Star Trek cards from data/translations/trk.json that reuse existing primitives (plus `exile`
# moving a spell off the stack and computed filter ranges), played from lib/enjine/sets/trk.json.
RSpec.describe "Star Trek cards: translations of the mana group" do
  let(:catalog) { catalog_with(*Enjine::Sets.load("trk").cards) }

  def slug(card) = Enjine::CardDefinition.slug(card)
  def life(game, index) = game.state.players[index].life
  def hand_id(game, player, card) = ids_in(game, player, :hand).find { game.state.object(it).card == slug(card) }
  def on_field(game, card) = game.state.battlefield.select { game.state.object(it).card == slug(card) }

  def pay_all(game)
    while game.pending_decision.kind == "pay_cost"
      options = game.legal_options
      sources = options.select { it[:type] == "activate_mana" }
      game.submit(options.find { it[:type] == "pay_mana" } ||
                  sources.find { !game.state.object(it[:object]).card.start_with?("treasure") } || sources.first)
    end
  end

  def cast(game, card, player: "alice", targets: [], x: nil)
    game.submit(type: "cast", object: hand_id(game, player, card))
    game.submit(type: "x", value: x) if x
    targets.each { game.submit(type: "target", target: it) }
    pay_all(game)
  end

  # Passes priority (answering other decisions with their first option) until the stack is empty.
  def settle(game, limit: 40)
    limit.times do
      break if game.pending_decision.kind == "priority" && game.state.stack.empty?

      game.pending_decision.kind == "priority" ? game.submit(type: "pass") : game.submit(game.legal_options.first)
    end
  end

  def board(alice: {}, bob: {})
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      { "alice" => alice, "bob" => bob }.each do |name, spec|
        player(name, life: spec.fetch(:life, 20)) do
          hand(*spec[:hand]) if spec[:hand]
          Array(spec[:field]).each { |entry| entry.is_a?(Array) ? battlefield(entry[0], **entry[1]) : battlefield(entry) }
          library "Island", count: 8
        end
      end
    end
  end

  def attack_with(game, *ids)
    game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
    ids.each { game.submit(type: "attack", object: it, target: "player:bob") }
    game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
  end

  def treasures(game) = game.state.battlefield.count { game.catalog.fetch(game.state.object(it).card).name == "Treasure" }

  it "Khaaaaaaaaaaaannn!: twice X damage, and the creature is exiled instead of dying (CR 107.3, 614.1a)" do
    game = board(alice: { hand: ["Khaaaaaaaaaaaannn!"], field: %w[Mountain Mountain Mountain] },
                 bob: { field: ["Pillarfield Ox"] })
    ox = on_field(game, "Pillarfield Ox").first
    cast(game, "Khaaaaaaaaaaaannn!", x: 2, targets: [ox])
    settle(game)
    expect(game.state.exile.map { game.state.object(it).card }).to eq(["pillarfield_ox"])
    expect(game.state.players[1].graveyard).to be_empty
  end

  it "Live Long and Prosper: doubles life, draws the hand size, no maximum hand size until your next turn" do
    game = board(alice: { hand: ["Live Long and Prosper", "Forest", "Forest"], life: 13,
                          field: %w[Plains Island Island Island Island Island Island] })
    cast(game, "Live Long and Prosper")
    settle(game)
    expect(life(game, 0)).to eq(26)
    expect(ids_in(game, "alice", :hand).size).to eq(4) # two cards in hand, then two drawn
    rule = game.state.effects.find { it["kind"] == "player_rule" }
    expect(rule).to include("rule" => "no_max_hand_size")
  end

  it "Live Long and Prosper can't be countered (CR 101.2)" do
    game = board(alice: { hand: ["Live Long and Prosper"], field: %w[Plains Island Island Island Island Island Island] },
                 bob: { hand: ["Counterspell"], field: %w[Island Island] })
    cast(game, "Live Long and Prosper")
    game.submit(type: "pass")
    cast(game, "Counterspell", player: "bob", targets: [game.state.stack.first])
    settle(game)
    expect(life(game, 0)).to eq(40)
  end

  describe "Brazen Bluff (CR 701.13a, 608.2e, 608.2g)" do
    def bluff_board
      board(alice: { field: %w[Island Island Island], hand: ["Divination"] },
            bob: { hand: ["Brazen Bluff", "Divination"], field: %w[Mountain Mountain] })
    end

    def respond_with_bluff(game)
      cast(game, "Divination")
      game.submit(type: "pass")
      spell = game.state.stack.first
      cast(game, "Brazen Bluff", player: "bob", targets: [spell])
      game.submit(type: "pass")
      game.submit(type: "pass")
      spell
    end

    it "the spell's controller may exile their own spell" do
      game = bluff_board
      respond_with_bluff(game)
      expect(game.pending_decision.player).to eq("alice")
      game.submit(type: "yes")
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["divination"])
      expect(game.state.stack).to be_empty
    end

    it "if they don't, the Bluff's controller may cast a noncreature spell from their hand for free" do
      game = bluff_board
      respond_with_bluff(game)
      game.submit(type: "no")
      expect(game.pending_decision.player).to eq("bob")
      game.submit(type: "cast", object: hand_id(game, "bob", "Divination"))
      settle(game)
      expect(ids_in(game, "bob", :hand).size).to eq(2) # Bob's free Divination
      expect(ids_in(game, "alice", :hand).size).to eq(2) # Alice's Divination resolved too
    end
  end

  it "Common Goal: one or two of your creatures each deal damage equal to their power (CR 120.3)" do
    game = board(alice: { hand: ["Common Goal"], field: ["Forest", "Forest", "Grizzly Bears", "Hill Giant"] },
                 bob: { field: ["Sandsea Behemoth"] })
    bears = on_field(game, "Grizzly Bears").first
    giant = on_field(game, "Hill Giant").first
    behemoth = on_field(game, "Sandsea Behemoth").first
    cast(game, "Common Goal", targets: [bears, giant, behemoth])
    settle(game)
    expect(game.state.battlefield).not_to include(behemoth) # 2 + 3 damage: lethal (CR 704.5g)

    game = board(alice: { hand: ["Common Goal"], field: ["Forest", "Forest", "Grizzly Bears"] },
                 bob: { field: ["Sandsea Behemoth"] })
    game.submit(type: "cast", object: hand_id(game, "alice", "Common Goal"))
    game.submit(type: "target", target: on_field(game, "Grizzly Bears").first)
    game.submit(type: "done") # the second creature is optional
    game.submit(type: "target", target: on_field(game, "Sandsea Behemoth").first)
    pay_all(game)
    settle(game)
    expect(game.state.object(on_field(game, "Sandsea Behemoth").first).damage).to eq(2)
  end

  it "Antagonist Incorporator: an artifact creature's combat damage may pay {1} for a Borg token (CR 118.12)" do
    game = board(alice: { field: [["Antagonist Incorporator", { controlled_since: 0 }], "Plains"] })
    attack_with(game, on_field(game, "Antagonist Incorporator").first)
    game.submit(type: "pass") until game.pending_decision.kind == "effect_choice" || game.state.step == :end
    expect(game.legal_options).to include({ type: "pay" })
    game.submit(type: "pay")
    pay_all(game)
    settle(game)
    token = game.state.battlefield.map { game.state.object(it) }.find { it.card.start_with?("token") || it.card.include?("borg") }
    expect(token).not_to be_nil
    expect(life(game, 1)).to eq(18)
  end

  it "Hive Mind Coprocessor: may pay 1 life to draw a card when it deals combat damage to a player (CR 119.4)" do
    game = board(alice: { field: [["Hive Mind Coprocessor", { controlled_since: 0 }]] })
    attack_with(game, on_field(game, "Hive Mind Coprocessor").first)
    game.submit(type: "pass") until game.pending_decision.kind == "effect_choice"
    game.submit(type: "pay")
    settle(game)
    expect(life(game, 0)).to eq(19)
    expect(ids_in(game, "alice", :hand).size).to eq(1)
    expect(life(game, 1)).to eq(16)
  end

  it "Grand Nagus Zek: +1/+1 per Treasure; another creature dying makes one Treasure, once each turn" do
    game = board(alice: { hand: ["Lightning Bolt", "Lightning Bolt"], field: ["Grand Nagus Zek", "Mountain", "Mountain"] },
                 bob: { field: ["Grizzly Bears", "Savannah Lions"] })
    zek = on_field(game, "Grand Nagus Zek").first
    cast(game, "Lightning Bolt", targets: [on_field(game, "Grizzly Bears").first])
    settle(game)
    expect(treasures(game)).to eq(1)
    expect(view_of(game, zek).values_at("power", "toughness")).to eq([2, 2])
    cast(game, "Lightning Bolt", targets: [on_field(game, "Savannah Lions").first])
    settle(game)
    expect(treasures(game)).to eq(1)
  end

  it "Brad Boimler: becoming tapped makes counters put on your permanents one more this turn (CR 614.1a)" do
    game = board(alice: { field: [["Brad Boimler, Eager Ensign", { controlled_since: 0 }], "Grizzly Bears"] })
    attack_with(game, on_field(game, "Brad Boimler, Eager Ensign").first)
    settle(game)
    expect(game.state.effects.map { it["kind"] }).to include("counter_bonus")
  end

  it "Beckett Mariner: the third promotion counter is removed and deals 2 damage to each opponent" do
    game = board(alice: { field: [["Beckett Mariner, Impetuous Ensign", { controlled_since: 0, counters: { "promotion" => 2 } }]] })
    mariner = on_field(game, "Beckett Mariner, Impetuous Ensign").first
    attack_with(game, mariner)
    settle(game)
    expect(game.state.object(mariner).counters.fetch("promotion", 0)).to eq(0)
    expect(life(game, 1)).to eq(18)
  end

  it "Beckett Mariner: below three promotion counters nothing else happens" do
    game = board(alice: { field: [["Beckett Mariner, Impetuous Ensign", { controlled_since: 0 }]] })
    mariner = on_field(game, "Beckett Mariner, Impetuous Ensign").first
    attack_with(game, mariner)
    settle(game)
    expect(game.state.object(mariner).counters["promotion"]).to eq(1)
    expect(life(game, 1)).to eq(20)
  end

  it "Jett Reno: surveils when small, draws instead with power 4 or greater" do
    game = board(alice: { field: [["Jett Reno, Problem Solver", { controlled_since: 0 }]] })
    attack_with(game, on_field(game, "Jett Reno, Problem Solver").first)
    game.submit(type: "pass") until game.pending_decision.kind == "effect_choice"
    expect(game.pending_decision.details["prompt"]).to match(/surveil/i)

    game = board(alice: { field: [["Jett Reno, Problem Solver", { controlled_since: 0, counters: { "+1/+1" => 3 } }]] })
    attack_with(game, on_field(game, "Jett Reno, Problem Solver").first)
    settle(game)
    expect(ids_in(game, "alice", :hand).size).to eq(1)
  end

  describe "Engineered Explosives (CR 702.44a, 202.3, 608.2h)" do
    it "destroys each nonland permanent whose mana value equals its charge counters" do
      game = board(alice: { field: [["Engineered Explosives", { counters: { "charge" => 2 } }], "Plains", "Plains",
                                    "Grizzly Bears"] },
                   bob: { field: ["Hill Giant", "Coral Merfolk", "Island"] })
      explosives = on_field(game, "Engineered Explosives").first
      game.submit(type: "activate", object: explosives, ability: "printed:0")
      pay_all(game)
      settle(game)
      cards = game.state.battlefield.map { game.state.object(it).card }
      expect(cards).to include("hill_giant", "plains", "island")
      expect(cards).not_to include("grizzly_bears", "coral_merfolk", "engineered_explosives")
    end

    it "with no counters it destroys tokens and other mana value 0 permanents" do
      game = board(alice: { field: ["Engineered Explosives", "Plains", "Plains", "Grand Nagus Zek"] })
      explosives = on_field(game, "Engineered Explosives").first
      engine = Enjine::Engine.new(game.catalog, game.state) { nil }
      zek = game.catalog.fetch("grand_nagus_zek")
      engine.create_token!(zek.token_definitions.first, 0)
      expect(treasures(game)).to eq(1)
      game.submit(type: "activate", object: explosives, ability: "printed:0")
      pay_all(game) while game.pending_decision.kind == "pay_cost"
      settle(game)
      expect(treasures(game)).to eq(0)
      expect(on_field(game, "Grand Nagus Zek")).not_to be_empty
    end

    it "enters with a charge counter per color spent on X (sunburst)" do
      game = board(alice: { hand: ["Engineered Explosives"], field: %w[Plains Island] })
      cast(game, "Engineered Explosives", x: 2)
      settle(game)
      expect(game.state.object(on_field(game, "Engineered Explosives").first).counters).to eq("charge" => 2)
    end
  end
end
