# frozen_string_literal: true

# Invented cards for small DSL shapes: card specs with the chosen name (CR 201.4, 607.2d), batched "one or more"
# triggers (CR 603.2c) and damage recipients (CR 120.3), counters on players (CR 122.1), the kindred card type in
# spell filters (CR 308), life-gain replacement effects (CR 614.1a, 616.1, 119.10) and another player choosing
# cards (CR 608.2d).
RSpec.describe "DSL expressiveness gaps (invented cards)" do
  def creature(name, stats, abilities = [], cost: "{1}", subtypes: [])
    { "name" => name, "mana_cost" => cost, "types" => ["creature"], "subtypes" => subtypes, "power" => stats[0],
      "toughness" => stats[1], "abilities" => abilities }
  end

  def sorcery(name, effects, targets: [], cost: "{1}", types: ["sorcery"])
    { "name" => name, "mana_cost" => cost, "types" => types,
      "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? } }] }
  end

  def triggered(when_, effects) = { "triggered" => { "when" => when_, "effects" => effects } }
  def gain(amount) = { "gain_life" => { "amount" => amount } }
  def gain_that_many = gain({ "triggering" => "amount" })

  let(:cards) do
    [
      sorcery("Spec Consult", [{ "choose_card_name" => {} },
                               { "reveal_until" => { "for" => { "name" => "chosen" }, "put" => "hand", "rest" => "graveyard" } }]),
      sorcery("Spec Dig Name", [{ "choose_card_name" => {} }, { "exile_top" => { "until" => { "card" => { "name" => "chosen" } } } }]),
      sorcery("Spec Therapy", [{ "choose_card_name" => { "not" => ["land"] } },
                               { "choose_cards" => { "from" => { "hand" => { "target" => 0 } }, "for" => { "name" => "chosen" },
                                                     "count" => "all", "put" => "discard", "reveal" => "all" } }],
              targets: ["player"]),
      { "name" => "Spec Flute", "mana_cost" => "{1}", "types" => ["artifact"],
        "abilities" => [{ "choose_card_name" => {} },
                        { "cost_modifier" => { "spells" => { "name" => "chosen" }, "caster" => "any", "increase" => 3 } }] },
      creature("Spec Mourner", [1, 1], [triggered({ "dies" => { "subject" => { "each" => "creature" }, "batched" => true } },
                                                  [gain_that_many])]),
      creature("Spec Greeter", [1, 1], [triggered({ "enters" => { "subject" => { "each" => "creature", "other" => true },
                                                                  "batched" => true } },
                                                  [gain_that_many,
                                                   { "add_counters" => { "counter" => "+1/+1", "amount" => 1,
                                                                         "to" => { "triggering" => "objects" } } }])]),
      creature("Spec Raid Captain", [1, 1], [triggered({ "deals_damage" => { "subject" => { "each" => "creature", "controller" => "you" },
                                                                             "combat" => true, "to" => "player", "batched" => true } },
                                                       [gain_that_many])]),
      creature("Spec Walker Hunter", [2, 2], [triggered({ "deals_damage" => { "to" => %w[planeswalker battle] } }, [gain(5)])]),
      sorcery("Spec Twin Bears", [{ "create_token" => { "token" => { "name" => "Spec Cub", "types" => ["creature"], "power" => 1,
                                                                     "toughness" => 1 }, "amount" => 2 } }]),
      sorcery("Spec Sweep", [{ "destroy" => { "to" => { "each" => "creature" } } }]),
      sorcery("Spec Cleanse", [{ "remove_all_counters" => { "to" => "you" } },
                               { "remove_counters" => { "counter" => "energy", "amount" => 1, "to" => "each_opponent" } }]),
      sorcery("Spec Goblin Gambit", [gain(1)], types: %w[kindred sorcery]),
      creature("Spec Kin Watcher", [1, 1], [triggered({ "cast" => { "spell" => { "spell" => { "types" => ["kindred"] } } } },
                                                      [gain(2)])]),
      { "name" => "Spec Boon", "mana_cost" => "{1}", "types" => ["enchantment"],
        "abilities" => [{ "life_gain_replacement" => { "multiply" => 2 } }] },
      { "name" => "Spec Halo", "mana_cost" => "{1}", "types" => ["enchantment"],
        "abilities" => [{ "life_gain_replacement" => { "plus" => 1 } }] },
      { "name" => "Spec Remedy", "mana_cost" => "{1}", "types" => ["enchantment"],
        "abilities" => [{ "life_gain_replacement" => { "player" => "opponent", "lose" => true } }] },
      sorcery("Spec Heal", [gain(3)]),
      sorcery("Spec Bargain", [{ "mill" => { "amount" => 3 } },
                               { "choose_cards" => { "from" => { "result" => 0 }, "for" => { "not_types" => ["land"] },
                                                     "put" => "hand", "chooser" => "each_opponent" } }]),
      sorcery("Spec Hand Pick", [{ "choose_cards" => { "from" => { "hand" => "you" }, "put" => "discard",
                                                       "chooser" => { "target" => 0 } } }],
              targets: ["player"]),
      { "name" => "Spec War Banner", "mana_cost" => "{1}", "types" => ["artifact"],
        "abilities" => [{ "static" => { "affects" => { "each" => { "creature" => { "attacking" => true } }, "controller" => "you" },
                                        "keywords" => ["first_strike"], "pump" => { "power" => 1, "toughness" => 0 } } },
                        { "static" => { "affects" => { "each" => { "creature" => { "tapped" => false, "blocking" => false } },
                                                       "controller" => "opponent" },
                                        "pump" => { "power" => 0, "toughness" => 1 } } }] },
      { "name" => "Spec Duel Blade", "mana_cost" => "{1}", "types" => ["artifact"], "subtypes" => ["equipment"],
        "abilities" => [{ "static" => { "affects" => "attached", "if" => { "attacking" => "attached" },
                                        "keywords" => ["first_strike"] } }] },
      { "name" => "Spec Hush Mage", "mana_cost" => "{1}", "types" => ["creature"], "power" => 1, "toughness" => 1,
        "abilities" => [{ "choose_card_name" => {} },
                        { "player_rule" => { "rule" => "cant_cast", "affects" => "each", "spells" => { "name" => "chosen" } } }] },
      sorcery("Spec Ambush Call", [{ "create_token" => { "token" => { "name" => "Spec Raider", "types" => ["creature"], "power" => 1,
                                                                      "toughness" => 1 }, "attacking" => true } }],
              types: ["instant"]),
      sorcery("Spec Self Pick", [{ "choose_cards" => { "from" => { "hand" => "you" }, "put" => "discard",
                                                       "chooser" => { "triggering" => "player" } } }])
    ]
  end

  def board(hand: [], battlefield: [], theirs: [], library: ["Island"] * 10, their_library: ["Swamp"] * 10, mana: { C: 6 },
            step: :precombat_main, their_hand: [])
    build_game(catalog_with(*cards)) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana) do
        hand(*hand) unless hand.empty?
        library(*library)
        battlefield.each { battlefield it }
      end
      player("bob") do
        hand(*their_hand) unless their_hand.empty?
        library(*their_library)
        theirs.each { battlefield it }
      end
    end
  end

  def play(game, action, *answers)
    game.submit(action) if action
    until (decision = game.pending_decision).kind == "priority" && game.state.stack.empty?
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.first)
      else
        answer = answers.shift or raise "no answer for #{decision.kind}: #{game.legal_options}"
        game.submit(answer.respond_to?(:call) ? answer.call(game) : answer)
      end
    end
    game
  end

  def cast(game, card, *) = play(game, { type: "cast", object: obj_id(game, card, zone: :hand, player: "alice") }, *)
  def pick(type, **details) = ->(game) { game.legal_options.find { |o| o[:type] == type && details.all? { |k, v| o[k] == v } } }
  def bob = ->(_game) { { type: "target", target: "player:bob" } }
  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, name) = game.state.players[game.names.index(name)].life
  def cards_in(game, name, zone) = (zone == :exile ? game.state.exile : ids_in(game, name, zone)).map { game.state.object(it).card }

  describe "card specs with the chosen name (CR 201.4, 607.2d)" do
    it "reveal_until stops at a card with the chosen name" do
      game = board(hand: ["Spec Consult"], library: ["Island", "Forest", "Grizzly Bears", "Island"])
      cast(game, "Spec Consult", pick("card_name", card_name: "Grizzly Bears"))
      expect(cards_in(game, "alice", :hand)).to eq(["grizzly_bears"])
      expect(cards_in(game, "alice", :graveyard)).to contain_exactly("island", "forest", "spec_consult")
    end

    it "exile_top until a card with the chosen name" do
      game = board(hand: ["Spec Dig Name"], library: ["Island", "Grizzly Bears", "Forest"])
      cast(game, "Spec Dig Name", pick("card_name", card_name: "Grizzly Bears"))
      expect(cards_in(game, "alice", :exile)).to contain_exactly("island", "grizzly_bears")
      expect(cards_in(game, "alice", :library)).to eq(["forest"])
    end

    it "choose_cards count all: the target discards every card with the chosen name, no choice" do
      game = board(hand: ["Spec Therapy"], their_hand: ["Grizzly Bears", "Grizzly Bears", "Swamp"])
      cast(game, "Spec Therapy", bob, pick("card_name", card_name: "Grizzly Bears"))
      expect(cards_in(game, "bob", :hand)).to eq(["swamp"])
      expect(cards_in(game, "bob", :graveyard)).to eq(%w[grizzly_bears grizzly_bears])
    end

    it "cost_modifier: spells with the name its source chose cost more" do
      game = board(hand: ["Spec Flute", "Spec Heal", "Spec Sweep"], mana: { C: 6 })
      cast(game, "Spec Flute", pick("name", name: "Spec Heal"))
      e = engine(game)
      flute = obj_id(game, "Spec Flute")
      heal = obj_id(game, "Spec Heal", zone: :hand, player: "alice")
      sweep = obj_id(game, "Spec Sweep", zone: :hand, player: "alice")
      ability = game.catalog.fetch(game.state.object(flute).card).abilities.find { it.kind == :cost_modifier }
      expect(ability.change_for(e, game.state.object(flute), game.state.object(heal), 0)).to eq(3)
      expect(ability.change_for(e, game.state.object(flute), game.state.object(sweep), 0)).to eq(0)
      expect(ability.to_s).to include("cost {3} more")
    end

    it "nothing matches the chosen name before a name is chosen, and the spec reads as such" do
      spec = Enjine::Mechanics::CardSpec.build({ "name" => "chosen", "types" => ["creature"] }, [], "x")
      game = board(battlefield: ["Grizzly Bears"])
      bears = game.state.object(obj_id(game, "Grizzly Bears"))
      expect(spec.match?(engine(game), bears)).to be(false)
      expect(spec.to_s).to eq("creature card with the chosen name")
      expect(spec.unrelated.any?).to be(false)
    end
  end

  it "player_rule cant_cast with spells named as its source chose (CR 201.4, 601.2)" do
    game = board(hand: ["Spec Hush Mage", "Spec Heal", "Spec Sweep"])
    cast(game, "Spec Hush Mage", pick("name", name: "Spec Heal"))
    types = game.legal_options.select { it[:type] == "cast" }.map { game.state.object(it[:object]).card }
    expect(types).to eq(["spec_sweep"])
  end

  describe "batched triggers (CR 603.2c)" do
    it "dies batched: creatures dying together to one effect trigger it once, counting them" do
      game = board(hand: ["Spec Sweep"], battlefield: ["Grizzly Bears", "Grizzly Bears"], theirs: ["Spec Mourner", "Grizzly Bears"])
      cast(game, "Spec Sweep")
      # Spec Mourner dies too and still sees all four die at once (CR 603.10a)
      expect(life(game, "bob")).to eq(24)
    end

    it "dies batched: creatures dying to state-based actions after combat damage are one batch" do
      game = board(battlefield: ["Grizzly Bears", "Grizzly Bears"], theirs: ["Spec Mourner", "Grizzly Bears", "Grizzly Bears"],
                   step: :beginning_of_combat)
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      bears = game.state.battlefield.select { game.state.object(it).card == "grizzly_bears" && game.state.object(it).controller.zero? }
      bears.each { game.submit(type: "attack", object: it, target: "player:bob") }
      game.submit(type: "done") if option_types(game).include?("done")
      game.submit(type: "pass") until game.pending_decision.kind == "declare_blockers"
      blockers = game.state.battlefield.select { game.state.object(it).card == "grizzly_bears" && game.state.object(it).controller == 1 }
      blockers.zip(bears).each { |b, a| game.submit(type: "block", object: b, attacker: a) }
      game.submit(type: "done") if option_types(game).include?("done")
      skip_to(game, :end_of_combat)
      expect(life(game, "bob")).to eq(24)
    end

    it "enters batched: tokens entering together trigger it once; {triggering: objects} are those tokens" do
      game = board(hand: ["Spec Twin Bears"], battlefield: ["Spec Greeter"])
      cast(game, "Spec Twin Bears")
      expect(life(game, "alice")).to eq(22)
      tokens = game.state.battlefield.select { engine(game).chars(it).name == "Spec Cub" }
      expect(tokens.map { game.state.object(it).counters["+1/+1"] }).to eq([1, 1])
      expect(game.state.object(obj_id(game, "Spec Greeter")).counters["+1/+1"].to_i).to eq(0)
    end

    it "deals_damage batched: one or more creatures dealing combat damage to a player trigger it once per step" do
      game = board(battlefield: ["Spec Raid Captain", "Grizzly Bears", "Grizzly Bears"], step: :beginning_of_combat)
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      mine = game.state.battlefield.select { game.state.object(it).controller.zero? }
      mine.each { game.submit(type: "attack", object: it, target: "player:bob") }
      game.submit(type: "done") if option_types(game).include?("done")
      skip_to(game, :end_of_combat)
      expect(life(game, "bob")).to eq(15)
      expect(life(game, "alice")).to eq(23)
    end

    it "deals_damage to a planeswalker (CR 120.3c): a list of recipient kinds" do
      game = board(battlefield: ["Spec Walker Hunter"], theirs: ["Vessa, Rally Captain"], step: :beginning_of_combat)
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      walker = obj_id(game, "Vessa, Rally Captain")
      game.submit(type: "attack", object: obj_id(game, "Spec Walker Hunter"), target: walker)
      game.submit(type: "done") if option_types(game).include?("done")
      skip_to(game, :end_of_combat)
      expect(life(game, "alice")).to eq(25)
    end

    it "deals_damage recipients: you, permanent and the to_s of batched/listed triggers" do
      build = ->(data) { Enjine::Mechanics.build_entry(:trigger, data, errors = [], "x").tap { expect(errors).to eq([]) } }
      expect(build.call({ "deals_damage" => { "to" => %w[player planeswalker] } }).to_s)
        .to eq("Whenever this deals damage to a player or planeswalker")
      expect(build.call({ "deals_damage" => { "batched" => true, "subject" => { "each" => "creature" } } }).to_s)
        .to eq("Whenever one or more of creature deal damage")
      game = board(battlefield: ["Grizzly Bears"])
      bears = obj_id(game, "Grizzly Bears")
      you = build.call({ "deals_damage" => { "to" => "you" } })
      perm = build.call({ "deals_damage" => { "to" => "permanent" } })
      source = { "id" => bears, "controller" => 0 }
      expect([you.recipient_ok?(engine(game), "player:alice", source, "you"),
              you.recipient_ok?(engine(game), "player:bob", source, "you"),
              perm.recipient_ok?(engine(game), bears, source, "permanent"),
              perm.recipient_ok?(engine(game), "player:bob", source, "permanent"),
              perm.recipient_ok?(engine(game), "gone#999", source, "creature")]).to eq([true, false, true, false, false])
    end
  end

  it "remove_all_counters and remove_counters reach players' counters (CR 122.1, 122.8)" do
    game = board(hand: ["Spec Cleanse"])
    e = engine(game)
    e.add_player_counters!(0, "poison", 3)
    e.add_player_counters!(0, "experience", 2)
    e.add_player_counters!(1, "energy", 2)
    cast(game, "Spec Cleanse")
    expect([e.player_counters(0), e.player_counters(1)]).to eq([{}, { "energy" => 1 }])
    expect(game.state.players[0].poison).to eq(0)
    expect(e.remove_player_counters!(1, "rad", 1)).to eq(0)
  end

  it "spell filters name the kindred card type (CR 308.1)" do
    game = board(hand: ["Spec Goblin Gambit"], battlefield: ["Spec Kin Watcher"])
    cast(game, "Spec Goblin Gambit")
    expect(life(game, "alice")).to eq(23)
  end

  describe "life-gain replacement effects (CR 614.1a, 616.1)" do
    it "plus 1 applies before doubling, each once" do
      game = board(hand: ["Spec Heal"], battlefield: ["Spec Boon", "Spec Halo"])
      cast(game, "Spec Heal")
      expect(life(game, "alice")).to eq(28)
    end

    it "an opponent's gain becomes a loss; then nothing else applies; your own gain is unaffected" do
      game = board(hand: ["Spec Heal"], battlefield: ["Spec Remedy"], theirs: ["Spec Boon"])
      engine(game).change_life!(1, 4)
      expect(life(game, "bob")).to eq(16)
      cast(game, "Spec Heal")
      expect(life(game, "alice")).to eq(23)
    end

    it "lifelink gain is replaced too, and a loss is not" do
      game = board(battlefield: ["Spec Boon"])
      engine(game).change_life!(0, -2)
      expect(life(game, "alice")).to eq(18)
      engine(game).lifelink!(obj_id(game, "Spec Boon"), 2)
      expect(life(game, "alice")).to eq(22)
    end

    it "describes itself" do
      texts = [{ "multiply" => 2 }, { "plus" => 1, "player" => "any" }, { "lose" => true, "player" => "opponent" }].map do
        Enjine::Mechanics.build_entry(:ability, { "life_gain_replacement" => it }, [], "x").to_s
      end
      expect(texts).to eq(["if you would gain life, gain 2 times that much instead",
                           "if a player would gain life, gain that much plus 1 instead",
                           "if an opponent would gain life, lose that much instead"])
    end
  end

  describe "choose_cards chooser (CR 608.2d)" do
    it "an opponent chooses among the milled cards; you put the chosen one into your hand" do
      game = board(hand: ["Spec Bargain"], library: ["Grizzly Bears", "Spec Heal", "Island", "Forest"])
      game.submit(type: "cast", object: obj_id(game, "Spec Bargain", zone: :hand, player: "alice"))
      game.submit(game.legal_options.find { it[:type] == "pay_mana" })
      game.submit(type: "pass") until game.pending_decision.kind != "priority"
      expect(game.pending_decision.player).to eq("bob")
      heal = ids_in(game, "alice", :graveyard).find { game.state.object(it).card == "spec_heal" }
      play(game, nil, ->(g) { g.legal_options.find { it[:object] == heal } })
      expect(cards_in(game, "alice", :hand)).to eq(["spec_heal"])
    end

    it "the target player chooses from your hand, looking at it first" do
      game = board(hand: ["Spec Hand Pick", "Grizzly Bears", "Island"])
      game.submit(type: "cast", object: obj_id(game, "Spec Hand Pick", zone: :hand, player: "alice"))
      game.submit(type: "target", target: "player:bob")
      game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
      game.submit(type: "pass") until game.pending_decision.kind != "priority"
      expect(game.pending_decision.player).to eq("bob")
      looked = game.history.flat_map(&:events).select { it.is_a?(Enjine::Events::LookedAt) && it.player == "bob" }
      expect(looked.flat_map(&:objects).size).to eq(2)
      bears = obj_id(game, "Grizzly Bears", zone: :hand, player: "alice")
      play(game, nil, ->(g) { g.legal_options.find { it[:object] == bears } })
      expect(cards_in(game, "alice", :graveyard)).to contain_exactly("grizzly_bears", "spec_hand_pick")
    end

    it "a chooser naming no player falls back to you" do
      game = board(hand: ["Spec Self Pick", "Island"])
      game.submit(type: "cast", object: obj_id(game, "Spec Self Pick", zone: :hand, player: "alice"))
      game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
      game.submit(type: "pass") until game.pending_decision.kind != "priority"
      expect(game.pending_decision.player).to eq("alice")
    end

    it "validates and describes the chooser" do
      errors = []
      Enjine::Mechanics.build_entry(:effect, { "choose_cards" => { "from" => { "hand" => "you" }, "put" => "hand", "random" => true,
                                                                   "chooser" => "each_opponent" } }, errors, "x")
      expect(errors).to eq(["x.choose_cards.chooser: random cards have no chooser"])
      errors = []
      Enjine::Mechanics.build_entry(:effect, { "choose_cards" => { "from" => { "hand" => "you" }, "put" => "hand", "random" => true,
                                                                   "count" => "all" } }, errors, "x")
      expect(errors).to eq(["x.choose_cards.count: must be a number to pick at random"])
      effect = Enjine::Mechanics.build_entry(:effect, { "choose_cards" => { "from" => { "hand" => "you" }, "put" => "hand",
                                                                            "count" => "all", "chooser" => "each_opponent" } }, [], "x")
      expect(effect.to_s).to include("choose all card from the hand of you").and include("chooses)")
    end
  end

  describe "statics reading combat and tapped status (CR 506.4, 613.8)" do
    it "a token put onto the battlefield attacking gets the bonus at once (CR 508.4, 506.4)" do
      game = board(hand: ["Spec Ambush Call"], battlefield: ["Spec War Banner", "Grizzly Bears", "Island"], step: :beginning_of_combat)
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      game.submit(type: "attack", object: obj_id(game, "Grizzly Bears"), target: "player:bob")
      game.submit(type: "done") if option_types(game).include?("done")
      cast(game, "Spec Ambush Call")
      raider = game.state.battlefield.find { engine(game).chars(it).name == "Spec Raider" }
      expect([engine(game).attackers.key?(raider), engine(game).chars(raider).keyword?(:first_strike)]).to eq([true, true])
    end

    it "attacking creatures you control get first strike and +1/+0 while attacking, and lose them after combat" do
      game = board(battlefield: ["Spec War Banner", "Grizzly Bears"], theirs: ["Grizzly Bears"], step: :beginning_of_combat)
      e = engine(game)
      mine, theirs = game.state.battlefield.select { game.state.object(it).card == "grizzly_bears" }
                         .partition { game.state.object(it).controller.zero? }.map(&:first)
      expect([e.chars(mine).keyword?(:first_strike), e.power(game.state.object(mine))]).to eq([false, 2])
      expect(e.toughness(game.state.object(theirs))).to eq(3) # untapped and not blocking
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      game.submit(type: "attack", object: mine, target: "player:bob")
      game.submit(type: "done") if option_types(game).include?("done")
      expect([e.chars(mine).keyword?(:first_strike), e.power(game.state.object(mine))]).to eq([true, 3])
      game.submit(type: "pass") until game.pending_decision.kind == "declare_blockers"
      game.submit(type: "block", object: theirs, attacker: mine)
      game.submit(type: "done") if option_types(game).include?("done")
      expect(e.toughness(game.state.object(theirs))).to eq(2) # blocking now
      skip_to(game, :end_of_combat)
      expect(game.state.battlefield).not_to include(theirs) # first strike 3 damage killed the 2/2 blocker first
      skip_to(game, :postcombat_main)
      expect([e.chars(mine).keyword?(:first_strike), e.power(game.state.object(mine))]).to eq([false, 2])
    end

    it "an Equipment's static with an `if` on the equipped creature attacking" do
      game = board(battlefield: ["Spec Duel Blade", "Grizzly Bears"], step: :beginning_of_combat)
      blade = obj_id(game, "Spec Duel Blade")
      bears = obj_id(game, "Grizzly Bears")
      game.state.object(blade).attached_to = bears
      engine(game).touch!
      expect(engine(game).chars(bears).keyword?(:first_strike)).to be(false)
      game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
      game.submit(type: "attack", object: bears, target: "player:bob")
      game.submit(type: "done") if option_types(game).include?("done")
      expect(engine(game).chars(bears).keyword?(:first_strike)).to be(true)
    end

    it "still refuses power in a static's filter" do
      errors = []
      Enjine::Mechanics.build_entry(:ability, { "static" => { "affects" => { "each" => { "creature" => { "power" => { "at_least" => 2 },
                                                                                                         "attacking" => true } } },
                                                              "keywords" => ["flying"] } }, errors, "x")
      expect(errors).to eq(["x.static.affects.each: power can't be used in a static ability yet"])
    end
  end
end
