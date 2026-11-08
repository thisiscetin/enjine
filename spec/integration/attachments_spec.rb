# frozen_string_literal: true

RSpec.describe "Auras and Equipment (CR 301.5, 303.4, 701.3, 702.5, 702.6, 704.5m-n)" do
  # Uses the invented core-pool cards Brasswork Cudgel, Scout's Lens (Equipment), Emberbond Charm
  # and Withering Grasp (Auras).
  def board(alice: [], bob: [], hand: [], step: :precombat_main, active: "alice")
    build_game do
      turn 3, active: active, step: step
      player("alice") do
        alice.each { battlefield it }
        hand(*hand) unless hand.empty?
        library "Island", count: 5
      end
      player("bob") do
        bob.each { battlefield it }
        library "Island", count: 5
      end
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)

  # Spends pool mana, or taps a source, for the cost being paid, one decision at a time.
  def pay(game)
    while game.pending_decision&.kind == "pay_cost"
      options = game.legal_options
      game.submit(options.find { it[:type] == "pay_mana" } || options.find { it[:type] == "activate_mana" })
    end
  end

  def equip(game, equipment, creature, ability: "printed:1")
    game.submit(type: "activate", object: equipment, ability: ability)
    game.submit(type: "target", target: creature)
    pay(game)
    pass_both(game)
  end

  def cast(game, card, target)
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: "alice"))
    game.submit(type: "target", target: target)
    pay(game)
  end

  describe "equip (CR 702.6a)" do
    it "targets only another creature you control, at sorcery speed, and attaches on resolution (CR 701.3a)" do
      game = board(alice: ["Brasswork Cudgel", "Grizzly Bears", "Forest", "Forest"], bob: ["Hill Giant"])
      cudgel = obj_id(game, "Brasswork Cudgel")
      bears = obj_id(game, "Grizzly Bears")
      expect(game.legal_options).to include(type: "activate", object: cudgel, ability: "printed:1")
      game.submit(type: "activate", object: cudgel, ability: "printed:1")
      expect(game.legal_options).to eq([{ type: "target", target: bears }, { type: "cancel" }])
      game.submit(type: "target", target: bears)
      pay(game)
      entry = nil
      2.times { entry = game.submit(type: "pass") }
      expect(entry.events.map(&:type)).to include("attached")
      expect(game.state.object(cudgel).attached_to).to eq(bears)
      expect(view_of(game, bears).values_at("power", "toughness")).to eq([3, 3]) # CR 613.4c via the static
      expect(engine(game).chars(bears).keyword?(:vigilance)).to be(true)
      expect(view_of(game, cudgel)["attached_to"]).to eq(bears)
    end

    it "can't be activated at instant speed (CR 702.6a: activate only as a sorcery)" do
      game = board(alice: ["Brasswork Cudgel", "Grizzly Bears", "Forest", "Forest"], step: :beginning_of_combat)
      expect(game.legal_options.map { it[:type] }).not_to include("activate")
    end

    it "moving to another creature takes the bonus with it" do
      game = board(alice: ["Brasswork Cudgel", "Grizzly Bears", "Savannah Lions", "Forest", "Forest", "Forest", "Forest"])
      cudgel = obj_id(game, "Brasswork Cudgel")
      bears = obj_id(game, "Grizzly Bears")
      lions = obj_id(game, "Savannah Lions")
      equip(game, cudgel, bears)
      equip(game, cudgel, lions)
      expect(game.state.object(cudgel).attached_to).to eq(lions)
      expect(view_of(game, bears).values_at("power", "toughness")).to eq([2, 2])
      expect(view_of(game, lions).values_at("power", "toughness")).to eq([3, 2])
    end

    it "does nothing if the target is no longer controlled by you on resolution (CR 301.5b, 608.2b)" do
      game = board(alice: ["Brasswork Cudgel", "Grizzly Bears", "Forest", "Forest"])
      cudgel = obj_id(game, "Brasswork Cudgel")
      bears = obj_id(game, "Grizzly Bears")
      game.submit(type: "activate", object: cudgel, ability: "printed:1")
      game.submit(type: "target", target: bears)
      pay(game)
      game.state.object(bears).controller = 1 # e.g. a control change in response
      pass_both(game)
      expect(game.state.object(cudgel).attached_to).to be_nil
    end
  end

  describe "the attach action (CR 701.3)" do
    it "doesn't move an attachment to something it can't be attached to, or to what it is already on (CR 701.3b)" do
      game = board(alice: ["Brasswork Cudgel", "Grizzly Bears", "Forest", "Withering Grasp"])
      e = engine(game)
      cudgel = e.object(obj_id(game, "Brasswork Cudgel"))
      bears = obj_id(game, "Grizzly Bears")
      forest = obj_id(game, "Forest")
      expect(e.attach!(cudgel, forest)).to be(false) # not a creature (CR 301.5)
      expect(e.attach!(cudgel, cudgel.id)).to be(false) # can't equip itself (CR 301.5c)
      expect(e.attach!(cudgel, bears)).to be(true)
      expect(e.attach!(cudgel, bears)).to be(false) # already attached there: nothing happens
      grasp = e.object(obj_id(game, "Withering Grasp"))
      expect(e.can_attach?(grasp, bears)).to be(false) # enchant creature an opponent controls (CR 702.5a)
      expect(e.can_attach?(e.object(forest), bears)).to be(false) # not an Aura or Equipment
      expect(e.attachments_of(bears)).to eq([cudgel.id])
    end

    it "equipped, or enchanted by its controller's Aura, counts as modified; an opponent's Aura doesn't (CR 700.9)" do
      game = board(alice: ["Brasswork Cudgel", "Emberbond Charm", "Withering Grasp", "Grizzly Bears", "Glory Seeker"],
                   bob: ["Hill Giant"])
      e = engine(game)
      bears, seeker, giant = obj_id(game, "Grizzly Bears"), obj_id(game, "Glory Seeker"), obj_id(game, "Hill Giant")
      modified = Enjine::Mechanics.build_entry(:filter, { "creature" => { "modified" => true } }, [], "f")
      expect(modified.candidates(e, 0)).to eq([])
      e.object(obj_id(game, "Brasswork Cudgel")).attached_to = bears
      e.object(obj_id(game, "Emberbond Charm")).attached_to = seeker
      e.object(obj_id(game, "Withering Grasp")).attached_to = giant
      expect(modified.candidates(e, 0)).to contain_exactly(bears, seeker)
    end

    it "an Equipment that is also a creature can't equip (CR 301.5c)" do
      walker = { "name" => "Walking Rack", "mana_cost" => "{2}", "types" => %w[artifact creature], "subtypes" => ["equipment"],
                 "power" => 1, "toughness" => 1, "abilities" => [{ "equip" => { "cost" => [{ "mana" => "{1}" }] } }] }
      game = build_game(catalog_with(walker)) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          battlefield "Walking Rack", "Grizzly Bears", "Forest"
          library "Island", count: 5
        end
        player("bob") { library "Island", count: 5 }
      end
      e = engine(game)
      expect(e.attach!(e.object(obj_id(game, "Walking Rack")), obj_id(game, "Grizzly Bears"))).to be(false)
    end
  end

  describe "state-based actions" do
    it "an Equipment whose creature dies stays on the battlefield, unattached (CR 704.5n, 701.3d)" do
      game = board(alice: ["Brasswork Cudgel", "Grizzly Bears", "Forest", "Forest", "Mountain"], hand: ["Lightning Bolt"])
      cudgel = obj_id(game, "Brasswork Cudgel")
      bears = obj_id(game, "Grizzly Bears")
      equip(game, cudgel, bears)
      cast(game, "Lightning Bolt", bears)
      entry = nil
      2.times { entry = game.submit(type: "pass") }
      expect(entry.events.map(&:type)).to include("unattached")
      expect(game.state.battlefield).to include(cudgel)
      expect(game.state.object(cudgel).attached_to).to be_nil
      expect(game.pending_decision.kind).to eq("priority")
    end

    it "an Equipment attached to something that is no longer a creature becomes unattached (CR 704.5n)" do
      game = board(alice: ["Brasswork Cudgel", "Forest"])
      e = engine(game)
      cudgel = e.object(obj_id(game, "Brasswork Cudgel"))
      cudgel.attached_to = obj_id(game, "Forest") # e.g. a creature land that stopped being a creature
      e.check_state_based_actions!
      expect(cudgel.attached_to).to be_nil
    end

    it "a permanent that is neither an Aura nor an Equipment becomes unattached (CR 704.5p)" do
      game = board(alice: ["Grizzly Bears", "Forest"])
      e = engine(game)
      forest = e.object(obj_id(game, "Forest"))
      forest.attached_to = obj_id(game, "Grizzly Bears")
      e.check_state_based_actions!
      expect(forest.attached_to).to be_nil
      expect(game.state.battlefield).to include(forest.id)
    end

    it "an Aura attached to nothing or to an illegal object goes to its owner's graveyard (CR 704.5m, 303.4c)" do
      game = board(alice: ["Emberbond Charm", "Withering Grasp", "Grizzly Bears"])
      e = engine(game)
      e.check_state_based_actions!
      expect(game.state.battlefield).to eq([obj_id(game, "Grizzly Bears")])
      expect(ids_in(game, "alice", :graveyard).map { game.state.object(it).card }).to contain_exactly("emberbond_charm", "withering_grasp")
    end
  end

  describe "Aura spells (CR 303.4a, 608.3)" do
    it "target what the enchant ability allows and enter attached to that target (CR 115.1b, 608.3c)" do
      game = board(alice: ["Swamp", "Swamp", "Grizzly Bears"], bob: ["Hill Giant"], hand: ["Withering Grasp"])
      giant = obj_id(game, "Hill Giant")
      game.submit(type: "cast", object: obj_id(game, "Withering Grasp", zone: :hand, player: "alice"))
      expect(game.legal_options).to eq([{ type: "target", target: giant }, { type: "cancel" }])
      game.submit(type: "target", target: giant)
      pay(game)
      pass_both(game)
      grasp = obj_id(game, "Withering Grasp")
      expect(game.state.object(grasp).attached_to).to eq(giant)
      expect(game.state.object(grasp).targets).to be_nil # the Aura permanent doesn't target (CR 115.1b)
      expect(view_of(game, giant).values_at("power", "toughness")).to eq([2, 2])
    end

    it "isn't castable without a legal target (CR 303.4a)" do
      game = board(alice: ["Swamp", "Swamp", "Grizzly Bears"], hand: ["Withering Grasp"])
      expect(game.legal_options.map { it[:type] }).not_to include("cast")
    end

    it "goes to the graveyard without entering if its target is illegal on resolution (CR 608.3b)" do
      game = board(alice: %w[Mountain Mountain], bob: ["Raging Goblin"], hand: ["Emberbond Charm", "Lightning Bolt"])
      goblin = obj_id(game, "Raging Goblin")
      cast(game, "Emberbond Charm", goblin)
      cast(game, "Lightning Bolt", goblin)
      pass_both(game) # bolt resolves
      entry = nil
      2.times { entry = game.submit(type: "pass") }
      expect(entry.events.map(&:type)).to include("fizzled")
      expect(ids_in(game, "alice", :graveyard).map { game.state.object(it).card }).to include("emberbond_charm")
      expect(game.state.battlefield.map { game.state.object(it).card }).not_to include("emberbond_charm")
    end

    it "'enchanted creature gains ...' affects what it is attached to (CR 303.4m)" do
      game = board(alice: ["Mountain", "Grizzly Bears"], hand: ["Emberbond Charm"])
      bears = obj_id(game, "Grizzly Bears")
      cast(game, "Emberbond Charm", bears)
      pass_both(game) # the Aura resolves; its enters trigger goes on the stack
      pass_both(game) # the trigger resolves
      expect(engine(game).chars(bears).keyword?(:trample)).to be(true)
      expect(view_of(game, bears).values_at("power", "toughness")).to eq([4, 2])
    end

    it "an Aura whose -1/-1 kills the creature goes to the graveyard next (CR 704.5f, 704.5m)" do
      game = board(alice: %w[Swamp Swamp], bob: ["Raging Goblin"], hand: ["Withering Grasp"])
      goblin = obj_id(game, "Raging Goblin")
      cast(game, "Withering Grasp", goblin)
      entry = nil
      2.times { entry = game.submit(type: "pass") }
      reasons = entry.events.grep(Enjine::Events::ZoneChanged).map { [it.card, it.reason] }
      expect(reasons).to include(%w[raging_goblin sba_toughness], %w[withering_grasp sba_aura])
    end
  end

  it "'whenever equipped creature attacks' triggers for the creature it is attached to (CR 301.5f, 508.3a)" do
    game = board(alice: ["Scout's Lens", "Grizzly Bears", "Forest"])
    lens = obj_id(game, "Scout's Lens")
    bears = obj_id(game, "Grizzly Bears")
    equip(game, lens, bears, ability: "printed:2")
    expect(view_of(game, bears).values_at("power", "toughness")).to eq([2, 3])
    skip_to(game, :beginning_of_combat)
    pass_both(game)
    game.submit(type: "attack", object: bears, target: "player:bob")
    expect(game.state.stack.map { game.state.object(it).source }).to eq([lens])
  end

  it "attachments round-trip through export/import and are validated (CR 701.3)" do
    game = board(alice: ["Brasswork Cudgel", "Grizzly Bears", "Forest", "Forest"])
    equip(game, obj_id(game, "Brasswork Cudgel"), obj_id(game, "Grizzly Bears"))
    copy = Enjine::Game.import(JSON.parse(game.export), catalog: game.catalog)
    expect(copy.state.to_h).to eq(game.state.to_h)
    data = game.state.to_h
    cudgel = data["objects"].find { it["card"] == "brasswork_cudgel" }
    cudgel["attached_to"] = cudgel["id"]
    expect(Enjine::Snapshot.validate(data, game.catalog)).to include(a_string_matching(/attached_to: must be another object's id/))
    hand_obj = data["objects"].find { it["zone"] == "library" }
    hand_obj["attached_to"] = cudgel["id"]
    expect(Enjine::Snapshot.validate(data,
                                     game.catalog)).to include(a_string_matching(/only permanents on the battlefield can be attached/))
  end
end
