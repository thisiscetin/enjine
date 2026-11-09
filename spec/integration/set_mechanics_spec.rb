# frozen_string_literal: true

# Face a dilemma (CR 700.17), assimilate (CR 701.72) and the strange new worlds count.
RSpec.describe "Star Trek set mechanics" do
  let(:herald) do
    { "name" => "Dilemma Herald", "mana_cost" => "{R}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "enters" => {} }, "modes" => [
        { "effects" => [{ "gain_life" => { "amount" => 1 } }] },
        { "effects" => [{ "lose_life" => { "amount" => 1, "to" => "each_opponent" } }] }
      ] } }] }
  end
  let(:watcher) do
    { "name" => "Rival Watcher", "mana_cost" => "{B}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "faces_dilemma" => { "controller" => "opponent" } },
                                         "effects" => [{ "lose_life" => { "amount" => 1, "to" => "each_opponent" } }] } }] }
  end
  let(:subjugate) do
    { "name" => "Subjugation Beam", "mana_cost" => "{B}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => [{ "creature" => { "controller" => "opponent" } }],
                                     "effects" => [{ "assimilate" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:catalog) { catalog_with(herald, watcher, subjugate) }

  def engine(game) = game.instance_variable_get(:@engine)
  def life(game, name) = game.view_for(:observer)["players"].find { it["name"] == name }["life"]

  def cast(game, card, player: "alice")
    game.submit(type: "cast", object: ids_in(game, player, :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(card) })
  end

  def pay_all(game)
    while game.pending_decision.kind == "pay_cost"
      game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
    end
  end

  describe "face a dilemma (CR 700.17)" do
    def board(hand)
      build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand.each { hand it }
          battlefield "Crossroads Oracle", "Island", "Island", "Mountain"
          library "Forest", count: 5
        end
        player("bob") do
          battlefield "Rival Watcher"
          library "Forest", count: 5
        end
      end
    end

    it "choosing a mode for a spell triggers 'whenever you face a dilemma', for you and not for an opponent's 'you'" do
      game = board(["Forked Path"])
      oracle = obj_id(game, "Crossroads Oracle")
      cast(game, "Forked Path")
      game.submit(type: "mode", mode: 0)
      entry = nil
      until game.pending_decision.kind != "pay_cost"
        entry = game.submit(game.legal_options.find { it[:type] == "pay_mana" } || game.legal_options.find { it[:type] == "activate_mana" })
      end
      expect(entry.events.map(&:type)).to include("dilemma_faced", "spell_cast")
      game.submit(game.legal_options.first) if game.pending_decision.kind == "order_triggers"
      names = game.view_for(:observer)["stack"].map { it["name"] }
      expect(names).to contain_exactly("Forked Path", "Crossroads Oracle ability", "Rival Watcher ability")
      pass_both(game, 3)
      expect(game.state.object(oracle).counters["+1/+1"]).to eq(1)
      expect(life(game, "alice")).to eq(19) # bob's watcher: an opponent faced a dilemma
    end

    it "a cancelled modal cast faces no dilemma" do
      game = board(["Forked Path"])
      cast(game, "Forked Path")
      game.submit(type: "mode", mode: 0)
      entry = game.submit(type: "cancel")
      expect(entry.events.map(&:type)).not_to include("dilemma_faced")
      expect(game.state.pending_triggers).to be_empty
    end

    it "choosing modes for a triggered ability is facing a dilemma too (CR 603.3c)" do
      game = board(["Dilemma Herald"])
      cast(game, "Dilemma Herald")
      pay_all(game)
      pass_both(game) # the creature resolves; its modal trigger asks for a mode
      expect(game.pending_decision.kind).to eq("choose_mode")
      game.submit(type: "mode", mode: 1)
      game.submit(game.legal_options.first) while game.pending_decision.kind == "order_triggers"
      expect(game.view_for(:observer)["stack"].map { it["name"] }).to include("Crossroads Oracle ability")
    end
  end

  describe "assimilate (CR 701.72)" do
    it "puts a creature card from a graveyard onto the battlefield under your control as a Borg artifact creature (701.72b)" do
      game = build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand "Hive Reclaimer"
          battlefield "Swamp", count: 4
          library "Forest", count: 5
        end
        player("bob") do
          graveyard "Grizzly Bears"
          library "Forest", count: 5
        end
      end
      bears = ids_in(game, "bob", :graveyard).first
      cast(game, "Hive Reclaimer")
      expect(game.legal_options).to include(type: "target", target: bears)
      game.submit(type: "target", target: bears)
      pay_all(game)
      pass_both(game)
      new_id = game.state.battlefield.find { game.state.object(it).card == "grizzly_bears" }
      obj = game.state.object(new_id)
      expect(obj).to have_attributes(controller: 0, owner: 1, counters: { "+1/+1" => 1 })
      expect(engine(game).chars(new_id)).to have_attributes(types: %i[creature artifact], subtypes: [:borg], power: 3)
      expect(engine(game).summoning_sick_for_tap?(obj)).to be(true)
      copy = Enjine::Game.import(game.export, catalog: catalog)
      expect(engine(copy).chars(new_id).types).to include(:artifact)
    end

    it "gains control of a permanent and puts a +1/+1 counter on it (701.72a); it keeps non-creature subtypes (CR 205.1b)" do
      game = build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand "Subjugation Beam"
          battlefield "Swamp"
          library "Forest", count: 5
        end
        player("bob") do
          battlefield "Longreach Skiff", counters: { "charge" => 3 }
          battlefield "Hill Giant"
          library "Forest", count: 5
        end
      end
      skiff = obj_id(game, "Longreach Skiff")
      cast(game, "Subjugation Beam")
      game.submit(type: "target", target: skiff)
      pay_all(game)
      entry = nil
      2.times { entry = game.submit(type: "pass") }
      expect(entry.events.map(&:type)).to include("control_changed")
      expect(game.state.object(skiff)).to have_attributes(controller: 0, controlled_since: 3)
      expect(engine(game).chars(skiff).subtypes).to eq(%i[spacecraft borg])
      expect(engine(game).power(game.state.object(skiff))).to eq(4)
    end

    it "the +1/+1 counter adds to the counters it would enter with anyway (CR 701.72b, 306.5b)" do
      absorb = { "name" => "Total Absorption", "mana_cost" => "{B}", "types" => ["sorcery"],
                 "abilities" => [{ "spell" => { "targets" => [{ "graveyard_card" => { "any_of" => ["planeswalker"] } }],
                                                "effects" => [{ "assimilate" => { "to" => { "target" => 0 } } }] } }] }
      game = build_game(catalog_with(absorb)) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand "Total Absorption"
          battlefield "Swamp"
          library "Forest", count: 5
        end
        player("bob") do
          graveyard "Vessa, Rally Captain"
          library "Forest", count: 5
        end
      end
      cast(game, "Total Absorption")
      game.submit(type: "target", target: ids_in(game, "bob", :graveyard).first)
      pay_all(game)
      pass_both(game)
      walker = game.state.battlefield.find { game.state.object(it).card == "vessa_rally_captain" }
      expect(game.state.object(walker).counters).to eq("loyalty" => 3, "+1/+1" => 1)
    end

    it "does nothing to a target that's no longer a card it can assimilate" do
      game = build_game(catalog) do
        player("alice") { library "Forest" }
        player("bob") { library "Forest" }
      end
      ctx = Enjine::Mechanics::EffectContext.new(0, nil, nil, [])
      expect(engine(game).assimilate!("missing#99", 0, ctx)).to be_nil
    end
  end

  describe "strange new worlds: differently named lands (CR 207.2c ability word)" do
    it "counts distinct names among lands you control" do
      game = build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand "Wayfinder Cartographer"
          battlefield "Forest", "Forest", "Mountain", "Island"
          library "Forest", count: 5
        end
        player("bob") do
          battlefield "Plains"
          library "Forest", count: 5
        end
      end
      cast(game, "Wayfinder Cartographer")
      pay_all(game)
      pass_both(game, 2)
      expect(life(game, "alice")).to eq(23) # Forest, Mountain, Island; not bob's Plains
    end
  end
end
