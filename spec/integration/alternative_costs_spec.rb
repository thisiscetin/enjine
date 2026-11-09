# frozen_string_literal: true

# Keyword alternative costs: flashback (CR 702.34), harmonize (702.180), mayhem (702.187), warp (702.185),
# evoke (702.74), web-slinging (702.188), sneak (702.190), and convoke (702.51).
RSpec.describe "Alternative costs from keywords" do
  def damage(amount) = { "deal_damage" => { "amount" => amount, "to" => { "target" => 0 } } }

  let(:recall) do
    { "name" => "Ember Recall", "mana_cost" => "{1}{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                     "effects" => [damage(2),
                                                   { "gain_life" => { "amount" => 3, "if" => { "cast_from" => "graveyard" } } }] } },
                      { "flashback" => { "cost" => "{2}{R}" } }] }
  end
  let(:echo) do
    { "name" => "Choir Echo", "mana_cost" => "{2}{U}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 1 } }] } },
                      { "flashback" => { "cost" => [{ "mana" => "{U}" }, { "tap_permanents" => { "count" => 2 } }] } }] }
  end
  let(:chord) do
    { "name" => "Thrumming Chord", "mana_cost" => "{3}{G}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 2 } }] } },
                      { "harmonize" => { "cost" => "{4}{G}" } }] }
  end
  let(:frenzy) do
    { "name" => "Scrap Frenzy", "mana_cost" => "{2}{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                     "effects" => [damage(1), { "deal_damage" => { "amount" => 2, "to" => { "target" => 0 },
                                                                                   "if" => { "cast_with" => "mayhem" } } }] } },
                      { "mayhem" => { "cost" => "{R}" } }] }
  end
  let(:hound) do
    { "name" => "Rubble Hound", "mana_cost" => "{1}{R}", "types" => ["creature"], "power" => 2, "toughness" => 1,
      "abilities" => ["mayhem"] }
  end
  let(:rummage) do
    { "name" => "Hasty Rummage", "mana_cost" => "{R}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "discard" => { "amount" => 1, "to" => "you" } },
                                                   { "draw" => { "amount" => 1 } }] } }] }
  end
  let(:skipper) do
    { "name" => "Rift Skipper", "mana_cost" => "{3}{R}", "types" => ["creature"], "power" => 4, "toughness" => 4,
      "abilities" => [{ "warp" => { "cost" => "{R}" } }] }
  end
  let(:watcher) do
    { "name" => "Void Watcher", "mana_cost" => "{1}{B}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "step_begins" => { "step" => "end", "whose" => "your" } },
                                         "if" => { "cast_with_this_turn" => "warp" },
                                         "effects" => [{ "draw" => { "amount" => 1 } }] } }] }
  end
  let(:wisp) do
    { "name" => "Ember Wisp", "mana_cost" => "{3}{R}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} }, "targets" => ["any_target"], "effects" => [damage(2)] } },
                      { "evoke" => { "cost" => "{R}" } }] }
  end
  let(:leaper) do
    { "name" => "Rooftop Leaper", "mana_cost" => "{3}{W}", "types" => ["creature"], "power" => 3, "toughness" => 3,
      "abilities" => [{ "web_slinging" => { "cost" => "{W}" } }] }
  end
  let(:lurker) do
    { "name" => "Sewer Lurker", "mana_cost" => "{3}{B}", "types" => ["creature"], "power" => 3, "toughness" => 3,
      "abilities" => [{ "sneak" => { "cost" => "{B}" } }] }
  end
  let(:rally) do
    { "name" => "Gang Rally", "mana_cost" => "{3}{W}", "types" => ["sorcery"], "keywords" => ["convoke"],
      "abilities" => [{ "spell" => { "effects" => [{ "gain_life" => { "amount" => 4 } }] } }] }
  end
  let(:catalog) { catalog_with(recall, echo, chord, frenzy, hound, rummage, skipper, watcher, wisp, leaper, lurker, rally) }

  def board(hand: [], graveyard: [], battlefield: [], step: :precombat_main, tapped: [])
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice") do
        battlefield.each { battlefield it }
        tapped.each { battlefield it, tapped: true }
        hand(*hand) unless hand.empty?
        graveyard(*graveyard) unless graveyard.empty?
        library "Forest", count: 10
      end
      player("bob") do
        battlefield "Island"
        library "Forest", count: 10
      end
    end
  end

  def pay!(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def card(game, name, zone, player = "alice")
    ids_in(game, player, zone).find { game.state.object(it).card == Enjine::CardDefinition.slug(name) }
  end

  def cards_in(game, zone, player = "alice") = ids_in(game, player, zone).map { game.state.object(it).card }
  def exiled(game) = game.state.exile.map { game.state.object(it).card }
  def bob(game) = "player:#{game.names[1]}"
  def life(game, seat) = game.view_for(:observer)["players"][seat]["life"]
  def casts(game) = game.legal_options.select { it[:type] == "cast" }
  def engine(game) = game.instance_variable_get(:@engine)
  def mine(game, name) = game.state.battlefield.select { game.state.object(it).card == Enjine::CardDefinition.slug(name) }

  # Options are computed as a game is built; after changing its state directly, compute them again.
  def refresh(game) = game.instance_variable_set(:@pending_decision, nil)

  # Passes and puts triggers on the stack (first option) until `step` begins with an empty stack.
  def settle(game, step = nil)
    200.times do
      return game if game.pending_decision.kind == "priority" && game.state.stack.empty? && (step.nil? || game.step == step)

      options = game.legal_options
      game.submit(options.find { it[:type] == "pass" } || options.find { it[:type] == "done" } || options.first)
    end
    raise "never settled"
  end

  describe "flashback (CR 702.34a)" do
    it "casts from the graveyard for the flashback cost, then exiles the card; cast_from reads the zone" do
      game = board(graveyard: ["Ember Recall"], battlefield: %w[Mountain Mountain Mountain])
      id = card(game, "Ember Recall", :graveyard)
      expect(casts(game)).to eq([{ type: "cast", object: id, via: "alt:printed:1" }])
      game.submit(type: "cast", object: id, via: "alt:printed:1")
      game.submit(type: "target", target: bob(game))
      expect(game.pending_decision.details["remaining"]).to eq("{2}{R}")
      pay!(game)
      pass_both(game)
      expect(life(game, 1)).to eq(18)
      expect(life(game, 0)).to eq(23)
      expect(exiled(game)).to eq(["ember_recall"])
      expect(cards_in(game, :graveyard)).to be_empty
    end

    it "isn't offered without enough mana; cast from the hand it goes to the graveyard and cast_from is hand" do
      game = board(graveyard: ["Ember Recall"], battlefield: %w[Mountain Mountain])
      expect(casts(game)).to be_empty
      game = board(hand: ["Ember Recall"], battlefield: %w[Mountain Mountain])
      game.submit(type: "cast", object: card(game, "Ember Recall", :hand))
      game.submit(type: "target", target: bob(game))
      pay!(game)
      pass_both(game)
      expect(life(game, 0)).to eq(20)
      expect(cards_in(game, :graveyard)).to eq(["ember_recall"])
    end

    it "pays non-mana parts of a flashback cost (tap two creatures), and is exiled when countered" do
      game = board(graveyard: ["Choir Echo"], battlefield: ["Island", "Grizzly Bears", "Grizzly Bears"])
      id = card(game, "Choir Echo", :graveyard)
      game.submit(type: "cast", object: id, via: "alt:printed:1")
      expect(game.pending_decision.kind).to eq("choose_cost")
      2.times { game.submit(game.legal_options.find { it[:type] == "cost" }) }
      pay!(game)
      spell = game.state.stack.first
      expect(game.state.object(spell).memory).to include("cast_from" => "graveyard", "cast_with" => "flashback")
      engine(game).counter!(spell)
      expect(exiled(game)).to eq(["choir_echo"])
    end

    it "isn't offered when the non-mana part can't be paid" do
      game = board(graveyard: ["Choir Echo"], battlefield: ["Island", "Grizzly Bears"])
      expect(casts(game)).to be_empty
    end
  end

  describe "harmonize (CR 702.180)" do
    it "taps up to one creature to reduce the total cost by its power" do
      game = board(graveyard: ["Thrumming Chord"], battlefield: ["Forest", "Forest", "Forest", "Grizzly Bears"])
      id = card(game, "Thrumming Chord", :graveyard)
      bears = obj_id(game, "Grizzly Bears")
      game.submit(type: "cast", object: id, via: "alt:printed:1")
      expect(game.pending_decision).to have_attributes(kind: "choose_cost")
      expect(game.legal_options).to eq([{ type: "cost", object: bears }, { type: "cost" }, { type: "cancel" }])
      game.submit(type: "cost", object: bears)
      expect(game.state.object(bears).tapped).to be(true)
      expect(game.pending_decision.details["remaining"]).to eq("{2}{G}")
      game.submit(type: "cancel")
      expect(game.state.object(bears).tapped).to be(false)
      expect(cards_in(game, :graveyard)).to eq(["thrumming_chord"])
    end

    it "isn't castable without a creature when the full cost can't be paid; tapping none pays it all" do
      game = board(graveyard: ["Thrumming Chord"], battlefield: %w[Forest Forest Forest])
      expect(casts(game)).to be_empty
      game = board(graveyard: ["Thrumming Chord"], battlefield: ["Forest"] * 5)
      game.submit(type: "cast", object: card(game, "Thrumming Chord", :graveyard), via: "alt:printed:1")
      game.submit(type: "cost")
      expect(game.pending_decision.details["remaining"]).to eq("{4}{G}")
      pay!(game)
      pass_both(game)
      expect(exiled(game)).to eq(["thrumming_chord"])
    end
  end

  describe "mayhem (CR 702.187)" do
    it "casts a card discarded this turn for its mayhem cost; cast_with mayhem holds" do
      game = board(hand: ["Hasty Rummage", "Scrap Frenzy"], battlefield: %w[Mountain Mountain])
      game.submit(type: "cast", object: card(game, "Hasty Rummage", :hand))
      pay!(game)
      pass_both(game)
      game.submit(type: "discard", object: card(game, "Scrap Frenzy", :hand)) if game.pending_decision.kind == "effect_choice"
      frenzy = card(game, "Scrap Frenzy", :graveyard)
      expect(frenzy).not_to be_nil
      option = { type: "cast", object: frenzy, via: "alt:printed:1" }
      expect(casts(game)).to include(option)
      game.submit(option)
      game.submit(type: "target", target: bob(game))
      pay!(game)
      pass_both(game)
      expect(life(game, 1)).to eq(17)
    end

    it "only while discarded this turn; mayhem without a cost lets the card be played for its mana cost" do
      game = board(graveyard: ["Scrap Frenzy", "Rubble Hound"], battlefield: %w[Mountain Mountain Mountain])
      expect(casts(game)).to be_empty
      hound = card(game, "Rubble Hound", :graveyard)
      game.state.object(hound).memory["discarded"] = { "turn" => game.turn - 1 }
      refresh(game)
      expect(casts(game)).to be_empty
      game.state.object(hound).memory["discarded"] = { "turn" => game.turn }
      refresh(game)
      expect(casts(game)).to eq([{ type: "cast", object: hound, via: "alt:printed:0" }])
      game.submit(type: "cast", object: hound, via: "alt:printed:0")
      expect(game.pending_decision.details["remaining"]).to eq("{1}{R}")
      pay!(game)
      expect(game.state.object(game.state.stack.first).memory).to eq("cast_from" => "graveyard") # no mayhem cost paid
    end
  end

  describe "warp (CR 702.185)" do
    it "exiles the permanent at the next end step; its owner may cast it from exile on a later turn" do
      game = board(hand: ["Rift Skipper"], battlefield: ["Mountain", "Void Watcher"])
      id = card(game, "Rift Skipper", :hand)
      expect(casts(game)).to include({ type: "cast", object: id, via: "alt:printed:0" })
      game.submit(type: "cast", object: id, via: "alt:printed:0")
      pay!(game)
      pass_both(game)
      skipper = obj_id(game, "Rift Skipper")
      expect(game.state.object(skipper).memory).to include("cast_with" => "warp", "cast_from" => "hand")
      hand_before = ids_in(game, "alice", :hand).size
      game.submit(type: "pass")
      settle(game, :end)
      expect(exiled(game)).to eq(["rift_skipper"])
      expect(ids_in(game, "alice", :hand).size).to eq(hand_before + 1) # Void Watcher: a spell was warped this turn
      warped = game.state.exile.first
      expect(game.state.object(warped).memory["warped"]).to eq(3)
      expect(engine(game).play_methods(0, warped)).to eq([])
      game.state.turn = 5
      expect(engine(game).play_methods(0, warped)).to eq([{ "via" => "warped", "play" => "cast" }])
    end

    it "casts a warped card from exile for its mana cost on a later turn" do
      game = board(battlefield: %w[Mountain Mountain Mountain Mountain], hand: ["Rift Skipper"])
      id = card(game, "Rift Skipper", :hand)
      engine(game).move!(id, :exile, reason: "warp")
      warped = game.state.exile.first
      game.state.object(warped).memory["warped"] = 2
      refresh(game)
      expect(casts(game)).to eq([{ type: "cast", object: warped, via: "warped" }])
      game.submit(type: "cast", object: warped, via: "warped")
      expect(game.pending_decision.details["remaining"]).to eq("{3}{R}")
      pay!(game)
      expect(game.state.object(game.state.stack.first).memory).to eq("cast_from" => "exile")
    end
  end

  describe "evoke (CR 702.74)" do
    it "sacrifices the evoked permanent when it enters; its other enters ability still triggers" do
      game = board(hand: ["Ember Wisp"], battlefield: ["Mountain"])
      game.submit(type: "cast", object: card(game, "Ember Wisp", :hand), via: "alt:printed:1")
      pay!(game)
      pass_both(game)
      until game.pending_decision.kind == "priority" && game.state.stack.empty?
        options = game.legal_options
        game.submit(options.find { it[:type] == "target" && it[:target] == bob(game) } ||
                    options.find { %w[order pass].include?(it[:type]) } || options.first)
      end
      expect(cards_in(game, :graveyard)).to eq(["ember_wisp"])
      expect(life(game, 1)).to eq(18)
    end
  end

  describe "web-slinging (CR 702.188)" do
    it "returns a tapped creature you control as part of the cost" do
      game = board(hand: ["Rooftop Leaper"], battlefield: ["Plains", "Grizzly Bears"], tapped: ["Grizzly Bears"])
      untapped, tapped = mine(game, "Grizzly Bears").sort_by { game.state.object(it).tapped ? 1 : 0 }
      game.submit(type: "cast", object: card(game, "Rooftop Leaper", :hand), via: "alt:printed:0")
      expect(game.pending_decision.details["cost"]).to eq("Return a tapped creature you control to its owner's hand")
      expect(game.legal_options).to eq([{ type: "cost", object: tapped }, { type: "cancel" }])
      game.submit(type: "cost", object: tapped)
      pay!(game)
      expect(cards_in(game, :hand)).to eq(["grizzly_bears"])
      expect(game.state.battlefield).to include(untapped)
    end

    it "isn't offered without a tapped creature" do
      game = board(hand: ["Rooftop Leaper"], battlefield: ["Plains", "Grizzly Bears"])
      expect(casts(game)).to be_empty
    end
  end

  describe "sneak (CR 702.190)" do
    it "during your declare blockers step, returns an unblocked attacker; the permanent enters tapped and attacking" do
      game = board(hand: ["Sewer Lurker"], battlefield: ["Swamp", "Grizzly Bears"], step: :declare_blockers)
      bears = obj_id(game, "Grizzly Bears")
      game.state.attackers[bears] = { "target" => bob(game), "blocked" => false }
      refresh(game)
      option = { type: "cast", object: card(game, "Sewer Lurker", :hand), via: "alt:printed:0" }
      expect(casts(game)).to eq([option])
      game.submit(option)
      expect(game.legal_options).to eq([{ type: "cost", object: bears }, { type: "cancel" }])
      game.submit(type: "cost", object: bears)
      pay!(game)
      pass_both(game)
      lurker = obj_id(game, "Sewer Lurker")
      expect(game.state.object(lurker).tapped).to be(true)
      expect(game.state.attackers[lurker]).to eq({ "target" => bob(game), "blocked" => false })
      expect(cards_in(game, :hand)).to eq(["grizzly_bears"])
    end

    it "enters tapped but not attacking when what the returned creature attacked is gone" do
      game = board(hand: ["Sewer Lurker"], battlefield: ["Swamp"])
      enters = { "tapped" => false, "counters" => {} }
      spell = Struct.new(:id, :memory).new("x", { "cast_from" => "hand", "sneak_attack" => "walker#99" })
      engine(game).alt_enters!(spell, enters)
      expect(enters).to eq("tapped" => true, "counters" => {}, "memory" => { "cast_from" => "hand" })
      ctx = Enjine::Mechanics::EffectContext.new(0, "gone#1", nil, [])
      expect(Enjine::Mechanics::Condition.build({ "cast_from" => "hand" }, [], "if").true?(engine(game), ctx)).to be(false)
    end

    it "isn't offered outside your declare blockers step or with only blocked attackers" do
      game = board(hand: ["Sewer Lurker"], battlefield: ["Swamp", "Grizzly Bears"], step: :declare_attackers)
      game.state.attackers[obj_id(game, "Grizzly Bears")] = { "target" => bob(game), "blocked" => false }
      refresh(game)
      expect(casts(game)).to be_empty
      game = board(hand: ["Sewer Lurker"], battlefield: ["Swamp", "Grizzly Bears"], step: :declare_blockers)
      game.state.attackers[obj_id(game, "Grizzly Bears")] = { "target" => bob(game), "blocked" => true }
      refresh(game)
      expect(casts(game)).to be_empty
    end
  end

  describe "convoke (CR 702.51)" do
    it "is castable with creatures paying part of the cost, each tapped for {1} or its color" do
      game = board(hand: ["Gang Rally"], battlefield: ["Plains", "Plains", "Grizzly Bears", "Grizzly Bears"])
      expect(casts(game)).to eq([{ type: "cast", object: card(game, "Gang Rally", :hand) }])
      game.submit(casts(game).first)
      bears = mine(game, "Grizzly Bears")
      expect(game.legal_options).to include({ type: "convoke", object: bears.first }, { type: "convoke", object: bears.last })
      bears.each { game.submit(type: "convoke", object: it) }
      expect(game.pending_decision.details["remaining"]).to eq("{1}{W}")
      pay!(game)
      pass_both(game)
      expect(life(game, 0)).to eq(24)
      expect(bears.map { game.state.object(it).tapped }).to eq([true, true])
    end

    it "offers only creatures that can still pay something, and keeps an irreversible payment payable" do
      game = board(hand: ["Gang Rally"], battlefield: ["Plains"] + (["Grizzly Bears"] * 4))
      game.submit(casts(game).first)
      bears = mine(game, "Grizzly Bears")
      bears.first(3).each { game.submit(type: "convoke", object: it) }
      expect(game.pending_decision.details["remaining"]).to eq("{W}")
      expect(game.legal_options.map { it[:type] }).not_to include("convoke")
      game = board(hand: ["Gang Rally"], battlefield: ["Plains"] + (["Grizzly Bears"] * 3))
      game.submit(casts(game).first)
      engine(game).payment["irreversible"] = true
      refresh(game)
      expect(game.legal_options.count { it[:type] == "convoke" }).to eq(3)
      game.submit(type: "convoke", object: mine(game, "Grizzly Bears").first)
      expect(game.pending_decision.details["remaining"]).to eq("{2}{W}")
    end

    it "isn't castable when creatures plus mana fall short; cancelling untaps convoked creatures" do
      game = board(hand: ["Gang Rally"], battlefield: ["Plains", "Plains", "Grizzly Bears"])
      expect(casts(game)).to be_empty
      game = board(hand: ["Gang Rally"], battlefield: ["Plains", "Grizzly Bears", "Grizzly Bears", "Grizzly Bears"])
      game.submit(casts(game).first)
      bears = obj_id(game, "Grizzly Bears")
      game.submit(type: "convoke", object: bears)
      game.submit(type: "cancel")
      expect(game.state.object(bears).tapped).to be(false)
    end
  end
end
