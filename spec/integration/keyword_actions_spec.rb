# frozen_string_literal: true

# Keyword actions and keyword abilities written as card data: blight (CR 701.68), connive (CR 701.50),
# recruit (CR 701.70), amass (CR 701.47), empower Jace (CR 701.71), endure (CR 701.63), job select
# (CR 702.182), mobilize (CR 702.181), firebending (CR 702.189) and the kindred card type (CR 308).
RSpec.describe "Keyword actions and abilities from Standard sets" do
  def spell(name, effects, cost: "{1}", targets: [], types: ["sorcery"], extra: [])
    { "name" => name, "mana_cost" => cost, "types" => types,
      "abilities" => extra + [{ "spell" => { "targets" => targets, "effects" => effects } }] }
  end

  def creature(name, abilities, power: 2, toughness: 2, cost: "{2}")
    { "name" => name, "mana_cost" => cost, "types" => ["creature"], "power" => power, "toughness" => toughness,
      "abilities" => abilities }
  end

  def etb(*effects) = { "triggered" => { "when" => { "enters" => {} }, "effects" => effects } }

  let(:cards) do
    [
      spell("Spec Blight Bolt", [{ "deal_damage" => { "amount" => 3, "to" => { "target" => 0 } } }],
            targets: ["any_target"], extra: [{ "additional_cost" => { "cost" => [{ "blight" => { "amount" => 1 } }] } }]),
      spell("Spec Wither Pact", [{ "may" => { "effects" => [{ "blight" => { "amount" => 2 } }],
                                              "then" => [{ "draw" => { "amount" => 1 } }] } }]),
      spell("Spec Hex Rite", [{ "blight" => { "amount" => 1, "to" => "each_opponent" } }]),
      creature("Spec Sly Agent", [etb({ "connive" => {} })]),
      spell("Spec Deep Scheme", [{ "connive" => { "amount" => 2, "to" => { "target" => 0 } } }],
            targets: [{ "creature" => { "controller" => "you" } }]),
      spell("Spec Muster Call", [{ "recruit" => {} }]),
      spell("Spec Horde Call", [{ "amass" => { "subtype" => "orc", "amount" => 2 } }]),
      spell("Spec Mind Surge", [{ "empower_jace" => { "amount" => 2 } }]),
      creature("Spec Stout Guard", [etb({ "endure" => { "amount" => 2 } })]),
      { "name" => "Spec Hero Blade", "mana_cost" => "{1}", "types" => ["artifact"], "subtypes" => ["equipment"],
        "keywords" => ["job_select"],
        "abilities" => [{ "static" => { "affects" => "attached", "pump" => { "power" => 1, "toughness" => 0 } } },
                        { "equip" => { "cost" => [{ "mana" => "{1}" }] } }] },
      creature("Spec Rally Captain", [{ "mobilize" => { "amount" => 2 } }]),
      creature("Spec Ember Adept", [{ "firebending" => { "amount" => { "power" => "self" } } }], power: 3, toughness: 1),
      spell("Spec Goblin Gambit", [{ "deal_damage" => { "amount" => 1, "to" => { "target" => 0 } } }],
            targets: ["any_target"], types: %w[kindred instant], cost: "{R}").merge("subtypes" => ["goblin"]),
      spell("Spec Fire Sprint", [{ "draw" => { "amount" => 1 } }], cost: "{R}{R}{R}", types: ["instant"]),
      spell("Spec Horde Rally", [{ "amass" => { "subtype" => "orc", "amount" => 1 } },
                                 { "pump" => { "power" => 3, "toughness" => 0, "to" => { "result" => 0 } } }]),
      creature("Spec Grim Tinker", [{ "activated" => { "cost" => ["tap", { "blight" => { "amount" => 1 } }],
                                                       "effects" => [{ "draw" => { "amount" => 1 } }] } }])
    ]
  end
  let(:catalog) { catalog_with(*cards) }

  def board(hand: [], field: [], bob_field: [], pool: { C: 5 }, step: :precombat_main, library: 6)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: pool) do
        hand(*hand) unless hand.empty?
        field.each { |entry| entry.is_a?(Array) ? battlefield(entry[0], **entry[1]) : battlefield(entry) }
        library "Forest", "Grizzly Bears", count: library / 2
      end
      player("bob") do
        battlefield(*bob_field) unless bob_field.empty?
        library "Forest", count: 5
      end
    end
  end

  def cast(game, card, target: nil)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) })
    game.submit(type: "target", target: target) if target
  end

  def pay(game)
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
  end

  def resolve(game) = pass_both(game)
  def counters(game, card) = game.state.object(obj_id(game, card)).counters
  def tokens(game, name) = game.state.battlefield.select { game.catalog.fetch(game.state.object(it).card).name == name }

  describe "blight (CR 701.68)" do
    it "as an additional cost puts -1/-1 counters on a chosen creature as the spell becomes cast" do
      game = board(hand: ["Spec Blight Bolt"], field: ["Hill Giant", "Grizzly Bears"])
      cast(game, "Spec Blight Bolt", target: "player:bob")
      expect(game.pending_decision.kind).to eq("choose_cost")
      giant = obj_id(game, "Hill Giant")
      game.submit(type: "cost", object: giant)
      pay(game)
      expect(counters(game, "Hill Giant")).to eq("-1/-1" => 1)
      expect(game.state.object(game.state.stack.first).paid.first).to include("object" => giant)
    end

    it "as an activated ability's cost (CR 602.2b)" do
      game = board(field: ["Spec Grim Tinker"])
      tinker = obj_id(game, "Spec Grim Tinker")
      game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == tinker })
      expect(game.legal_options).to include({ type: "cost", object: tinker })
      game.submit(type: "cost", object: tinker)
      expect(counters(game, "Spec Grim Tinker")).to eq("-1/-1" => 1)
      resolve(game)
      expect(ids_in(game, "alice", :hand).size).to eq(1)
    end

    it "can't be paid without a creature (CR 701.68b, 118.3)" do
      game = board(hand: ["Spec Blight Bolt"])
      expect(option_types(game)).not_to include("cast")
    end

    it "as an effect: the controller chooses; in a may, yes needs a creature" do
      game = board(hand: ["Spec Wither Pact"], field: ["Hill Giant"])
      cast(game, "Spec Wither Pact")
      pay(game)
      resolve(game)
      expect(game.legal_options).to eq([{ type: "yes" }, { type: "no" }])
      game.submit(type: "yes")
      giant = obj_id(game, "Hill Giant")
      expect(game.legal_options).to eq([{ type: "blight", object: giant }])
      game.submit(type: "blight", object: giant)
      expect(counters(game, "Hill Giant")).to eq("-1/-1" => 2)
      expect(ids_in(game, "alice", :hand).size).to eq(1)

      game = board(hand: ["Spec Wither Pact"])
      cast(game, "Spec Wither Pact")
      pay(game)
      resolve(game)
      expect(game.legal_options).to eq([{ type: "no" }])
    end

    it "each opponent blights; one without creatures doesn't" do
      game = board(hand: ["Spec Hex Rite"], bob_field: ["Grizzly Bears", "Hill Giant"])
      cast(game, "Spec Hex Rite")
      pay(game)
      resolve(game)
      expect(game.pending_decision.player).to eq("bob")
      game.submit(type: "blight", object: obj_id(game, "Hill Giant"))
      expect(counters(game, "Hill Giant")).to eq("-1/-1" => 1)

      game = board(hand: ["Spec Hex Rite"])
      cast(game, "Spec Hex Rite")
      pay(game)
      resolve(game)
      expect(game.pending_decision.kind).to eq("priority")
    end
  end

  describe "connive (CR 701.50)" do
    it "draws, discards, and gets a +1/+1 counter for a nonland card discarded" do
      game = board(hand: ["Spec Sly Agent", "Forest"])
      cast(game, "Spec Sly Agent")
      pay(game)
      resolve(game) # the creature
      resolve(game) # its trigger
      expect(game.pending_decision.kind).to eq("effect_choice")
      bears = ids_in(game, "alice", :hand).find { game.state.object(it).card == "grizzly_bears" } ||
              ids_in(game, "alice", :hand).last
      nonland = game.catalog.fetch(game.state.object(bears).card).land? ? 0 : 1
      game.submit(type: "discard", object: bears)
      expect(counters(game, "Spec Sly Agent").fetch("+1/+1", 0)).to eq(nonland)
    end

    it "connive N discards N and counts only nonland cards (CR 701.50d)" do
      game = board(hand: ["Spec Deep Scheme"], field: ["Hill Giant"], library: 2)
      cast(game, "Spec Deep Scheme", target: obj_id(game, "Hill Giant"))
      pay(game)
      resolve(game)
      hand = ids_in(game, "alice", :hand).dup
      expect(hand.size).to eq(2)
      hand.each { game.submit(type: "discard", object: it) }
      expect(counters(game, "Hill Giant")).to eq("+1/+1" => 1) # a Forest and a Grizzly Bears
    end

    it "a conniving permanent that left still loots, without counters (CR 701.50b)" do
      game = board(hand: ["Spec Deep Scheme"], field: ["Hill Giant"], library: 2)
      cast(game, "Spec Deep Scheme", target: obj_id(game, "Hill Giant"))
      pay(game)
      giant = obj_id(game, "Hill Giant")
      game.state.object(game.state.stack.first).targets = [giant]
      engine = game.instance_variable_get(:@engine)
      effect = game.catalog.fetch("spec_deep_scheme").spell_ability.effects.first
      ctx = Enjine::Mechanics::EffectContext.new(0, nil, nil, [giant], [], [])
      engine.move!(giant, :graveyard, reason: "destroy")
      expect(effect.send(:loot_queue, engine, ctx)).to eq([])
    end
  end

  describe "recruit (CR 701.70)" do
    it "creates a 1/1 Human Soldier only if a nonland card was discarded" do
      { "Grizzly Bears" => 1, "Forest" => 0 }.each do |discard, made|
        game = board(hand: ["Spec Muster Call", discard], library: 2)
        cast(game, "Spec Muster Call")
        pay(game)
        resolve(game)
        card = ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(discard) }
        game.submit(type: "discard", object: card)
        expect(tokens(game, "Human Soldier").size).to eq(made), discard
      end
    end
  end

  describe "amass (CR 701.47) and empower Jace (CR 701.71)" do
    it "creates a 0/0 Orc Army with counters, then grows the one you control" do
      game = board(hand: ["Spec Horde Call", "Spec Horde Call"])
      2.times do
        cast(game, "Spec Horde Call")
        pay(game)
        resolve(game)
      end
      army = tokens(game, "Orc Army")
      expect(army.size).to eq(1)
      expect(game.state.object(army.first).counters).to eq("+1/+1" => 4)
      expect(view_of(game, army.first)).to include("power" => 4, "toughness" => 4)
    end

    it "asks which Army when there are several, and it becomes the amassed subtype (CR 701.47a)" do
      zombie_army = { "name" => "Spec Zombie Army", "mana_cost" => "{1}", "types" => ["creature"],
                      "subtypes" => %w[zombie army], "power" => 1, "toughness" => 1 }
      game = build_game(catalog_with(*cards, zombie_army)) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { C: 1 }) do
          hand "Spec Horde Call"
          battlefield "Spec Zombie Army", count: 2
          library "Forest", count: 3
        end
        player("bob") { library "Forest", count: 3 }
      end
      cast(game, "Spec Horde Call")
      pay(game)
      resolve(game)
      first = game.legal_options.first[:object]
      expect(game.legal_options.size).to eq(2)
      game.submit(type: "choose", object: first)
      expect(game.state.object(first).counters).to eq("+1/+1" => 2)
      expect(game.instance_variable_get(:@engine).chars(first).subtypes).to include(:orc, :zombie)
    end

    it "the amassed Army is the effect's result, whether it was created or already there (CR 701.47c)" do
      game = board(hand: ["Spec Horde Rally", "Spec Horde Rally"])
      2.times do
        cast(game, "Spec Horde Rally")
        pay(game)
        resolve(game)
      end
      army = tokens(game, "Orc Army").first
      expect(view_of(game, army)).to include("power" => 8, "toughness" => 2)
    end

    it "creates a Jace planeswalker token with loyalty counters, and empowers it again" do
      game = board(hand: ["Spec Mind Surge", "Spec Mind Surge"])
      cast(game, "Spec Mind Surge")
      pay(game)
      resolve(game)
      jace = tokens(game, "Jace")
      expect(jace.size).to eq(1)
      expect(game.state.object(jace.first).counters).to eq("loyalty" => 2)
      cast(game, "Spec Mind Surge")
      pay(game)
      resolve(game)
      expect(game.state.object(jace.first).counters).to eq("loyalty" => 4)
      expect(game.legal_options.map { it[:type] }).to include("activate")
    end
  end

  describe "endure (CR 701.63)" do
    it "puts N +1/+1 counters on it, or creates an N/N Spirit" do
      { "counters" => [{ "+1/+1" => 2 }, 0], "spirit" => [{}, 1] }.each do |choice, (want, spirits)|
        game = board(hand: ["Spec Stout Guard"])
        cast(game, "Spec Stout Guard")
        pay(game)
        resolve(game)
        resolve(game)
        game.submit(game.legal_options.find { it[:type] == choice })
        expect(counters(game, "Spec Stout Guard")).to eq(want)
        expect(tokens(game, "Spirit").size).to eq(spirits)
        expect(view_of(game, tokens(game, "Spirit").first)).to include("power" => 2, "toughness" => 2) if spirits == 1
      end
    end
  end

  describe "job select (CR 702.182)" do
    it "creates a 1/1 Hero and attaches the Equipment to it" do
      game = board(hand: ["Spec Hero Blade"])
      cast(game, "Spec Hero Blade")
      pay(game)
      resolve(game)
      resolve(game)
      hero = tokens(game, "Hero").first
      expect(game.state.object(obj_id(game, "Spec Hero Blade")).attached_to).to eq(hero)
      expect(view_of(game, hero)).to include("power" => 2, "toughness" => 1)
    end
  end

  describe "mobilize (CR 702.181) and firebending (CR 702.189)" do
    def attack(game, *cards)
      pass_both(game) # -> declare attackers
      cards.each { game.submit(type: "attack", object: obj_id(game, it), target: "player:bob") }
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
    end

    it "mobilize creates tapped attacking Warriors, sacrificed at the next end step" do
      game = board(field: ["Spec Rally Captain"], step: :beginning_of_combat, pool: {})
      attack(game, "Spec Rally Captain")
      resolve(game)
      warriors = tokens(game, "Warrior")
      expect(warriors.size).to eq(2)
      expect(warriors.map { game.state.object(it).tapped }).to all(be(true))
      expect(game.state.attackers.keys).to include(*warriors)
      skip_to(game, :end)
      resolve(game)
      expect(tokens(game, "Warrior")).to be_empty
    end

    it "firebending adds {R} that lasts until end of combat" do
      game = board(field: ["Spec Ember Adept"], hand: ["Spec Fire Sprint"], step: :beginning_of_combat, pool: {})
      attack(game, "Spec Ember Adept")
      resolve(game)
      pool = game.state.players[0].restricted_mana
      expect(pool).to eq([{ "mana" => "R", "until" => "end_of_combat" }] * 3)
      expect(game.view_for("alice")["players"][0]["restricted_mana"].first["text"]).to include("until end of combat")
      pass_both(game) # declare attackers ends; the mana stays
      expect(game.state.players[0].restricted_mana.size).to eq(3)
      copy = Enjine::Game.import(game.export, catalog: catalog)
      expect(copy.state.players[0].restricted_mana.size).to eq(3)
      cast(game, "Spec Fire Sprint")
      pay(game)
      expect(game.state.players[0].restricted_mana).to be_empty
    end

    it "firebending mana empties as combat ends, and the rules monitor agrees (CR 500.5)" do
      game = board(field: ["Spec Ember Adept"], step: :beginning_of_combat, pool: {})
      monitor = Enjine::RulesMonitor.new(game)
      attack(game, "Spec Ember Adept")
      resolve(game)
      until game.step == :postcombat_main
        option = option_types(game).include?("pass") ? { type: "pass" } : game.legal_options.first
        monitor.check!(game.submit(option))
        expect(game.state.players[0].restricted_mana.size).to eq(3) unless game.step == :postcombat_main
      end
      expect(game.state.players[0].restricted_mana).to be_empty
      expect(monitor.findings).to eq([])
    end
  end

  describe "kindred (CR 308)" do
    it "casts as its other type, and its subtypes are creature types" do
      game = board(hand: ["Spec Goblin Gambit"], pool: { R: 1 })
      cast(game, "Spec Goblin Gambit", target: "player:bob")
      pay(game)
      expect(game.state.stack.size).to eq(1)
      chars = game.instance_variable_get(:@engine).chars(game.state.stack.first)
      expect(Enjine::Mechanics::Amount.creature_types(chars)).to eq([:goblin])
      resolve(game)
      expect(game.state.players[1].life).to eq(19)
    end
  end
end
