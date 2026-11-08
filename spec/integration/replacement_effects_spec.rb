# frozen_string_literal: true

RSpec.describe "Replacement effects (CR 614, 616)" do
  def pay_all(game)
    while game.pending_decision&.kind == "pay_cost"
      options = game.legal_options
      game.submit(options.find { it[:type] == "pay_mana" } || options.find { it[:type] == "activate_mana" })
    end
  end

  def cast(game, card, *targets, x_value: nil, player: "alice")
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: player))
    game.submit(type: "x", value: x_value) if x_value
    targets.each { game.submit(type: "target", target: it) }
    pay_all(game)
  end

  def cards(game, player, zone) = ids_in(game, player, zone).map { game.state.object(it).card }
  def life(game, who) = game.state.players[game.names.index(who)].life

  let(:pyre) do
    { "name" => "Pyre Lash", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["creature"],
                                     "effects" => [{ "deal_damage" => { "amount" => 4, "to" => { "target" => 0 } } }] } }] }
  end
  let(:unmake) do
    { "name" => "Unmake Rite", "mana_cost" => "{B}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [{ "destroy" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:offering) do
    { "name" => "Grim Offering", "mana_cost" => "{B}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => [{ "creature" => { "controller" => "you" } }],
                                     "effects" => [{ "sacrifice" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:catalog) { catalog_with(pyre, unmake, offering) }

  describe "draw replacement (CR 614.11)" do
    it "draws two instead of one; a second such effect applies to each of those draws (CR 614.5)" do
      game = build_game do
        turn 3, active: "alice", step: :upkeep
        player("alice") do
          battlefield "Ledger Savant"
          library "Forest", count: 10
        end
        player("bob") { library "Forest", count: 5 }
      end
      game.submit(type: "pass")
      game.submit(type: "pass")
      expect(ids_in(game, "alice", :hand).size).to eq(2) # the draw step's draw became two

      two = build_game do
        turn 3, active: "alice", step: :upkeep
        player("alice") do
          battlefield "Ledger Savant", count: 2
          library "Forest", count: 10
        end
        player("bob") { library "Forest", count: 5 }
      end
      2.times { two.submit(type: "pass") }
      expect(ids_in(two, "alice", :hand).size).to eq(4)
    end

    it "applies even with an empty library: the player drew from an empty library (CR 614.11, 704.5b)" do
      game = build_game do
        turn 3, active: "alice", step: :upkeep
        player("alice") { battlefield "Ledger Savant" }
        player("bob") { library "Forest", count: 5 }
      end
      2.times { game.submit(type: "pass") }
      expect(game.result).to eq("winner" => "bob", "reason" => "empty_library")
    end

    it "only replaces its controller's draws" do
      game = build_game do
        turn 3, active: "bob", step: :upkeep
        player("alice") { battlefield "Ledger Savant" }
        player("bob") { library "Forest", count: 5 }
      end
      2.times { game.submit(type: "pass") }
      expect(ids_in(game, "bob", :hand).size).to eq(1)
    end
  end

  describe "token replacement (CR 614.1a, 111.1)" do
    it "tokens created under its controller's control are replaced by that many of its token, tapped status kept" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { G: 4 }) do
          hand "Mirage Foundry"
          library "Forest", count: 5
        end
        player("bob") { library "Forest", count: 5 }
      end
      cast(game, "Mirage Foundry")
      2.times { game.submit(type: "pass") } # the creature resolves; its enters trigger goes on the stack
      2.times { game.submit(type: "pass") } # the trigger resolves: a Treasure would be created
      tokens = game.state.battlefield.map { game.state.object(it) }.select { game.catalog.fetch(it.card).token? }
      expect(tokens.map { game.catalog.fetch(it.card).name }).to eq(["Phantasm"])
      expect(game.catalog.fetch(tokens.first.card).creature?).to be(true)
    end

    it "doesn't replace tokens an opponent creates" do
      game = build_game do
        turn 3, active: "alice", step: :end
        player("alice") do
          battlefield "Mirage Foundry"
          library "Forest", count: 5
        end
        player("bob") do
          battlefield "Hoarding Broker"
          library "Forest", count: 5
        end
      end
      skip_to(game, :upkeep, turn: 4)
      2.times { game.submit(type: "pass") } # the upkeep trigger creates bob's Treasure
      names = game.state.battlefield.map { game.catalog.fetch(game.state.object(it).card).name }
      expect(names).to include("Treasure")
      expect(names).not_to include("Phantasm")
    end
  end

  describe "destruction replacement (CR 614.8-style)" do
    def board(defender, counters: { "+1/+1" => 1 }, damage: 0, hand: "Unmake Rite")
      cat = catalog
      build_game(cat) do
        turn 3, active: "bob", step: :precombat_main
        player("alice") do
          battlefield "Field Medic Tovan"
          battlefield defender, counters: counters, damage: damage
        end
        player("bob", mana_pool: { B: 1, R: 1 }) do
          hand hand
          library "Forest", count: 5
        end
      end
    end

    it "a destroy effect: instead all +1/+1 counters and all damage are removed" do
      game = board("Hill Giant", damage: 1)
      giant = obj_id(game, "Hill Giant")
      cast(game, "Unmake Rite", giant, player: "bob")
      2.times { game.submit(type: "pass") }
      expect(game.state.battlefield).to include(giant)
      expect(game.state.object(giant)).to have_attributes(counters: { "+1/+1" => 0 }, damage: 0)
    end

    it "lethal damage is destruction too (CR 704.5g): the damage is removed and it survives" do
      game = board("Hill Giant", counters: { "+1/+1" => 1 }, hand: "Pyre Lash")
      giant = obj_id(game, "Hill Giant")
      cast(game, "Pyre Lash", giant, player: "bob")
      2.times { game.submit(type: "pass") }
      expect(game.state.battlefield).to include(giant)
      expect(game.state.object(giant).damage).to eq(0)
    end

    it "doesn't apply without a +1/+1 counter, to itself, or to sacrifice (CR 701.21a)" do
      game = board("Hill Giant", counters: {})
      cast(game, "Unmake Rite", obj_id(game, "Hill Giant"), player: "bob")
      2.times { game.submit(type: "pass") }
      expect(cards(game, "alice", :graveyard)).to eq(["hill_giant"])

      medic = board("Hill Giant")
      tovan = obj_id(medic, "Field Medic Tovan")
      medic.state.object(tovan).counters["+1/+1"] = 1
      cast(medic, "Unmake Rite", tovan, player: "bob")
      2.times { medic.submit(type: "pass") }
      expect(cards(medic, "alice", :graveyard)).to eq(["field_medic_tovan"])

      own = build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { B: 1 }) do
          battlefield "Field Medic Tovan"
          battlefield "Hill Giant", counters: { "+1/+1" => 1 }
          hand "Grim Offering"
        end
        player("bob")
      end
      cast(own, "Grim Offering", obj_id(own, "Hill Giant"))
      2.times { own.submit(type: "pass") }
      expect(cards(own, "alice", :graveyard)).to contain_exactly("grim_offering", "hill_giant")
    end

    it "only protects its controller's creatures; one that only removes counters leaves the damage" do
      shedder = { "name" => "Shed Warden", "mana_cost" => "{1}", "types" => ["artifact"],
                  "abilities" => [{ "destroy_replacement" => { "affects" => { "each" => "creature", "controller" => "you" },
                                                               "remove_counters" => "+1/+1" } }] }
      game = build_game(catalog_with(unmake, shedder)) do
        turn 3, active: "bob", step: :precombat_main
        player("alice") do
          battlefield "Shed Warden"
          battlefield "Craw Wurm", counters: { "+1/+1" => 1 }, damage: 1
        end
        player("bob", mana_pool: { B: 2 }) do
          battlefield "Grizzly Bears", counters: { "+1/+1" => 1 }
          hand "Unmake Rite", count: 2
        end
      end
      wurm = obj_id(game, "Craw Wurm")
      cast(game, "Unmake Rite", wurm, player: "bob")
      2.times { game.submit(type: "pass") }
      expect(game.state.object(wurm)).to have_attributes(counters: { "+1/+1" => 0 }, damage: 1)
      cast(game, "Unmake Rite", obj_id(game, "Grizzly Bears"), player: "bob")
      2.times { game.submit(type: "pass") }
      expect(cards(game, "bob", :graveyard)).to include("grizzly_bears")
    end

    it "a replacement that only removes damage keeps the counters" do
      mender = { "name" => "Patch Warden", "mana_cost" => "{1}", "types" => ["artifact"],
                 "abilities" => [{ "destroy_replacement" => { "affects" => { "each" => "creature" }, "remove_damage" => true } }] }
      game = build_game(catalog_with(pyre, mender)) do
        turn 3, active: "bob", step: :precombat_main
        player("alice") { battlefield "Hill Giant", counters: { "+1/+1" => 1 } }
        player("bob", mana_pool: { R: 1 }) do
          battlefield "Patch Warden"
          hand "Pyre Lash"
        end
      end
      giant = obj_id(game, "Hill Giant")
      cast(game, "Pyre Lash", giant, player: "bob")
      2.times { game.submit(type: "pass") }
      expect(game.state.object(giant)).to have_attributes(counters: { "+1/+1" => 1 }, damage: 0)
    end

    it "removing the counters can leave 0 toughness, which isn't destruction (CR 704.5f)" do
      husk = { "name" => "Hollow Husk", "mana_cost" => "{1}", "types" => %w[artifact creature], "power" => 0, "toughness" => 0 }
      cat = catalog_with(unmake, husk)
      game = build_game(cat) do
        turn 3, active: "bob", step: :precombat_main
        player("alice") do
          battlefield "Field Medic Tovan"
          battlefield "Hollow Husk", counters: { "+1/+1" => 1 }
        end
        player("bob", mana_pool: { B: 1 }) { hand "Unmake Rite" }
      end
      cast(game, "Unmake Rite", obj_id(game, "Hollow Husk"), player: "bob")
      last = nil
      2.times { last = game.submit(type: "pass") }
      expect(last.events.grep(Enjine::Events::ZoneChanged).map(&:reason)).to include("sba_toughness")
      expect(cards(game, "alice", :graveyard)).to eq(["hollow_husk"])
    end
  end

  describe "a spell exiling itself as it resolves (CR 608.2n)" do
    it "happens once; an ability using it has no card to exile" do
      note = { "name" => "Vanishing Note", "mana_cost" => "{U}", "types" => ["instant"],
               "abilities" => [{ "spell" => { "effects" => ["exile_this_spell", { "draw" => { "amount" => 1 } }, "exile_this_spell"] } }] }
      herald = { "name" => "Fading Herald", "mana_cost" => "{U}", "types" => ["creature"], "power" => 1, "toughness" => 1,
                 "abilities" => [{ "triggered" => { "when" => { "enters" => {} },
                                                    "effects" => ["exile_this_spell", { "gain_life" => { "amount" => 1 } }] } }] }
      game = build_game(catalog_with(note, herald)) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { U: 2 }) do
          hand "Vanishing Note", "Fading Herald"
          library "Forest", count: 3
        end
        player("bob")
      end
      cast(game, "Vanishing Note")
      2.times { game.submit(type: "pass") }
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["vanishing_note"])
      cast(game, "Fading Herald")
      game.submit(type: "pass") until game.state.stack.empty? && game.state.pending_triggers.empty?
      expect(life(game, "alice")).to eq(21)
      expect(game.state.battlefield.map { game.state.object(it).card }).to include("fading_herald")
    end
  end

  describe "dies → exile instead, this turn (CR 614.1a, 700.4)" do
    it "a creature dealt lethal damage is exiled, not put into the graveyard" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { R: 3 }) do
          hand "Doom Brand"
          library "Forest", count: 3
        end
        player("bob") { battlefield "Grizzly Bears" }
      end
      bears = obj_id(game, "Grizzly Bears")
      cast(game, "Doom Brand", bears, x_value: 2)
      2.times { game.submit(type: "pass") }
      expect(cards(game, "bob", :graveyard)).to be_empty
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["grizzly_bears"])
    end

    it "ends at cleanup: a survivor isn't affected next turn" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { R: 2 }) do
          hand "Doom Brand"
          library "Forest", count: 3
        end
        player("bob") do
          battlefield "Hill Giant"
          library "Forest", count: 3
        end
      end
      cast(game, "Doom Brand", obj_id(game, "Hill Giant"), x_value: 1)
      2.times { game.submit(type: "pass") }
      expect(game.state.effects.map { it["kind"] }).to eq(["exile_if_dies"])
      skip_to(game, :upkeep, turn: 4)
      expect(game.state.effects).to be_empty
    end
  end

  describe "+1 counter of each kind until end of turn, before doubling (CR 616.1)" do
    it "adds one to counters put on its controller's permanents this turn" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { G: 2 }) do
          hand "Surge of Plenty"
          battlefield "Grizzly Bears"
          library "Forest", count: 3
        end
        player("bob")
      end
      bears = obj_id(game, "Grizzly Bears")
      cast(game, "Surge of Plenty", bears)
      2.times { game.submit(type: "pass") }
      expect(game.state.object(bears).counters).to eq("+1/+1" => 2)
    end

    it "is applied before a doubling effect, and to counters a permanent enters with" do
      doubler = { "name" => "Growth Matrix", "mana_cost" => "{2}", "types" => ["artifact"],
                  "abilities" => [{ "double_counters" => { "affects" => { "each" => "creature", "controller" => "you" } } }] }
      grower = { "name" => "Seeded Hulk", "mana_cost" => "{G}", "types" => ["creature"], "power" => 1, "toughness" => 1,
                 "abilities" => [{ "enters_with_counters" => { "counters" => { "+1/+1" => 1 } } }] }
      cat = catalog_with(doubler, grower)
      game = build_game(cat) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { G: 3 }) do
          hand "Surge of Plenty", "Seeded Hulk"
          battlefield "Grizzly Bears", "Growth Matrix"
          library "Forest", count: 3
        end
        player("bob")
      end
      bears = obj_id(game, "Grizzly Bears")
      cast(game, "Surge of Plenty", bears)
      2.times { game.submit(type: "pass") }
      expect(game.state.object(bears).counters).to eq("+1/+1" => 4) # (1 + 1) x 2
      cast(game, "Seeded Hulk")
      2.times { game.submit(type: "pass") }
      expect(game.state.object(obj_id(game, "Seeded Hulk")).counters).to eq("+1/+1" => 4)
    end
  end

  describe "enters untapped (CR 614.12, applied after enters tapped)" do
    it "overrides a land's own enters-tapped and an effect putting it onto the battlefield tapped" do
      tapland = { "name" => "Sleepy Grove", "types" => ["land"],
                  "abilities" => ["enters_tapped", { "mana" => { "cost" => ["tap"], "produce" => "{G}" } }] }
      cat = catalog_with(tapland)
      game = build_game(cat) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { G: 2 }) do
          hand "Sleepy Grove", "Swift Current Shrine"
          library "Forest", count: 3
        end
        player("bob")
      end
      cast(game, "Swift Current Shrine")
      2.times { game.submit(type: "pass") } # the shrine resolves
      2.times { game.submit(type: "pass") } # its trigger: search for a basic land, put it onto the battlefield tapped
      game.submit(game.legal_options.find { it[:type] == "find" })
      forest = obj_id(game, "Forest")
      expect(game.state.object(forest).tapped).to be(false)
      entry = game.submit(type: "play_land", object: obj_id(game, "Sleepy Grove", zone: :hand, player: "alice"))
      expect(game.state.object(entry.events.first.new_id).tapped).to be(false)
    end

    it "doesn't affect an opponent's lands" do
      tapland = { "name" => "Sleepy Grove", "types" => ["land"],
                  "abilities" => ["enters_tapped", { "mana" => { "cost" => ["tap"], "produce" => "{G}" } }] }
      game = build_game(catalog_with(tapland)) do
        turn 3, active: "bob", step: :precombat_main
        player("alice") { battlefield "Swift Current Shrine" }
        player("bob") { hand "Sleepy Grove" }
      end
      entry = game.submit(type: "play_land", object: obj_id(game, "Sleepy Grove", zone: :hand, player: "bob"))
      expect(game.state.object(entry.events.first.new_id).tapped).to be(true)
    end
  end

  describe "enters tapped and attacking (CR 508.4)" do
    it "a creature entering while its controller controls an attacker enters tapped and attacking, without attacking triggers" do
      game = build_game do
        turn 3, active: "alice", step: :beginning_of_combat
        player("alice") do
          battlefield "Vanguard Marshal"
          battlefield "Grizzly Bears"
          battlefield "Plains", count: 2
          hand "Watchful Sentry"
          library "Forest", count: 3
        end
        player("bob") { library "Forest", count: 3 }
      end
      2.times { game.submit(type: "pass") }
      bears = obj_id(game, "Grizzly Bears")
      game.submit(type: "attack", object: bears, target: "player:bob")
      game.submit(type: "done")
      expect(game.pending_decision).to have_attributes(kind: "priority", player: "alice")
      cast(game, "Watchful Sentry")
      entry = game.submit(type: "pass")
      entry = game.submit(type: "pass") until game.state.stack.empty?
      sentry = obj_id(game, "Watchful Sentry")
      expect(game.state.object(sentry).tapped).to be(true)
      expect(game.state.attackers[sentry]).to eq("target" => "player:bob", "blocked" => false)
      expect(entry.events.map(&:type)).not_to include("attacker_declared")
    end

    it "a creature token created during combat enters attacking too" do
      muster = { "name" => "Sudden Muster", "mana_cost" => "{W}", "types" => ["instant"],
                 "abilities" => [{ "spell" => { "effects" => [{ "create_token" => { "token" => {
                   "name" => "Recruit", "types" => ["creature"], "power" => 1, "toughness" => 1
                 } } }] } }] }
      game = build_game(catalog_with(muster)) do
        turn 3, active: "alice", step: :beginning_of_combat
        player("alice") do
          battlefield "Vanguard Marshal", "Plains"
          hand "Sudden Muster"
          library "Forest", count: 3
        end
        player("bob") { library "Forest", count: 3 }
      end
      2.times { game.submit(type: "pass") }
      game.submit(type: "attack", object: obj_id(game, "Vanguard Marshal"), target: "player:bob")
      cast(game, "Sudden Muster")
      game.submit(type: "pass") until game.state.stack.empty?
      token = game.state.attackers.keys.find { game.catalog.fetch(game.state.object(it).card).token? }
      expect(token).not_to be_nil
      expect(game.state.object(token).tapped).to be(true)
    end

    it "without an attacking creature it enters normally" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { G: 2 }) do
          battlefield "Vanguard Marshal"
          hand "Grizzly Bears"
        end
        player("bob")
      end
      cast(game, "Grizzly Bears")
      2.times { game.submit(type: "pass") }
      expect(game.state.object(obj_id(game, "Grizzly Bears")).tapped).to be(false)
      expect(game.state.attackers).to be_empty
    end
  end
end
