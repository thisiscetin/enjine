# frozen_string_literal: true

RSpec.describe "Library, hand and graveyard effects, edicts and linked exile (CR 701.20, 401.4, 701.21, 607, 610.3)" do
  def spell(name, effects, targets = [], types: ["sorcery"])
    { "name" => name, "mana_cost" => "{0}", "types" => types,
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? } }] }
  end

  def creature(name, power: 2, triggered: nil, abilities: [])
    abilities += [{ "triggered" => triggered }] if triggered
    { "name" => name, "mana_cost" => "{0}", "types" => ["creature"], "power" => power, "toughness" => 2,
      "abilities" => abilities }
  end

  let(:land) { { "types" => ["land"] } }
  let(:catalog) do
    catalog_with(
      spell("Relic Sounding", [{ "dig" => { "amount" => 3, "for" => { "types" => ["artifact"] }, "optional" => true,
                                            "reveal" => "chosen", "put" => "hand" } }]),
      spell("Ordered Sounding", [{ "dig" => { "amount" => 3, "rest" => "bottom_any" } }]),
      spell("Split Sounding", [{ "dig" => { "amount" => 2, "rest" => "graveyard" } }]),
      spell("Open Vault", [{ "dig" => { "amount" => 4, "reveal" => "all", "for" => { "permanent" => true }, "count" => "all",
                                        "put" => "battlefield", "tapped" => true } }]),
      spell("Ground Breaker", [{ "dig" => { "amount" => 3, "reveal" => "all", "for" => land, "put" => "battlefield",
                                            "rest" => "graveyard" } }]),
      spell("Fault Line", [{ "reveal_until" => { "for" => land, "count" => 2, "put" => "battlefield" } },
                           { "delayed_trigger" => { "when" => { "step_begins" => { "step" => "end" } },
                                                    "effects" => [{ "sacrifice" => { "to" => { "result" => 0 } } }] } }]),
      spell("Burst Cache", [{ "exile_top" => { "amount" => 3, "link" => true } },
                            { "return_to_battlefield" => { "to" => { "result" => 0 }, "under" => "you" } }]),
      creature("Path Seeker", triggered: { "when" => { "enters" => {} }, "effects" => [{ "explore" => { "to" => "self" } }] }),
      spell("Dredge Net", [{ "mill" => { "amount" => 3 } },
                           { "choose_cards" => { "from" => { "result" => 0 }, "for" => { "permanent" => true }, "optional" => true,
                                                 "put" => "hand" } }], types: ["instant"]),
      spell("Ground Recall", [{ "choose_cards" => { "from" => { "graveyard" => "you" }, "for" => land, "put" => "hand",
                                                    "otherwise" => [{ "gain_life" => { "amount" => 4 } }] } }]),
      spell("Thought Leech", [{ "choose_cards" => { "from" => { "hand" => { "target" => 0 } }, "look" => true,
                                                    "for" => { "not_types" => ["land"] }, "optional" => true, "put" => "exile",
                                                    "then" => [{ "draw" => { "amount" => 1, "to" => { "target" => 0 } } }] } }],
            ["opponent"]),
      spell("Open Mind", [{ "choose_cards" => { "from" => { "hand" => { "target" => 0 } }, "reveal" => "all",
                                                "for" => { "not_types" => ["land"] }, "put" => "graveyard" } },
                          { "look_at_hand" => { "to" => { "target" => 0 } } }], ["opponent"]),
      spell("Culling Order", [{ "sacrifice_choice" => { "filter" => "creature", "to" => { "each" => "player" } } }]),
      spell("Desperate Offer", [{ "may" => { "effects" => [{ "sacrifice_choice" => {
              "filter" => { "one_of" => [{ "creature" => { "other" => true } }, { "artifact" => { "other" => true } }] }
            } }], "then" => [{ "draw" => { "amount" => 1 } }] } }]),
      spell("Reseed", [{ "sacrifice_choice" => { "filter" => "land", "count" => "any" } },
                       { "search_library" => { "for" => land, "count" => { "count" => { "result" => 0 } }, "put" => "battlefield",
                                               "tapped" => true } }]),
      spell("Drift Away", [{ "put_in_library" => { "to" => { "target" => 0 }, "position" => "owner_choice" } }], ["creature"],
            types: ["instant"]),
      spell("Bury Deep", [{ "put_in_library" => { "to" => { "target" => 0 }, "position" => "bottom" } }],
            [{ "graveyard_card" => { "controller" => "you" } }]),
      spell("Ash Sweep", [{ "exile" => { "to" => { "target" => 0 } } }, { "gain_life" => { "amount" => 2 } }],
            ["graveyard_card"], types: ["instant"]),
      spell("Grave Call", [{ "return_to_hand" => { "to" => { "target" => 0 } } }],
            [{ "graveyard_card" => { "controller" => "you", "any_of" => ["creature"] } }]),
      spell("Recycle Rite", [{ "shuffle_into_library" => { "to" => { "target" => 0 } } }, { "shuffle_library" => {} }],
            ["graveyard_card"]),
      spell("Exile and Pray", [{ "exile" => { "to" => { "target" => 0 } } },
                               { "search_library" => { "searcher" => { "controller_of" => { "target" => 0 } }, "may" => true,
                                                       "for" => { "supertypes" => ["basic"], "types" => ["land"] },
                                                       "reveal" => true } }], ["creature"]),
      spell("Muster Call", [{ "search_library" => { "for" => { "types" => ["creature"] }, "put" => "battlefield",
                                                    "counters" => { "+1/+1" => 2 } } }]),
      spell("Withering Cry",
            [{ "pump" => { "power" => -1, "toughness" => -1, "to" => { "each" => { "creature" => { "other" => true } } } } }]),
      { "name" => "Keepsake Shrine", "mana_cost" => "{0}", "types" => ["enchantment"], "abilities" => [
        { "activated" => { "cost" => [{ "mana" => "{0}" }], "effects" => [
          { "choose_cards" => { "from" => { "hand" => "you" }, "put" => "exile", "link" => true } }
        ] } },
        { "activated" => { "cost" => [{ "mana" => "{0}" }], "effects" => [
          { "gain_life" => { "amount" => 10, "if" => { "share_card_type" => "exiled_with" } } }
        ] } },
        { "activated" => { "cost" => [{ "mana" => "{0}" }], "effects" => [
          { "choose_cards" => { "from" => "exiled_with", "put" => "hand" } }
        ] } }
      ] },
      { "name" => "Holding Cell", "mana_cost" => "{0}", "types" => ["artifact"], "abilities" => [
        { "triggered" => { "when" => { "enters" => {} },
                           "targets" => [{ "permanent" => { "controller" => "opponent", "not" => ["land"] } }],
                           "effects" => [{ "exile" => { "to" => { "target" => 0 }, "until_source_leaves" => true } }] } }
      ] },
      spell("Scrap It", [{ "destroy" => { "to" => { "target" => 0 } } }], ["artifact"], types: ["instant"])
    )
  end

  def game_with(hand: [], library: [], graveyard: [], board: [], bob_hand: [], bob_board: [], bob_library: ["Forest"] * 5,
                bob_graveyard: [], step: :precombat_main)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice") do
        hand(*hand)
        board.each { battlefield it }
        library(*library)
        graveyard(*graveyard)
      end
      player("bob") do
        hand(*bob_hand)
        bob_board.each { battlefield it }
        library(*bob_library)
        graveyard(*bob_graveyard)
      end
    end
  end

  def cast(game, card, *targets)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) })
    targets.each { game.submit(type: "target", target: it) }
    game.submit(type: "pay_done") if option_types(game).include?("pay_done")
  end

  def cast_and_resolve(game, card, *targets)
    cast(game, card, *targets)
    pass_both(game)
  end

  def cards(game, ids) = ids.map { game.state.object(it).card }
  def choices(game) = game.legal_options

  def choose(game, type, card = nil)
    option = game.legal_options.find { it[:type] == type && (card.nil? || game.state.object(it[:object]).card == Enjine::CardDefinition.slug(card)) }
    raise "no #{type} #{card} in #{game.legal_options}" unless option

    game.submit(option)
  end

  def events(game, klass) = game.history.flat_map(&:events).grep(klass)

  describe "dig: look at or reveal the top cards, take some, put the rest away (CR 701.20, 401.4)" do
    it "looks privately, reveals the artifact taken, and puts the rest on the bottom in a random order" do
      game = game_with(hand: ["Relic Sounding"], library: ["Lightning Bolt", "Arc Lantern", "Forest", "Island", "Plains"])
      cast_and_resolve(game, "Relic Sounding")
      expect(game.pending_decision.kind).to eq("effect_choice")
      expect(choices(game).map { it[:type] }).to eq(%w[take done])
      looked = events(game, Enjine::Events::LookedAt).last
      expect(looked.for_viewer("alice")["cards"]).to eq(%w[lightning_bolt arc_lantern forest])
      expect(looked.for_viewer("carol")).to eq({ "type" => "looked_at", "player" => "alice", "owner" => "alice", "count" => 3 })
      expect(game.view_for("bob")["pending"]).not_to have_key("choices")
      choose(game, "take", "Arc Lantern")
      expect(cards(game, ids_in(game, "alice", :hand))).to eq(["arc_lantern"])
      expect(events(game, Enjine::Events::CardRevealed).map(&:card)).to eq(["arc_lantern"])
      library = cards(game, ids_in(game, "alice", :library))
      expect(library.first(2)).to eq(%w[island plains])
      expect(library.last(2)).to contain_exactly("lightning_bolt", "forest")
    end

    it "may take nothing: done puts everything on the bottom (the seed decides the order)" do
      game = game_with(hand: ["Relic Sounding"], library: ["Arc Lantern", "Forest", "Island", "Plains"])
      cast_and_resolve(game, "Relic Sounding")
      choose(game, "done")
      expect(ids_in(game, "alice", :hand)).to be_empty
      expect(cards(game, ids_in(game, "alice", :library)).first).to eq("plains")
    end

    it "a card must be taken when nothing makes it optional; the rest go on the bottom in the chosen order" do
      game = game_with(hand: ["Ordered Sounding"], library: %w[Forest Island Plains Swamp Mountain])
      cast_and_resolve(game, "Ordered Sounding")
      expect(choices(game).map { it[:type] }).to eq(%w[take take take])
      choose(game, "take", "Island")
      expect(choices(game).map { it[:type] }).to eq(%w[bottom bottom])
      choose(game, "bottom", "Plains")
      expect(cards(game, ids_in(game, "alice", :library))).to eq(%w[swamp mountain plains forest])
      expect(cards(game, ids_in(game, "alice", :hand))).to eq(["island"])
    end

    it "puts the rest into the graveyard; only the card taken is the effect's result" do
      game = game_with(hand: ["Split Sounding"], library: %w[Forest Island Plains])
      cast_and_resolve(game, "Split Sounding")
      choose(game, "take", "Island")
      expect(cards(game, ids_in(game, "alice", :graveyard))).to contain_exactly("forest", "split_sounding")
      expect(cards(game, ids_in(game, "alice", :library))).to eq(["plains"])
    end

    it "reveals and puts every permanent card onto the battlefield tapped with count all" do
      game = game_with(hand: ["Open Vault"], library: ["Grizzly Bears", "Lightning Bolt", "Arc Lantern", "Forest", "Island"])
      cast_and_resolve(game, "Open Vault")
      entered = game.state.battlefield.map { game.state.object(it) }
      expect(entered.map(&:card)).to contain_exactly("grizzly_bears", "arc_lantern", "forest")
      expect(entered.map(&:tapped).uniq).to eq([true])
      expect(events(game, Enjine::Events::CardRevealed).size).to eq(4)
      expect(cards(game, ids_in(game, "alice", :library))).to eq(%w[island lightning_bolt])
    end

    it "a revealed land must be put onto the battlefield; the rest goes to the graveyard" do
      game = game_with(hand: ["Ground Breaker"], library: ["Lightning Bolt", "Forest", "Grizzly Bears", "Island"])
      cast_and_resolve(game, "Ground Breaker")
      expect(choices(game)).to eq([{ type: "take", object: ids_in(game, "alice", :library)[1] }])
      choose(game, "take")
      expect(cards(game, game.state.battlefield)).to eq(["forest"])
      expect(cards(game, ids_in(game, "alice", :graveyard))).to contain_exactly("lightning_bolt", "grizzly_bears", "ground_breaker")
    end
  end

  describe "reveal until (CR 701.20a, 401.4)" do
    it "reveals until two lands, puts them onto the battlefield, the rest on the bottom; sacrificed at the end step" do
      game = game_with(hand: ["Fault Line"], library: ["Lightning Bolt", "Forest", "Grizzly Bears", "Island", "Plains"])
      cast_and_resolve(game, "Fault Line")
      expect(cards(game, game.state.battlefield)).to contain_exactly("forest", "island")
      expect(cards(game, ids_in(game, "alice", :library)).first).to eq("plains")
      expect(cards(game, ids_in(game, "alice", :library)).last(2)).to contain_exactly("lightning_bolt", "grizzly_bears")
      expect(events(game, Enjine::Events::CardRevealed).map(&:card)).to eq(%w[lightning_bolt forest grizzly_bears island])
      skip_to(game, :end)
      pass_both(game)
      expect(game.state.battlefield).to be_empty
      expect(cards(game, ids_in(game, "alice", :graveyard))).to include("forest", "island")
    end

    it "stops when the library runs out" do
      game = game_with(hand: ["Fault Line"], library: ["Lightning Bolt", "Forest"])
      cast_and_resolve(game, "Fault Line")
      expect(cards(game, game.state.battlefield)).to eq(["forest"])
      expect(cards(game, ids_in(game, "alice", :library))).to eq(["lightning_bolt"])
    end
  end

  it "exiles the top cards with the source; permanent cards among them return under your control (CR 406.1, 400.7j)" do
    game = game_with(hand: ["Burst Cache"], library: ["Grizzly Bears", "Lightning Bolt", "Forest", "Island"])
    cast_and_resolve(game, "Burst Cache")
    expect(cards(game, game.state.battlefield)).to contain_exactly("grizzly_bears", "forest")
    expect(cards(game, game.state.exile)).to eq(["lightning_bolt"])
    expect(cards(game, ids_in(game, "alice", :library))).to eq(["island"])
  end

  describe "explore (CR 701.44a)" do
    it "a revealed land goes to the hand" do
      game = game_with(hand: ["Path Seeker"], library: %w[Forest Island])
      cast_and_resolve(game, "Path Seeker")
      pass_both(game)
      expect(cards(game, ids_in(game, "alice", :hand))).to eq(["forest"])
      expect(game.state.object(obj_id(game, "Path Seeker")).counters).to eq({})
    end

    it "otherwise a +1/+1 counter, and the card may go to the graveyard" do
      game = game_with(hand: ["Path Seeker"], library: ["Lightning Bolt", "Island"])
      cast_and_resolve(game, "Path Seeker")
      pass_both(game)
      expect(game.state.object(obj_id(game, "Path Seeker")).counters).to eq({ "+1/+1" => 1 })
      expect(choices(game).map { it[:type] }).to eq(%w[top graveyard])
      choose(game, "graveyard")
      expect(cards(game, ids_in(game, "alice", :graveyard))).to eq(["lightning_bolt"])
    end

    it "with an empty library it still gets the counter" do
      game = game_with(hand: ["Path Seeker"])
      cast_and_resolve(game, "Path Seeker")
      pass_both(game)
      expect(game.state.object(obj_id(game, "Path Seeker")).counters).to eq({ "+1/+1" => 1 })
      expect(game.pending_decision.kind).to eq("priority")
    end
  end

  describe "choosing cards (results, graveyard, hand)" do
    it "chooses a permanent card from among the milled cards (CR 400.7j)" do
      game = game_with(hand: ["Dredge Net"], library: ["Lightning Bolt", "Grizzly Bears", "Forest", "Island"],
                       graveyard: ["Hill Giant"])
      cast_and_resolve(game, "Dredge Net")
      expect(cards(game, choices(game).filter_map { it[:object] })).to eq(%w[grizzly_bears forest])
      choose(game, "choose", "Grizzly Bears")
      expect(cards(game, ids_in(game, "alice", :hand))).to eq(["grizzly_bears"])
    end

    it "returns a land card from your graveyard, or does the fallback when it can't" do
      game = game_with(hand: ["Ground Recall"], graveyard: ["Forest", "Lightning Bolt"])
      cast_and_resolve(game, "Ground Recall")
      expect(choices(game).map { it[:type] }).to eq(["choose"]) # not optional: no "done"
      choose(game, "choose", "Forest")
      expect(cards(game, ids_in(game, "alice", :hand))).to eq(["forest"])
      expect(game.state.players[0].life).to eq(20)
      empty = game_with(hand: ["Ground Recall"], graveyard: ["Lightning Bolt"])
      cast_and_resolve(empty, "Ground Recall")
      expect(empty.state.players[0].life).to eq(24)
    end

    it "looks at an opponent's hand, exiles a chosen nonland card, then that player draws (CR 701.20e)" do
      game = game_with(hand: ["Thought Leech"], bob_hand: ["Lightning Bolt", "Forest"])
      cast(game, "Thought Leech", "player:bob")
      pass_both(game)
      looked = events(game, Enjine::Events::LookedAt).last
      expect(looked.for_viewer("alice")["cards"]).to eq(%w[lightning_bolt forest])
      expect(cards(game, choices(game).filter_map { it[:object] })).to eq(["lightning_bolt"])
      choose(game, "choose")
      expect(cards(game, game.state.exile)).to eq(["lightning_bolt"])
      expect(cards(game, ids_in(game, "bob", :hand))).to eq(%w[forest forest])
    end

    it "choosing nothing skips the draw" do
      game = game_with(hand: ["Thought Leech"], bob_hand: ["Lightning Bolt"])
      cast(game, "Thought Leech", "player:bob")
      pass_both(game)
      choose(game, "done")
      expect(cards(game, ids_in(game, "bob", :hand))).to eq(["lightning_bolt"])
    end

    it "reveals the whole hand and the choice is mandatory (CR 701.20a)" do
      game = game_with(hand: ["Open Mind"], bob_hand: ["Lightning Bolt", "Hill Giant", "Forest"])
      cast(game, "Open Mind", "player:bob")
      pass_both(game)
      expect(events(game, Enjine::Events::CardRevealed).map(&:card)).to eq(%w[lightning_bolt hill_giant forest])
      expect(choices(game).map { it[:type] }).to eq(%w[choose choose])
      choose(game, "choose", "Hill Giant")
      expect(cards(game, ids_in(game, "bob", :graveyard))).to eq(["hill_giant"])
      expect(events(game, Enjine::Events::LookedAt).last.cards).to eq(%w[lightning_bolt forest])
    end
  end

  describe "sacrifice of the player's choice (CR 701.21a, 101.4)" do
    it "each player sacrifices a creature: choices in turn order, then all at once" do
      game = game_with(hand: ["Culling Order"], board: ["Grizzly Bears"], bob_board: ["Hill Giant", "Raging Goblin"])
      cast_and_resolve(game, "Culling Order")
      expect(game.pending_decision.player).to eq("bob") # alice had one creature: no choice
      expect(game.state.battlefield.size).to eq(3)
      choose(game, "sacrifice", "Raging Goblin")
      expect(cards(game, game.state.battlefield)).to eq(["hill_giant"])
      reasons = game.history.last.events.grep(Enjine::Events::ZoneChanged).map(&:reason) - ["resolve"]
      expect(reasons).to eq(%w[sacrifice sacrifice])
    end

    it "an optional sacrifice of another creature or artifact is offered only when possible (CR 118.3)" do
      game = game_with(hand: ["Desperate Offer"], library: ["Forest"], board: ["Arc Lantern"])
      cast_and_resolve(game, "Desperate Offer")
      expect(choices(game).map { it[:type] }).to eq(%w[yes no])
      choose(game, "yes")
      expect(game.state.battlefield).to be_empty
      expect(cards(game, ids_in(game, "alice", :hand))).to eq(["forest"])
      none = game_with(hand: ["Desperate Offer"])
      cast_and_resolve(none, "Desperate Offer")
      expect(choices(none).map { it[:type] }).to eq(["no"])
    end

    it "sacrifices any number of lands, then searches for up to that many" do
      game = game_with(hand: ["Reseed"], board: %w[Forest Island Plains], library: ["Swamp", "Mountain", "Grizzly Bears"])
      cast_and_resolve(game, "Reseed")
      expect(choices(game).map { it[:type] }).to eq(%w[sacrifice sacrifice sacrifice done])
      choose(game, "sacrifice", "Forest")
      choose(game, "sacrifice", "Island")
      choose(game, "done")
      expect(cards(game, ids_in(game, "alice", :graveyard))).to include("forest", "island")
      choose(game, "find", "Swamp")
      choose(game, "find", "Mountain")
      expect(cards(game, game.state.battlefield)).to contain_exactly("plains", "swamp", "mountain")
      expect(game.state.battlefield.count { game.state.object(it).tapped }).to eq(2)
    end

    it "\"other\" in an each-selector excludes the source" do
      game = game_with(hand: ["Withering Cry"], board: ["Grizzly Bears"], bob_board: ["Hill Giant"])
      cast_and_resolve(game, "Withering Cry")
      expect(game.state.effects.flat_map { it["affected"] }).to contain_exactly(obj_id(game, "Grizzly Bears"), obj_id(game, "Hill Giant"))
    end
  end

  describe "into libraries and from graveyards (CR 401.4, 404, 608.2b, 701.24c)" do
    it "the owner chooses the top or the bottom of their library" do
      game = game_with(hand: ["Drift Away"], bob_board: ["Hill Giant"], bob_library: %w[Forest Island])
      cast(game, "Drift Away", obj_id(game, "Hill Giant"))
      pass_both(game)
      expect(game.pending_decision.player).to eq("bob")
      choose(game, "bottom")
      expect(cards(game, ids_in(game, "bob", :library))).to eq(%w[forest island hill_giant])
      top = game_with(hand: ["Drift Away"], bob_board: ["Hill Giant"])
      cast(top, "Drift Away", obj_id(top, "Hill Giant"))
      pass_both(top)
      choose(top, "top")
      expect(cards(top, ids_in(top, "bob", :library)).first).to eq("hill_giant")
    end

    it "puts a target card from your graveyard on the bottom of your library" do
      game = game_with(hand: ["Bury Deep"], graveyard: ["Hill Giant"], library: ["Forest"])
      cast_and_resolve(game, "Bury Deep", ids_in(game, "alice", :graveyard).first)
      expect(cards(game, ids_in(game, "alice", :library))).to eq(%w[forest hill_giant])
    end

    it "exiles a target card from a graveyard; a target that left the graveyard makes the spell fizzle (CR 608.2b)" do
      game = game_with(hand: ["Ash Sweep"], bob_graveyard: ["Hill Giant"])
      cast_and_resolve(game, "Ash Sweep", ids_in(game, "bob", :graveyard).first)
      expect(cards(game, game.state.exile)).to eq(["hill_giant"])
      expect(game.state.players[0].life).to eq(22)
      gone = game_with(hand: ["Ash Sweep"], bob_graveyard: ["Hill Giant"])
      target = ids_in(gone, "bob", :graveyard).first
      cast(gone, "Ash Sweep", target)
      gone.instance_variable_get(:@engine).move!(target, :library, reason: "test")
      pass_both(gone)
      expect(gone.state.players[0].life).to eq(20)
      expect(events(gone, Enjine::Events::Fizzled).size).to eq(1)
    end

    it "returns a target creature card from your graveyard to your hand" do
      game = game_with(hand: ["Grave Call"], graveyard: ["Hill Giant", "Lightning Bolt"])
      expect(cards(game, game.state.players[0].graveyard)).to eq(%w[hill_giant lightning_bolt])
      cast(game, "Grave Call")
      expect(game.legal_options.filter_map { it[:target] }).to eq([ids_in(game, "alice", :graveyard).first])
      game.submit(game.legal_options.first)
      pass_both(game)
      expect(cards(game, ids_in(game, "alice", :hand))).to eq(["hill_giant"])
    end

    it "shuffles a graveyard card into its owner's library (and shuffles anyway)" do
      game = game_with(hand: ["Recycle Rite"], bob_graveyard: ["Hill Giant"])
      cast_and_resolve(game, "Recycle Rite", ids_in(game, "bob", :graveyard).first)
      expect(cards(game, ids_in(game, "bob", :library))).to include("hill_giant")
      expect(events(game, Enjine::Events::LibraryShuffled).map(&:player)).to eq(%w[bob alice])
    end
  end

  describe "search by another player and search with counters (CR 701.23, 608.2h)" do
    it "the exiled creature's last controller may search their library" do
      game = game_with(hand: ["Exile and Pray"], bob_board: ["Hill Giant"], bob_library: ["Lightning Bolt", "Forest"])
      cast(game, "Exile and Pray", obj_id(game, "Hill Giant"))
      pass_both(game)
      expect(game.pending_decision).to have_attributes(kind: "effect_choice", player: "bob")
      choose(game, "search")
      choose(game, "find", "Forest")
      expect(cards(game, ids_in(game, "bob", :hand))).to eq(["forest"])
      expect(events(game, Enjine::Events::CardRevealed).map(&:card)).to eq(["forest"])
    end

    it "declining doesn't search or shuffle; the result survives export/import while waiting" do
      game = game_with(hand: ["Exile and Pray"], bob_board: ["Hill Giant"])
      cast(game, "Exile and Pray", obj_id(game, "Hill Giant"))
      pass_both(game)
      copy = Enjine::Game.import(game.export, catalog: catalog)
      choose(copy, "decline")
      expect(events(copy, Enjine::Events::LibraryShuffled)).to be_empty
      expect(copy.pending_decision.kind).to eq("priority")
    end

    it "puts the found creature onto the battlefield with counters" do
      game = game_with(hand: ["Muster Call"], library: ["Hill Giant", "Forest"])
      cast_and_resolve(game, "Muster Call")
      choose(game, "find", "Hill Giant")
      expect(game.state.object(obj_id(game, "Hill Giant")).counters).to eq({ "+1/+1" => 2 })
    end
  end

  describe "linked abilities: cards exiled with a source (CR 607.2a, 406.6)" do
    def activate(game, index)
      shrine = obj_id(game, "Keepsake Shrine")
      game.submit(type: "activate", object: shrine, ability: "printed:#{index}")
      game.submit(type: "pay_done") if option_types(game).include?("pay_done")
      pass_both(game)
    end

    it "remembers what it exiled, checks whether those cards share a card type, and returns them" do
      game = game_with(board: ["Keepsake Shrine"], hand: ["Hill Giant", "Grizzly Bears", "Lightning Bolt"])
      activate(game, 1) # no cards exiled with it: nothing shares a type
      expect(game.state.players[0].life).to eq(20)
      activate(game, 0)
      choose(game, "choose", "Hill Giant")
      activate(game, 0)
      choose(game, "choose", "Grizzly Bears")
      shrine = game.state.object(obj_id(game, "Keepsake Shrine"))
      expect(cards(game, shrine.memory["exiled_with"])).to eq(%w[hill_giant grizzly_bears])
      copy = Enjine::Game.import(game.export, catalog: catalog)
      activate(copy, 1)
      expect(copy.state.players[0].life).to eq(30)
      activate(copy, 0)
      choose(copy, "choose", "Lightning Bolt")
      activate(copy, 1)
      expect(copy.state.players[0].life).to eq(30) # a creature and an instant share no card type
      activate(copy, 2)
      expect(cards(copy, choices(copy).map { it[:object] })).to eq(%w[hill_giant grizzly_bears lightning_bolt])
    end
  end

  describe "exile until the source leaves the battlefield (CR 610.3)" do
    it "returns the card when the source leaves" do
      game = game_with(hand: ["Holding Cell", "Scrap It"], bob_board: ["Hill Giant"])
      cast_and_resolve(game, "Holding Cell")
      game.submit(type: "target", target: obj_id(game, "Hill Giant"))
      pass_both(game)
      expect(cards(game, game.state.exile)).to eq(["hill_giant"])
      cast_and_resolve(game, "Scrap It", obj_id(game, "Holding Cell"))
      expect(game.state.exile).to be_empty
      expect(game.state.object(obj_id(game, "Hill Giant"))).to have_attributes(controller: 1, owner: 1)
    end

    it "exiles nothing if the source left before the ability resolved (CR 610.3b)" do
      game = game_with(hand: ["Holding Cell", "Scrap It"], bob_board: ["Hill Giant"])
      cast_and_resolve(game, "Holding Cell")
      game.submit(type: "target", target: obj_id(game, "Hill Giant"))
      cast(game, "Scrap It", obj_id(game, "Holding Cell"))
      pass_both(game, 2)
      expect(game.state.exile).to be_empty
      expect(cards(game, game.state.battlefield)).to eq(["hill_giant"])
    end

    it "a returned card that left exile in the meantime stays where it is" do
      game = game_with(hand: ["Holding Cell", "Scrap It"], bob_board: ["Hill Giant"])
      cast_and_resolve(game, "Holding Cell")
      game.submit(type: "target", target: obj_id(game, "Hill Giant"))
      pass_both(game)
      game.instance_variable_get(:@engine).move!(game.state.exile.first, :graveyard, reason: "test")
      cast_and_resolve(game, "Scrap It", obj_id(game, "Holding Cell"))
      expect(cards(game, ids_in(game, "bob", :graveyard))).to eq(["hill_giant"])
    end
  end

  describe "variants and edge cases" do
    # One "Probe Spell" with the given effects (and targets), cast and resolved by alice.
    def probe(effects, targets: [], target_ids: [], **board)
      @catalog = catalog_with(spell("Probe Spell", effects, targets))
      game = build_game(@catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand "Probe Spell", *board.fetch(:hand, [])
          board.fetch(:board, []).each { battlefield it }
          library(*board.fetch(:library, []))
          graveyard(*board.fetch(:graveyard, []))
        end
        player("bob") do
          board.fetch(:bob_board, []).each { battlefield it }
          library "Forest", count: 3
          graveyard(*board.fetch(:bob_graveyard, []))
        end
      end
      cast_and_resolve(game, "Probe Spell", *target_ids.map { it.respond_to?(:call) ? it.call(game) : it })
      game
    end

    def never = { "life" => "you", "at_most" => 0 }

    {
      "dig" => { "amount" => 2 }, "reveal_until" => { "for" => { "types" => ["land"] } }, "explore" => { "to" => "you" },
      "choose_cards" => { "from" => { "hand" => "you" }, "put" => "exile" },
      "sacrifice_choice" => { "filter" => "land" }, "put_in_library" => { "to" => "you", "position" => "owner_choice" },
      "search_library" => {}
    }.each do |name, params|
      it "#{name} does nothing when its \"if\" condition is false (CR 608.2c)" do
        game = probe([{ name => params.merge("if" => never) }], library: %w[Forest Island], hand: ["Forest"], board: ["Forest"])
        expect(game.pending_decision.kind).to eq("priority")
        expect(game.history.last.events.grep(Enjine::Events::ZoneChanged).map(&:reason)).to eq(["resolve"])
      end
    end

    it "chooses any number of cards, reveals them, and puts them on top, on the bottom or onto the battlefield" do
      top = probe([{ "choose_cards" => { "from" => { "hand" => "you" }, "count" => "any", "reveal" => "chosen",
                                         "put" => "library_top" } }], hand: ["Hill Giant", "Forest"], library: ["Island"])
      choose(top, "choose", "Hill Giant")
      choose(top, "done")
      expect(events(top, Enjine::Events::CardRevealed).map(&:card)).to eq(["hill_giant"])
      expect(cards(top, ids_in(top, "alice", :library))).to eq(%w[hill_giant island])
      bottom = probe([{ "choose_cards" => { "from" => { "graveyard" => "you" }, "put" => "library_bottom" } }],
                     graveyard: ["Hill Giant"], library: ["Island"])
      choose(bottom, "choose")
      expect(cards(bottom, ids_in(bottom, "alice", :library))).to eq(%w[island hill_giant])
      field = probe([{ "choose_cards" => { "from" => { "hand" => "you" }, "for" => { "types" => ["land"] }, "put" => "battlefield",
                                           "tapped" => true } }], hand: ["Forest"])
      choose(field, "choose")
      expect(field.state.object(obj_id(field, "Forest"))).to have_attributes(tapped: true, controller: 0)
    end

    it "a nested \"then\" effect can stop to ask, and an empty set asks nothing" do
      game = probe([{ "choose_cards" => { "from" => { "hand" => "you" }, "put" => "exile",
                                          "then" => [{ "surveil" => { "amount" => 1 } }] } }], hand: ["Hill Giant"], library: ["Island"])
      choose(game, "choose")
      expect(choices(game).map { it[:type] }).to eq(%w[top graveyard])
      choose(game, "graveyard")
      expect(cards(game, ids_in(game, "alice", :graveyard))).to include("island")
      empty = probe([{ "choose_cards" => { "from" => { "hand" => "you" }, "put" => "exile" } }])
      expect(empty.pending_decision.kind).to eq("priority")
    end

    it "reveals until a card into the hand and lets the player order the rest on the bottom" do
      game = probe([{ "reveal_until" => { "for" => { "types" => ["creature"] }, "rest" => "bottom_any" } }],
                   library: ["Forest", "Island", "Hill Giant", "Plains"])
      expect(choices(game).map { it[:type] }).to eq(%w[bottom bottom])
      choose(game, "bottom", "Island")
      expect(cards(game, ids_in(game, "alice", :hand))).to eq(["hill_giant"])
      expect(cards(game, ids_in(game, "alice", :library))).to eq(%w[plains island forest])
    end

    it "exiles the top cards of each opponent's library without a link" do
      game = probe([{ "exile_top" => { "amount" => 2, "to" => "each_opponent" } }])
      expect(game.state.exile.size).to eq(2)
      expect(game.state.exile.map { game.state.object(it).owner }.uniq).to eq([1])
    end

    it "a card that isn't on the battlefield explores with the effect's controller and gets no counter (CR 701.44c)" do
      game = probe([{ "explore" => { "to" => { "target" => 0 } } }], targets: ["graveyard_card"],
                                                                     target_ids: [->(g) { ids_in(g, "bob", :graveyard).first }],
                                                                     bob_graveyard: ["Hill Giant"], library: ["Lightning Bolt"])
      choose(game, "top")
      expect(cards(game, ids_in(game, "alice", :library))).to eq(["lightning_bolt"])
      expect(game.state.object(ids_in(game, "bob", :graveyard).first).counters).to eq({})
    end

    it "zone effects ignore players; a searcher that can't be determined doesn't search" do
      game = probe([{ "shuffle_into_library" => { "to" => "you" } }, { "put_in_library" => { "to" => "you", "position" => "top" } },
                    { "search_library" => { "searcher" => { "controller_of" => "you" } } }])
      expect(events(game, Enjine::Events::LibraryShuffled)).to be_empty
      expect(game.pending_decision.kind).to eq("priority")
    end

    it "the controller of an object gone without a remembered controller is unknown; linked cards of a gone source are none" do
      game = probe([], library: ["Island"])
      engine = game.instance_variable_get(:@engine)
      ctx = Enjine::Mechanics::EffectContext.new(0, "gone#1", ids_in(game, "alice", :library).first, ["gone#2"], [])
      selector = Enjine::Mechanics::Selector.build({ "controller_of" => { "target" => 0 } }, [], "s", targets_count: 1)
      expect(selector.resolve(engine, ctx)).to eq([])
      expect(Enjine::Mechanics::Selector.build("exiled_with", [], "s", targets_count: 0).resolve(engine, ctx)).to eq([])
    end

    it "describes counts in the zone effects" do
      any = Enjine::Mechanics.build_entry(:effect, { "sacrifice_choice" => { "filter" => { "creature" => { "token" => false } },
                                                                             "count" => "any" } }, [], "e")
      expect(any.to_s).to eq("you sacrifices any number of nontoken creature of their choice")
      search = Enjine::Mechanics.build_entry(:effect, { "search_library" => { "count" => "any" } }, [], "e")
      expect(search.to_s).to eq("search your library for any number of card → hand, shuffle")
      reveal = Enjine::Mechanics.build_entry(:effect, { "reveal_until" => { "put" => "hand" } }, [], "e")
      expect(reveal.to_s).to eq("reveal until 1 card → hand, rest → bottom random")
    end
  end
end
