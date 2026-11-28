# frozen_string_literal: true

# Costs paid while resolving (CR 118.12), "this permanent" in a triggered ability's cost (CR 113.7, 400.7), a spell
# exiling itself (CR 608.2n), choices in mana abilities' costs (CR 605.3a), cost reductions (CR 601.2f) and a
# payment that can't be finished (CR 734.1).
RSpec.describe "Cost and payment fixes (CR 118.12, 601.2f, 605.3a, 608.2n, 734.1)" do
  def draw_one = [{ "draw" => { "amount" => 1 } }]
  def gain(n) = [{ "gain_life" => { "amount" => n } }]

  def sorcery(name, effects, cost: "{B}")
    { "name" => name, "mana_cost" => cost, "types" => ["sorcery"], "abilities" => [{ "spell" => { "effects" => effects } }] }
  end

  def creature(name, abilities = [], extra = {})
    { "name" => name, "mana_cost" => "{1}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => abilities }.merge(extra)
  end

  def pay_all(game)
    while game.pending_decision&.kind == "pay_cost"
      pay = game.legal_options.find { it[:type] == "pay_mana" }
      game.submit(pay || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  def cast_first(game)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    pay_all(game)
  end

  def resolve_stack(game)
    game.submit(type: "pass") until game.state.stack.empty? || game.pending_decision.kind != "priority"
  end

  def counters_of(game, card) = game.state.object(obj_id(game, card)).counters.reject { |_, n| n.zero? }
  def life(game, who) = game.state.players[game.names.index(who)].life
  def cards(game, who, zone) = ids_in(game, who, zone).map { game.state.object(it).card }
  def engine(game) = game.instance_variable_get(:@engine)
  def exiled(game) = game.state.exile.map { game.state.object(it).card }

  describe "a cost with choices paid through `pay` (CR 118.12, 601.2h)" do
    let(:battery) { creature("Spec Charge Battery") }
    let(:drain) do
      sorcery("Spec Charge Drain", [{ "pay" => { "cost" => [{ "remove_counters" => { "count" => 1, "counter" => "charge",
                                                                                     "filter" => "permanent" } }],
                                                 "then" => draw_one, "otherwise" => gain(5) } }])
    end

    def board(catalog, counters: { "charge" => 1, "+1/+1" => 1 }, hand: ["Spec Charge Drain"], &extra)
      build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { B: 1 }) do
          hand(*hand)
          battlefield "Spec Charge Battery", counters: counters
          instance_eval(&extra) if extra
          library "Forest", count: 5
        end
        player("bob") { library "Forest", count: 5 }
      end
    end

    it "removes the chosen counter of the named kind (CR 118.12, 122.1)" do
      game = board(catalog_with(battery, drain))
      cast_first(game)
      resolve_stack(game)
      game.submit(type: "pay")
      battery_id = obj_id(game, "Spec Charge Battery")
      expect(game.legal_options).to eq([{ type: "cost", object: battery_id, counter: "charge" }])
      game.submit(type: "cost", object: battery_id, counter: "charge")
      expect(counters_of(game, "Spec Charge Battery")).to eq("+1/+1" => 1)
      expect(ids_in(game, "alice", :hand).size).to eq(1)
      expect(life(game, "alice")).to eq(20)
    end

    it "chooses each kind of choosing cost: sacrifice, tap, discard, behold, creature type (CR 601.2h, 701.4a)" do
      costs = [{ "sacrifice_permanent" => { "filter" => "artifact" } }, { "tap_permanents" => { "count" => 1 } },
               { "discard" => {} }, { "choose_creature_type" => {} },
               { "behold" => { "card" => { "subtypes" => "chosen" } } }]
      spell = sorcery("Spec Many Costs", [{ "pay" => { "cost" => costs, "then" => gain(3) } }])
      relic = { "name" => "Spec Relic", "mana_cost" => "{1}", "types" => ["artifact"] }
      elf = creature("Spec Elf", [], "subtypes" => ["elf"])
      game = board(catalog_with(battery, spell, relic, elf), hand: ["Spec Many Costs", "Forest"]) do
        battlefield "Spec Relic", "Spec Elf"
      end
      cast_first(game)
      resolve_stack(game)
      game.submit(type: "pay")
      game.submit(type: "cost", object: obj_id(game, "Spec Relic"))
      game.submit(type: "cost", object: obj_id(game, "Spec Charge Battery"))
      game.submit(type: "cost", object: ids_in(game, "alice", :hand).first)
      game.submit(type: "cost", creature_type: "elf")
      expect(game.legal_options).to eq([{ type: "cost", object: obj_id(game, "Spec Elf") }])
      game.submit(type: "cost", object: obj_id(game, "Spec Elf"))
      expect(life(game, "alice")).to eq(23)
      expect(cards(game, "alice", :graveyard)).to contain_exactly("spec_relic", "forest", "spec_many_costs")
      expect(game.state.object(obj_id(game, "Spec Charge Battery")).tapped).to be(true)
    end
  end

  describe "\"this permanent\" in a triggered ability's `pay` (CR 113.7a, 118.12)" do
    let(:keeper) do
      creature("Spec Charge Keeper", [{ "triggered" => {
                 "when" => { "step_begins" => { "step" => "end", "whose" => "your" } },
                 "effects" => [{ "pay" => { "cost" => [{ "remove_counters" => { "count" => 1, "counter" => "charge", "self" => true } }],
                                            "then" => draw_one, "otherwise" => [{ "sacrifice" => { "to" => "self" } }] } }]
               } }])
    end
    let(:offering) do
      creature("Spec Offering", [{ "triggered" => {
                 "when" => { "step_begins" => { "step" => "end", "whose" => "your" } },
                 "effects" => [{ "pay" => { "cost" => ["sacrifice"], "then" => gain(4) } }]
               } }])
    end

    def end_step(catalog, field, counters: {})
      game = build_game(catalog) do
        turn 3, active: "alice", step: :postcombat_main
        player("alice") do
          battlefield field, counters: counters
          library "Forest", count: 5
        end
        player("bob") { library "Forest", count: 5 }
      end
      game.submit(type: "pass") until game.state.stack.any?
      yield game if block_given? # the trigger is on the stack
      game.submit(type: "pass") until game.pending_decision.kind == "effect_choice"
      game
    end

    it "removes counters from the source permanent, not the ability on the stack (CR 113.7a)" do
      game = end_step(catalog_with(keeper), "Spec Charge Keeper", counters: { "charge" => 2 })
      expect(game.legal_options).to eq([{ type: "pay" }, { type: "decline" }])
      game.submit(type: "pay")
      keeper_id = obj_id(game, "Spec Charge Keeper")
      game.submit(type: "cost", object: keeper_id, counter: "charge")
      expect(counters_of(game, "Spec Charge Keeper")).to eq("charge" => 1)
      expect(ids_in(game, "alice", :hand).size).to eq(1)
    end

    it "sacrifices the source permanent; with no counters only declining is open (CR 118.3)" do
      game = end_step(catalog_with(offering), "Spec Offering")
      game.submit(type: "pay")
      expect(cards(game, "alice", :graveyard)).to eq(["spec_offering"])
      expect(life(game, "alice")).to eq(24)
      game = end_step(catalog_with(keeper), "Spec Charge Keeper")
      expect(game.legal_options).to eq([{ type: "decline" }])
    end

    it "can't pay a \"this permanent\" cost once the source has left the battlefield (CR 400.7)" do
      game = end_step(catalog_with(offering), "Spec Offering") do |g|
        engine(g).move!(obj_id(g, "Spec Offering"), :graveyard, reason: "destroy")
      end
      expect(game.legal_options).to eq([{ type: "decline" }])
    end
  end

  describe "a spell that exiles itself, then goes on resolving (CR 608.2n, 400.7)" do
    let(:toll) do
      sorcery("Spec Vanishing Toll", ["exile_this_spell", { "pay" => { "mana" => "{1}", "then" => draw_one } },
                                      { "scry" => { "amount" => 1 } }])
    end
    let(:seeker) do
      sorcery("Spec Vanishing Seeker", [{ "may" => { "effects" => [{ "gain_life" => { "amount" => 1 } }],
                                                     "then" => ["exile_this_spell", { "search_library" => {
                                                       "for" => { "types" => ["land"] }, "put" => "hand"
                                                     } }] } }])
    end
    let(:spiral) do
      sorcery("Spec Vanishing Spiral", ["exile_this_spell", { "reflexive_trigger" => {
                "targets" => ["land"], "effects" => [{ "untap" => { "to" => { "target" => 0 } } }]
              } }])
    end

    def board(catalog, hand)
      build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { B: 1 }) do
          hand hand
          battlefield "Swamp"
          battlefield "Forest", tapped: true
          library "Forest", count: 5
        end
        player("bob") { library "Forest", count: 5 }
      end
    end

    it "asks for a payment and a scry after exiling itself; the game round-trips meanwhile" do
      game = board(catalog_with(toll), "Spec Vanishing Toll")
      cast_first(game)
      resolve_stack(game)
      expect(exiled(game)).to eq(["spec_vanishing_toll"])
      expect(Enjine::Snapshot.validate(game.state.to_h, game.catalog)).to eq([])
      game = Enjine::Game.import(game.export, catalog: game.catalog)
      game.submit(type: "pay")
      pay_all(game)
      expect(game.pending_decision.kind).to eq("effect_choice") # the scry
      game.submit(game.legal_options.first)
      expect(game.pending_decision.kind).to eq("priority")
      expect(ids_in(game, "alice", :hand).size).to eq(1)
      expect(exiled(game)).to eq(["spec_vanishing_toll"])
    end

    it "searches after exiling itself in a nested list (CR 701.23a)" do
      game = board(catalog_with(seeker), "Spec Vanishing Seeker")
      cast_first(game)
      resolve_stack(game)
      game.submit(type: "yes")
      expect(exiled(game)).to eq(["spec_vanishing_seeker"])
      game.submit(game.legal_options.first)
      game.submit(game.legal_options.first) while game.pending_decision.kind == "effect_choice"
      expect(cards(game, "alice", :hand)).to eq(["forest"])
      expect(life(game, "alice")).to eq(21)
    end

    it "creates a reflexive trigger after exiling itself (CR 603.12)" do
      game = board(catalog_with(spiral), "Spec Vanishing Spiral")
      cast_first(game)
      resolve_stack(game)
      expect(exiled(game)).to eq(["spec_vanishing_spiral"])
      forest = obj_id(game, "Forest")
      game.submit(type: "target", target: forest)
      resolve_stack(game)
      expect(game.state.object(forest).tapped).to be(false)
    end
  end

  describe "cost reductions (CR 601.2f, 607.2d)" do
    let(:horn) do
      { "name" => "Spec Herald Horn", "mana_cost" => "{3}", "types" => ["artifact"],
        "abilities" => [{ "choose_creature_type" => {} },
                        { "cost_modifier" => { "spells" => { "any_of" => ["creature"], "subtypes" => "chosen" }, "reduce" => 1 } }] }
    end
    let(:elf) { creature("Spec Horn Elf", [], "subtypes" => ["elf"], "mana_cost" => "{1}{G}") }
    let(:goblin) { creature("Spec Horn Goblin", [], "subtypes" => ["goblin"], "mana_cost" => "{1}{G}") }
    let(:blades) do
      { "name" => "Spec Counted Blades", "mana_cost" => "{2}", "types" => ["artifact"],
        "abilities" => [{ "activated" => {
          "cost" => [{ "mana" => "{3}" }], "timing" => "sorcery", "targets" => [{ "creature" => { "controller" => "you" } }],
          "cost_reduction" => { "amount" => { "counters" => { "of" => { "target" => 0 }, "kind" => "+1/+1" } } },
          "effects" => [{ "gain_life" => { "amount" => 1 } }]
        } }] }
    end

    it "spells of the type chosen for the permanent cost less (CR 607.2d)" do
      game = build_game(catalog_with(horn, elf, goblin)) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand "Spec Horn Elf", "Spec Horn Goblin"
          battlefield "Spec Herald Horn", "Forest"
          library "Forest", count: 3
        end
        player("bob")
      end
      game.state.object(obj_id(game, "Spec Herald Horn")).memory["chosen_type"] = "elf"
      game = Enjine::Game.import(game.export, catalog: game.catalog)
      castable = game.legal_options.select { it[:type] == "cast" }.map { game.state.object(it[:object]).card }
      expect(castable).to eq(["spec_horn_elf"])
    end

    it "an ability's reduction may count something about its target, once it is chosen (CR 601.2f)" do
      game = build_game(catalog_with(blades)) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          battlefield "Spec Counted Blades", "Forest"
          battlefield "Grizzly Bears", counters: { "+1/+1" => 2 }
          battlefield "Grizzly Bears"
          library "Forest", count: 3
        end
        player("bob")
      end
      blades_id = obj_id(game, "Spec Counted Blades")
      countered, plain = game.state.battlefield.select { it.start_with?("grizzly_bears") }
                             .partition { game.state.object(it).counters.any? }.map(&:first)
      game.submit(type: "activate", object: blades_id, ability: "printed:0") # affordable: it might target the counters
      game.submit(type: "target", target: countered)
      expect(game.pending_decision.details["remaining"]).to eq("{1}")
      game.submit(type: "cancel")
      game.submit(type: "activate", object: blades_id, ability: "printed:0")
      game.submit(type: "target", target: plain)
      expect(game.pending_decision.details["remaining"]).to eq("{3}")
    end
  end

  describe "a granted mana ability that taps its granter (CR 602.2b, 605.3a, 607.1a)" do
    let(:drum) do
      { "name" => "Spec Leaf Drum", "mana_cost" => "{1}", "types" => ["artifact"],
        "abilities" => [{ "static" => { "affects" => { "each" => "creature", "controller" => "you" },
                                        "abilities" => [{ "mana" => { "cost" => ["tap", { "tap" => "granter" }],
                                                                      "color" => "any_one" } }] } }] }
    end
    let(:growth) { sorcery("Spec Twin Growth", gain(2), cost: "{G}{G}") }
    let(:sprout) { sorcery("Spec Lone Sprout", gain(1), cost: "{G}") }

    def board(hand)
      build_game(catalog_with(drum, growth, sprout)) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand(*hand)
          battlefield "Spec Leaf Drum"
          battlefield "Grizzly Bears", count: 2
          library "Forest", count: 3
        end
        player("bob")
      end
    end

    def drum_options(game) = game.legal_options.select { it[:type] == "activate_mana" }

    it "taps the granter, so it makes mana once among all its creatures" do
      game = board(["Spec Twin Growth"])
      expect(option_types(game)).not_to include("cast") # one mana at most, not one per creature
      bears = game.state.battlefield.select { it.start_with?("grizzly_bears") }
      game.submit(drum_options(game).find { it[:object] == bears.first && it[:mana] == "{G}" })
      expect(game.state.object(obj_id(game, "Spec Leaf Drum")).tapped).to be(true)
      expect(drum_options(game)).to be_empty
    end

    it "untaps the granter when the payment is cancelled (CR 734.1)" do
      game = board(["Spec Lone Sprout"])
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(drum_options(game).find { it[:mana] == "{R}" })
      expect(game.legal_options).to include({ type: "cancel" })
      game.submit(type: "cancel")
      expect(game.state.battlefield.map { game.state.object(it) }.none?(&:tapped)).to be(true)
    end
  end

  describe "a payment that can't be finished after an irreversible cost (CR 734.1)" do
    let(:town) do
      { "name" => "Spec Toll Town", "types" => ["land"],
        "abilities" => [{ "mana" => { "cost" => ["tap", { "pay_life" => 1 }], "color" => "any_one" } }] }
    end
    let(:bolt) do
      { "name" => "Spec Town Bolt", "mana_cost" => "{1}{R}", "types" => ["instant"],
        "abilities" => [{ "spell" => { "effects" => gain(3) } }] }
    end

    def stuck_game(resolving: false)
      catalog = catalog_with(town, bolt, sorcery("Spec Town Toll", [{ "pay" => { "mana" => "{1}{R}", "then" => gain(3) } }]))
      game = build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { B: 1 }) do
          hand(resolving ? "Spec Town Toll" : "Spec Town Bolt")
          battlefield "Spec Toll Town", "Mountain"
          library "Forest", count: 3
        end
        player("bob")
      end
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      if resolving
        game.submit(type: "pay_mana", mana: "B")
        resolve_stack(game)
        game.submit(type: "pay")
      end
      expect(game.legal_options).to include({ type: "cancel" })
      game.submit(type: "activate_mana", object: obj_id(game, "Spec Toll Town"), ability: "printed:0", mana: "{G}")
      expect(game.legal_options).not_to include({ type: "cancel" }) # irreversible: the life is paid (CR 605.3a)
      game.submit(type: "pay_mana", mana: "G")
      engine(game).object(obj_id(game, "Mountain")).tapped = true # its mana is gone: the rest can't be paid
      game = Enjine::Game.import(game.export, catalog: game.catalog)
      expect(game.legal_options).to eq([{ type: "cancel" }])
      game
    end

    it "the cast is rewound; the mana ability isn't, its mana goes back to the pool" do
      game = stuck_game
      game.submit(type: "cancel")
      expect(cards(game, "alice", :hand)).to eq(["spec_town_bolt"])
      expect(game.state.stack).to be_empty
      expect(life(game, "alice")).to eq(19)
      expect(game.state.object(obj_id(game, "Spec Toll Town")).tapped).to be(true)
      expect(game.state.players[0].mana_pool).to include(G: 1, B: 1)
      expect(game.pending_decision.kind).to eq("priority")
    end

    it "a payment while resolving counts as not paid" do
      game = stuck_game(resolving: true)
      game.submit(type: "cancel")
      expect(life(game, "alice")).to eq(19)
      expect(game.state.players[0].mana_pool).to include(G: 1)
      expect(game.pending_decision.kind).to eq("priority")
    end
  end
end
