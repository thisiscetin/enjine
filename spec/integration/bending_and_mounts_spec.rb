# frozen_string_literal: true

# Avatar bending and mount/body keywords written as card data: earthbend (CR 701.66), waterbend (CR 701.67),
# airbend (CR 701.65), saddle (CR 702.171), exert (CR 701.43), decayed (CR 702.147) and wither (CR 702.80).
RSpec.describe "Bending, mounts and body keywords" do
  def spell(name, effects, cost: "{1}", targets: [], types: ["sorcery"], extra: [])
    { "name" => name, "mana_cost" => cost, "types" => types,
      "abilities" => extra + [{ "spell" => { "targets" => targets, "effects" => effects } }] }
  end

  def creature(name, abilities, power: 2, toughness: 2, cost: "{2}", keywords: [], subtypes: [], extra_keys: {})
    { "name" => name, "mana_cost" => cost, "types" => ["creature"], "power" => power, "toughness" => toughness,
      "keywords" => keywords, "subtypes" => subtypes, "abilities" => abilities }.merge(extra_keys)
  end

  def land_you_control = { "land" => { "controller" => "you" } }
  def draw(n = 1) = { "draw" => { "amount" => n } }

  let(:cards) do
    [
      spell("Spec Earth Lesson", [{ "earthbend" => { "amount" => 3, "to" => { "target" => 0 } } }],
            targets: [land_you_control]),
      spell("Spec Island Shaping", [{ "earthbend" => { "amount" => { "count" => { "each" => "land", "controller" => "you" } },
                                                       "to" => { "target" => 0 } } },
                                    { "become" => { "subtypes" => ["island"], "duration" => "indefinite",
                                                    "to" => { "result" => 0 } } }],
            targets: [land_you_control]),
      creature("Spec Earth Watcher", [{ "triggered" => { "when" => { "earthbends" => {} },
                                                         "effects" => [{ "gain_life" => { "amount" => 1 } }] } }]),
      creature("Spec Geyser Diver", [{ "activated" => { "cost" => [{ "waterbend" => "{3}" }], "effects" => [draw] } }]),
      creature("Spec Tide Sentry", [{ "activated" => { "cost" => [{ "waterbend" => "{1}" }, "tap"],
                                                       "effects" => [draw] } }]),
      creature("Spec River Spirit", [], cost: "{U}", extra_keys: { "abilities" => [
                 { "additional_cost" => { "cost" => [{ "waterbend" => "{2}" }] } }
               ] }),
      spell("Spec Revival Tide", [{ "draw" => { "amount" => 1, "if" => { "not" => { "cast_with" => "additional_cost" } } } },
                                  { "draw" => { "amount" => 3, "if" => { "cast_with" => "additional_cost" } } }],
            cost: "{U}", extra: [{ "additional_cost" => { "cost" => [{ "waterbend" => "{2}" }], "optional" => true } }]),
      spell("Spec Water Lesson", [draw(2), { "pay" => { "waterbend" => "{2}", "otherwise" => [{ "discard" => { "amount" => 1 } }] } }],
            cost: "{U}"),
      { "name" => "Spec Trinket", "mana_cost" => "{1}", "types" => ["artifact"] },
      creature("Spec Water Watcher", [{ "triggered" => { "when" => { "waterbends" => {} },
                                                         "effects" => [{ "gain_life" => { "amount" => 1 } }] } }]),
      creature("Spec Trail Lynx", [{ "saddle" => { "power" => 3 } },
                                   { "triggered" => { "when" => { "attacks" => {} },
                                                      "while" => { "source" => { "creature" => { "saddled" => true } } },
                                                      "effects" => [draw] } },
                                   { "triggered" => { "when" => { "becomes_saddled" => {} },
                                                      "effects" => [{ "gain_life" => { "amount" => { "triggering" => "amount" } } }] } }],
               subtypes: %w[cat mount]),
      creature("Spec Eager Rider", [{ "triggered" => { "when" => { "saddles_mount" => {} },
                                                       "effects" => [{ "pump" => { "power" => 2, "toughness" => 0,
                                                                                   "to" => { "triggering" => "object" } } }] } }],
               power: 1, toughness: 1, subtypes: ["pilot"]),
      { "name" => "Spec Saddle Rack", "mana_cost" => "{2}", "types" => ["artifact"],
        "abilities" => [{ "activated" => { "cost" => ["tap"], "timing" => "sorcery",
                                           "targets" => [{ "creature" => { "subtypes" => ["mount"], "controller" => "you" } }],
                                           "effects" => [{ "become_saddled" => { "to" => { "target" => 0 } } }] } }] },
      spell("Spec Air Lesson", [{ "airbend" => { "to" => { "target" => 0 } } }, draw],
            targets: [{ "permanent" => { "not" => ["land"] } }], types: ["instant"], cost: "{W}"),
      spell("Spec Gust Rebuke", [{ "airbend" => { "to" => { "target" => 0 } } }],
            targets: [{ "one_of" => %w[creature spell] }], types: ["instant"], cost: "{W}"),
      creature("Spec Air Watcher", [{ "triggered" => { "when" => { "airbends" => { "controller" => "any" } },
                                                       "effects" => [{ "gain_life" => { "amount" => 1 } }] } }]),
      creature("Spec Thorn Wyrm", [], power: 2, toughness: 4, keywords: ["wither"]),
      creature("Spec Kyoshi Serpent", [{ "ward" => { "waterbend" => "{2}" } }], power: 5, toughness: 5),
      spell("Spec Exile Rite", [{ "exile" => { "to" => { "target" => 0 } } }], targets: ["creature"], types: ["instant"]),
      spell("Spec Thorn Burst", [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }],
            targets: ["any_target"], types: ["instant"], cost: "{R}").merge("keywords" => ["wither"]),
      creature("Spec Rot Hulk", [], power: 5, toughness: 5, keywords: %w[decayed trample]),
      spell("Spec Rot Renewal", [{ "add_counters" => { "counter" => "decayed", "amount" => 1, "to" => { "target" => 0 } } }],
            targets: ["creature"]),
      creature("Spec Weary Knight", [{ "activated" => { "cost" => %w[tap exert], "effects" => [draw] } }],
               power: 2, toughness: 1),
      creature("Spec Ember Pupil", [{ "firebending" => { "amount" => 1 } },
                                    { "triggered" => { "when" => { "firebends" => {} },
                                                       "effects" => [{ "gain_life" => { "amount" => 1 } }] } }])
    ]
  end
  let(:catalog) { catalog_with(*cards) }

  def board(hand: [], field: [], bob_field: [], pool: { C: 5 }, step: :precombat_main)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice", mana_pool: pool) do
        hand(*hand) unless hand.empty?
        field.each { |entry| entry.is_a?(Array) ? battlefield(entry[0], **entry[1]) : battlefield(entry) }
        library "Forest", "Grizzly Bears", count: 3
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

  def chars(game, id) = game.instance_variable_get(:@engine).chars(game.state.object(id))
  def mine(game, card) = game.state.battlefield.select { game.state.object(it).card == card && game.state.object(it).controller.zero? }

  describe "earthbend (CR 701.66)" do
    it "makes the target land a 0/0 haste creature with N +1/+1 counters that's still a land (CR 701.66a)" do
      game = board(hand: ["Spec Earth Lesson"], field: ["Forest"])
      forest = obj_id(game, "Forest")
      cast(game, "Spec Earth Lesson", target: forest)
      pay(game)
      pass_both(game)
      c = chars(game, forest)
      expect(c.types).to include(:land, :creature)
      expect(c.keyword?(:haste)).to be(true)
      expect([c.power, c.toughness]).to eq([3, 3])
      expect(game.state.object(forest).counters).to eq("+1/+1" => 3)
    end

    it "returns the land tapped under your control when it dies (CR 701.66a, 603.7c)" do
      game = board(hand: ["Spec Earth Lesson", "Lightning Bolt"], field: ["Forest"], pool: { R: 2 })
      forest = obj_id(game, "Forest")
      cast(game, "Spec Earth Lesson", target: forest)
      pay(game)
      pass_both(game)
      cast(game, "Lightning Bolt")
      game.submit(type: "target", target: forest)
      pay(game)
      pass_both(game) # Bolt resolves: the 3/3 land dies
      pass_both(game) # the delayed trigger resolves
      back = mine(game, "forest").first
      expect(back).not_to be_nil
      expect(back).not_to eq(forest)
      expect(game.state.object(back).tapped).to be(true)
      expect(chars(game, back).creature?).to be(false)
      expect(ids_in(game, "alice", :graveyard).map { game.state.object(it).card }).not_to include("forest")
    end

    it "returns the land tapped when it's put into exile (CR 701.66a)" do
      game = board(hand: ["Spec Earth Lesson", "Spec Exile Rite"], field: ["Forest"], pool: { C: 2 })
      forest = obj_id(game, "Forest")
      cast(game, "Spec Earth Lesson", target: forest)
      pay(game)
      pass_both(game)
      cast(game, "Spec Exile Rite", target: forest)
      pay(game)
      pass_both(game)
      pass_both(game)
      back = mine(game, "forest").first
      expect(game.state.object(back).tapped).to be(true)
      expect(game.state.exile).to be_empty
    end

    it "names the land as its result and counts as earthbending (CR 701.66b)" do
      game = board(hand: ["Spec Island Shaping"], field: ["Forest", "Forest", "Spec Earth Watcher"])
      forest = mine(game, "forest").first
      cast(game, "Spec Island Shaping", target: forest)
      pay(game)
      pass_both(game)
      expect(game.state.object(forest).counters).to eq("+1/+1" => 2)
      expect(chars(game, forest).subtypes).to include(:island, :forest)
      pass_both(game) # the earthbends trigger
      expect(game.state.players[0].life).to eq(21)
    end
  end

  describe "waterbend (CR 701.67)" do
    def activate(game, card)
      id = obj_id(game, card)
      game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == id })
    end

    def waterbend_options(game) = game.legal_options.select { it[:type] == "waterbend" }

    it "pays each generic mana of the cost by tapping an untapped artifact or creature (CR 701.67a)" do
      game = board(field: ["Spec Geyser Diver", "Spec Trinket", "Grizzly Bears", "Forest"], pool: {})
      activate(game, "Spec Geyser Diver")
      expect(game.pending_decision.kind).to eq("pay_cost")
      expect(waterbend_options(game).map { it[:object] })
        .to contain_exactly(obj_id(game, "Spec Geyser Diver"), obj_id(game, "Spec Trinket"), obj_id(game, "Grizzly Bears"))
      game.submit(type: "waterbend", object: obj_id(game, "Spec Trinket"))
      game.submit(type: "waterbend", object: obj_id(game, "Grizzly Bears"))
      expect(game.state.object(obj_id(game, "Spec Trinket")).tapped).to be(true)
      game.submit(type: "activate_mana", object: obj_id(game, "Forest"), ability: mana_ref(game, obj_id(game, "Forest")))
      game.submit(game.legal_options.find { it[:type] == "pay_mana" })
      expect(game.state.stack.size).to eq(1)
    end

    it "is affordable with tappable permanents alone, and cancelling untaps them (CR 734.1)" do
      game = board(field: ["Spec Geyser Diver", "Spec Trinket", "Grizzly Bears"], pool: {})
      expect(game.legal_options).to include(a_hash_including(type: "activate", object: obj_id(game, "Spec Geyser Diver")))
      activate(game, "Spec Geyser Diver")
      game.submit(type: "waterbend", object: obj_id(game, "Spec Trinket"))
      game.submit(type: "cancel")
      expect(game.state.object(obj_id(game, "Spec Trinket")).tapped).to be(false)
    end

    it "can't be paid by tapping when there is too little to tap" do
      game = board(field: ["Spec Geyser Diver", "Spec Trinket"], pool: {})
      expect(game.legal_options).not_to include(a_hash_including(type: "activate"))
    end

    it "doesn't let the {T} ability's own source pay, and pays only the waterbend part (CR 701.67b)" do
      game = board(hand: ["Spec River Spirit"], field: ["Spec Tide Sentry", "Spec Trinket", "Grizzly Bears", "Hill Giant"],
                   pool: { U: 1 })
      activate(game, "Spec Tide Sentry")
      expect(waterbend_options(game).map { it[:object] }).not_to include(obj_id(game, "Spec Tide Sentry"))
      game.submit(type: "cancel")
      cast(game, "Spec River Spirit") # {U} plus waterbend {2}
      game.submit(type: "waterbend", object: obj_id(game, "Spec Trinket"))
      game.submit(type: "waterbend", object: obj_id(game, "Grizzly Bears"))
      expect(waterbend_options(game)).to be_empty
      pay(game)
      expect(game.state.stack.size).to eq(1)
    end

    it "as an optional additional cost: the spell knows it was paid but isn't kicked; waterbending triggers (CR 118.8b, 701.67c)" do
      game = board(hand: ["Spec Revival Tide"], field: ["Spec Water Watcher", "Spec Trinket", "Grizzly Bears"], pool: { U: 1 })
      cast(game, "Spec Revival Tide")
      game.submit(type: "kick")
      expect(game.state.object(game.state.stack.first).memory).to eq("kicked_with" => "additional_cost")
      game.submit(type: "waterbend", object: obj_id(game, "Spec Trinket"))
      game.submit(type: "waterbend", object: obj_id(game, "Grizzly Bears"))
      pay(game)
      pass_both(game) # the waterbends trigger
      expect(game.state.players[0].life).to eq(21)
      pass_both(game)
      expect(ids_in(game, "alice", :hand).size).to eq(3)
    end

    it "while resolving: \"discard a card unless you waterbend {2}\" (CR 118.12, 701.67a)" do
      game = board(hand: ["Spec Water Lesson"], field: ["Spec Trinket", "Grizzly Bears"], pool: { U: 1 })
      cast(game, "Spec Water Lesson")
      pay(game)
      pass_both(game)
      game.submit(type: "pay")
      expect(game.pending_decision.kind).to eq("pay_cost")
      game.submit(type: "waterbend", object: obj_id(game, "Spec Trinket"))
      game.submit(type: "waterbend", object: obj_id(game, "Grizzly Bears"))
      expect(ids_in(game, "alice", :hand).size).to eq(2)
      expect(game.state.stack).to be_empty
    end
  end

  describe "waterbend costs paid while resolving (CR 118.12)" do
    it "ward—waterbend: the targeting player may tap artifacts and creatures to pay it (CR 702.21a, 701.67a)" do
      game = board(hand: ["Lightning Bolt"], field: ["Spec Trinket", "Grizzly Bears"], bob_field: ["Spec Kyoshi Serpent"],
                   pool: { R: 1 })
      serpent = obj_id(game, "Spec Kyoshi Serpent")
      cast(game, "Lightning Bolt", target: serpent)
      pay(game)
      pass_both(game) # ward resolves
      expect(game.pending_decision.kind).to eq("effect_choice")
      game.submit(type: "pay")
      game.submit(type: "waterbend", object: obj_id(game, "Spec Trinket"))
      game.submit(type: "waterbend", object: obj_id(game, "Grizzly Bears"))
      pass_both(game)
      expect(game.state.object(serpent).damage).to eq(3)
    end
  end

  describe "saddle (CR 702.171)" do
    def saddle(game, *riders)
      lynx = obj_id(game, "Spec Trail Lynx")
      game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == lynx })
      riders.each { game.submit(type: "cost", object: obj_id(game, it)) }
      game.submit(type: "done") if game.legal_options.include?({ type: "done" })
    end

    def attack(game, *cards)
      skip_to(game, :beginning_of_combat)
      pass_both(game) # -> declare attackers
      cards.each { game.submit(type: "attack", object: obj_id(game, it), target: "player:bob") }
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
    end

    def saddled?(game, card) = game.instance_variable_get(:@engine).saddled?(game.state.object(obj_id(game, card)))

    it "taps other creatures with total power N or more; the Mount becomes saddled until end of turn (CR 702.171a-c)" do
      game = board(field: ["Spec Trail Lynx", "Spec Eager Rider", "Grizzly Bears"], pool: {})
      lynx = obj_id(game, "Spec Trail Lynx")
      saddle(game, "Spec Eager Rider")
      expect(game.legal_options).not_to include(a_hash_including(type: "done"))
      expect(game.legal_options.map { it[:object] }).not_to include(lynx)
      game.submit(type: "cost", object: obj_id(game, "Grizzly Bears"))
      game.submit(type: "done") if game.legal_options.include?({ type: "done" })
      pass_both(game) # the rider's saddles trigger
      expect(chars(game, lynx).power).to eq(4)
      pass_both(game) # the saddle ability
      expect(saddled?(game, "Spec Trail Lynx")).to be(true)
      pass_both(game) # becomes saddled: gain 2 (two riders)
      expect(game.state.players[0].life).to eq(22)
      copy = Enjine::Game.import(game.export, catalog: catalog)
      expect(saddled?(copy, "Spec Trail Lynx")).to be(true)
      attack(game, "Spec Trail Lynx")
      pass_both(game)
      expect(ids_in(game, "alice", :hand).size).to eq(1)
      skip_to(game, :upkeep, turn: 4)
      expect(saddled?(game, "Spec Trail Lynx")).to be(false)
    end

    it "is sorcery speed, and an unsaddled Mount's attack doesn't trigger" do
      game = board(field: ["Spec Trail Lynx", "Hill Giant"], pool: {}, step: :beginning_of_combat)
      expect(game.legal_options).not_to include(a_hash_including(type: "activate"))
      attack(game, "Spec Trail Lynx")
      expect(game.state.stack).to be_empty
    end

    it "other effects saddle a Mount; the filter sees it" do
      game = board(field: ["Spec Trail Lynx", "Spec Saddle Rack"], pool: {})
      rack = obj_id(game, "Spec Saddle Rack")
      game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == rack })
      game.submit(type: "target", target: obj_id(game, "Spec Trail Lynx")) if game.pending_decision.kind == "choose_target"
      pass_both(game)
      expect(saddled?(game, "Spec Trail Lynx")).to be(true)
    end
  end

  describe "airbend (CR 701.65)" do
    it "exiles the permanent; its owner may cast it for {2} rather than its mana cost (CR 701.65a, 118.9)" do
      game = board(hand: ["Spec Air Lesson"], bob_field: ["Hill Giant", "Forest", "Forest"], field: ["Spec Air Watcher"],
                   pool: { W: 1 })
      giant = obj_id(game, "Hill Giant")
      cast(game, "Spec Air Lesson", target: giant)
      pay(game)
      pass_both(game)
      exiled = game.state.exile.find { game.state.object(it).card == "hill_giant" }
      expect(exiled).not_to be_nil
      expect(ids_in(game, "alice", :hand).size).to eq(1) # drew
      pass_both(game) # the airbends trigger
      expect(game.state.players[0].life).to eq(21)
      skip_to(game, :precombat_main, turn: 4)
      option = game.legal_options.find { it[:type] == "cast" && it[:object] == exiled }
      expect(option).not_to be_nil
      game.submit(option)
      expect(game.pending_decision.kind).to eq("pay_cost")
      game.state.battlefield.select { game.state.object(it).card == "forest" }.each do |land|
        game.submit(type: "activate_mana", object: land, ability: mana_ref(game, land))
      end
      pay(game)
      expect(game.state.stack.size).to eq(1)
      pass_both(game)
      expect(game.state.battlefield.map { game.state.object(it).card }).to include("hill_giant")
    end

    it "exiles a spell from the stack, which its owner may cast again for {2}" do
      game = board(hand: ["Lightning Bolt", "Spec Gust Rebuke"], pool: { R: 1, W: 1, C: 2 })
      cast(game, "Lightning Bolt", target: "player:bob")
      game.submit(type: "pay_mana", mana: "R")
      bolt = game.state.stack.first
      cast(game, "Spec Gust Rebuke", target: bolt)
      game.submit(type: "pay_mana", mana: "W")
      pass_both(game)
      exiled = game.state.exile.find { game.state.object(it).card == "lightning_bolt" }
      expect(game.state.stack).to be_empty
      game.submit(type: "cast", object: exiled, via: game.legal_options.find { it[:object] == exiled }[:via])
      game.submit(type: "target", target: "player:bob")
      pay(game)
      pass_both(game)
      expect(game.state.players[1].life).to eq(17)
    end
  end

  describe "wither (CR 702.80)" do
    it "deals damage to creatures as -1/-1 counters, and to players as usual (CR 702.80a, 120.3d)" do
      game = board(hand: ["Spec Thorn Burst", "Spec Thorn Burst"], bob_field: ["Hill Giant"], pool: { R: 2 })
      giant = obj_id(game, "Hill Giant")
      cast(game, "Spec Thorn Burst", target: giant)
      pay(game)
      pass_both(game)
      expect(game.state.object(giant).counters).to eq("-1/-1" => 2)
      expect(game.state.object(giant).damage).to eq(0)
      cast(game, "Spec Thorn Burst", target: "player:bob")
      pay(game)
      pass_both(game)
      expect(game.state.players[1].life).to eq(18)
    end

    it "in combat: the blocker gets -1/-1 counters (CR 510.2, 702.80c)" do
      game = board(field: ["Spec Thorn Wyrm"], bob_field: ["Hill Giant"], pool: {}, step: :beginning_of_combat)
      giant = obj_id(game, "Hill Giant")
      pass_both(game)
      game.submit(type: "attack", object: obj_id(game, "Spec Thorn Wyrm"), target: "player:bob")
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
      pass_both(game)
      game.submit(type: "block", object: giant, attacker: obj_id(game, "Spec Thorn Wyrm"))
      game.submit(type: "done") if game.pending_decision.kind == "declare_blockers"
      pass_both(game)
      expect(game.state.object(giant).counters).to eq("-1/-1" => 2)
    end
  end

  describe "decayed (CR 702.147)" do
    it "can't block, and is sacrificed at end of combat after it attacks (CR 702.147a)" do
      game = board(field: ["Spec Rot Hulk"], bob_field: ["Spec Rot Hulk"], pool: {}, step: :beginning_of_combat)
      mine = mine(game, "spec_rot_hulk").first
      pass_both(game)
      game.submit(type: "attack", object: mine, target: "player:bob")
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
      pass_both(game) # the attack trigger resolves
      expect(game.pending_decision.kind).to eq("priority") # bob's Hulk can't block: no declare_blockers decision
      skip_to(game, :end_of_combat)
      pass_both(game)
      expect(game.state.players[1].life).to eq(15)
      expect(game.state.battlefield).not_to include(mine)
      expect(ids_in(game, "alice", :graveyard).map { game.state.object(it).card }).to include("spec_rot_hulk")
    end

    it "a decayed counter gives it decayed (CR 122.1b)" do
      game = board(hand: ["Spec Rot Renewal"], field: ["Grizzly Bears"], pool: { C: 1 })
      bears = obj_id(game, "Grizzly Bears")
      cast(game, "Spec Rot Renewal", target: bears)
      pay(game)
      pass_both(game)
      expect(chars(game, bears).keyword?(:decayed)).to be(true)
    end
  end

  describe "exert (CR 701.43)" do
    it "as a cost: it doesn't untap during its controller's next untap step only (CR 701.43a)" do
      game = board(field: ["Spec Weary Knight"], pool: {})
      knight = obj_id(game, "Spec Weary Knight")
      game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == knight })
      pass_both(game)
      expect(game.state.object(knight).tapped).to be(true)
      skip_to(game, :upkeep, turn: 5)
      expect(game.state.object(knight).tapped).to be(true)
      skip_to(game, :upkeep, turn: 7)
      expect(game.state.object(knight).tapped).to be(false)
    end
  end

  describe "firebending (CR 702.189b)" do
    it "its ability resolving is firebending" do
      game = board(field: ["Spec Ember Pupil"], pool: {}, step: :beginning_of_combat)
      pass_both(game)
      game.submit(type: "attack", object: obj_id(game, "Spec Ember Pupil"), target: "player:bob")
      game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
      pass_both(game) # firebending
      pass_both(game) # the firebends trigger
      expect(game.state.players[0].life).to eq(21)
    end
  end
end
