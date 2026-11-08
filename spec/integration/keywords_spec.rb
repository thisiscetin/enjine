# frozen_string_literal: true

RSpec.describe "Evergreen keywords (CR 702)" do
  def creature(name, power, toughness, *keywords)
    { "name" => name, "mana_cost" => "{1}", "types" => ["creature"], "power" => power, "toughness" => toughness,
      "keywords" => keywords }
  end

  let(:catalog) do
    catalog_with(
      creature("Sky Skiff", 2, 2, "flying"), creature("Web Spinner", 1, 3, "reach"), creature("Gate Warden", 0, 4, "defender"),
      creature("Night Watch", 2, 2, "vigilance"), creature("Alley Brute", 3, 3, "menace"),
      creature("Duelist", 2, 1, "first strike"), creature("Twin Blade", 2, 2, "double strike"),
      creature("Stampede Bull", 5, 4, "trample"), creature("Venom Adder", 1, 1, "deathtouch"),
      creature("Toxic Trampler", 4, 4, "trample", "deathtouch"), creature("Blood Priest", 2, 2, "lifelink"),
      creature("Stone Golem", 2, 2, "indestructible"), creature("Veiled Scout", 2, 2, "hexproof")
    )
  end

  def combat(attacker_cards, blocker_cards, step: :beginning_of_combat)
    build_game(catalog) do
      turn 3, active: "alice", step: step
      player("alice") do
        attacker_cards.each { battlefield it }
        library "Forest", count: 5
      end
      player("bob") do
        blocker_cards.each { battlefield it }
        library "Forest", count: 5
      end
    end
  end

  def id(game, name) = obj_id(game, name)
  def life(game, who) = game.view_for(:observer)["players"].find { it["name"] == who }["life"]

  def attack(game, *names)
    pass_both(game)
    names.each { game.submit(type: "attack", object: id(game, it), target: "player:bob") }
    game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
    pass_both(game) # -> declare blockers
  end

  it "flying: only flying or reach creatures can block it (CR 702.9b, 702.17b)" do
    game = combat(["Sky Skiff"], ["Grizzly Bears", "Web Spinner", "Sky Skiff"])
    attack(game, "Sky Skiff")
    blockers = game.legal_options.filter_map { it[:object] if it[:type] == "block" }
    expect(blockers.map { game.state.object(it).card }).to contain_exactly("web_spinner", "sky_skiff")
  end

  it "defender can't attack; vigilance attacks without tapping (CR 702.3b, 702.20b)" do
    game = combat(["Gate Warden", "Night Watch"], [])
    pass_both(game)
    expect(game.legal_options.filter_map { it[:object] }.uniq).to eq([id(game, "Night Watch")])
    game.submit(type: "attack", object: id(game, "Night Watch"), target: "player:bob")
    expect(game.state.object(id(game, "Night Watch")).tapped).to be(false)
  end

  it "menace: a single blocker is illegal until another joins or it's removed (CR 702.111b)" do
    game = combat(["Alley Brute"], ["Grizzly Bears", "Hill Giant"])
    attack(game, "Alley Brute")
    bears = id(game, "Grizzly Bears")
    game.submit(type: "block", object: bears, attacker: id(game, "Alley Brute"))
    expect(option_types(game)).not_to include("done")
    expect(game.legal_options).to include(type: "unblock", object: bears)
    game.submit(type: "block", object: id(game, "Hill Giant"), attacker: id(game, "Alley Brute"))
    expect(game.step).to eq(:declare_blockers) # both blockers declared: legal, the declaration ends
    expect(game.pending_decision.kind).to eq("priority")
  end

  it "menace: removing the lone blocker makes 'done' legal again" do
    game = combat(["Alley Brute"], ["Grizzly Bears", "Hill Giant"])
    attack(game, "Alley Brute")
    bears = id(game, "Grizzly Bears")
    game.submit(type: "block", object: bears, attacker: id(game, "Alley Brute"))
    game.submit(type: "unblock", object: bears)
    expect(option_types(game)).to include("done")
  end

  it "first strike deals damage first, killing a blocker before it strikes back (CR 702.7b, 510.4)" do
    game = combat(["Duelist"], ["Grizzly Bears"])
    attack(game, "Duelist")
    game.submit(type: "block", object: id(game, "Grizzly Bears"), attacker: id(game, "Duelist"))
    pass_both(game) # -> first-strike damage step
    expect(game.step).to eq(:combat_damage)
    expect(game.state.battlefield.map { game.state.object(it).card }).not_to include("grizzly_bears")
    pass_both(game) # -> regular damage step
    expect(game.step).to eq(:combat_damage)
    expect(view_of(game, id(game, "Duelist"))["damage"]).to eq(0)
  end

  it "double strike deals damage in both steps (CR 702.4b)" do
    game = combat(["Twin Blade"], [])
    attack(game, "Twin Blade")
    pass_both(game) # -> first-strike damage step
    expect(life(game, "bob")).to eq(18)
    pass_both(game)
    expect(life(game, "bob")).to eq(16)
  end

  it "trample: lethal damage to the blocker, the excess may go to the player (CR 702.19b)" do
    game = combat(["Stampede Bull"], ["Grizzly Bears"])
    attack(game, "Stampede Bull")
    bull = id(game, "Stampede Bull")
    bears = id(game, "Grizzly Bears")
    game.submit(type: "block", object: bears, attacker: bull)
    pass_both(game)
    expect(game.pending_decision).to have_attributes(kind: "assign_damage", details: { "attacker" => bull, "remaining" => 5 })
    expect(game.legal_options).to eq([{ type: "assign", object: bears }]) # player not yet: bears needs 2
    2.times { game.submit(type: "assign", object: bears) }
    expect(game.legal_options).to eq([{ type: "assign", object: bears }, { type: "assign", object: "player:bob" }])
    3.times { game.submit(type: "assign", object: "player:bob") }
    expect(life(game, "bob")).to eq(17)
    expect(game.state.battlefield).not_to include(bears)
  end

  it "trample with all blockers gone assigns everything to the player (CR 702.19e)" do
    game = combat(["Stampede Bull"], ["Grizzly Bears"])
    attack(game, "Stampede Bull")
    game.submit(type: "block", object: id(game, "Grizzly Bears"), attacker: id(game, "Stampede Bull"))
    data = game.to_h
    data["state"]["blockers"] = {}
    bears = data["state"]["battlefield"].find { it.start_with?("grizzly_bears") }
    data["state"]["battlefield"].delete(bears)
    data["state"]["players"][1]["graveyard"] << bears
    data["state"]["objects"].find { it["id"] == bears }.merge!("zone" => "graveyard", "controlled_since" => nil)
    game = Enjine::Game.import(data, catalog: catalog)
    pass_both(game)
    expect(life(game, "bob")).to eq(15)
  end

  it "deathtouch: any damage destroys a creature (CR 702.2b, 704.5h); 1 is lethal for trample (702.2c)" do
    game = combat(["Venom Adder"], ["Hill Giant"])
    attack(game, "Venom Adder")
    game.submit(type: "block", object: id(game, "Hill Giant"), attacker: id(game, "Venom Adder"))
    pass_both(game)
    expect(game.state.battlefield.map { game.state.object(it).card }).not_to include("hill_giant")

    game = combat(["Toxic Trampler"], ["Hill Giant"])
    attack(game, "Toxic Trampler")
    game.submit(type: "block", object: id(game, "Hill Giant"), attacker: id(game, "Toxic Trampler"))
    pass_both(game)
    game.submit(type: "assign", object: id(game, "Hill Giant"))
    expect(game.legal_options).to include(type: "assign", object: "player:bob")
    3.times { game.submit(type: "assign", object: "player:bob") }
    expect(life(game, "bob")).to eq(17)
    expect(game.state.battlefield.map { game.state.object(it).card }).not_to include("hill_giant")
  end

  it "lifelink: its controller gains life equal to the damage (CR 702.15b)" do
    game = combat(["Blood Priest"], [])
    attack(game, "Blood Priest")
    pass_both(game) # -> combat damage
    expect(life(game, "alice")).to eq(22)
    expect(life(game, "bob")).to eq(18)
  end

  it "indestructible survives lethal damage and destroy effects, not 0 toughness (CR 702.12b)" do
    game = combat(["Hill Giant"], ["Stone Golem"])
    attack(game, "Hill Giant")
    golem = id(game, "Stone Golem")
    game.submit(type: "block", object: golem, attacker: id(game, "Hill Giant"))
    pass_both(game)
    expect(game.state.battlefield).to include(golem)
    expect(view_of(game, golem)["damage"]).to eq(3)
    engine = game.instance_variable_get(:@engine)
    destroy = Enjine::Mechanics.build_entry(:effect, { "destroy" => { "to" => { "target" => 0 } } }, [], "e", targets_count: 1)
    destroy.apply(engine, Enjine::Mechanics::EffectContext.new(0, nil, nil, [golem]))
    expect(game.state.battlefield).to include(golem)
  end

  it "hexproof: opponents can't target it, its controller can (CR 702.11b)" do
    game = build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Lightning Bolt", "Giant Growth"
        battlefield "Mountain", "Forest"
      end
      player("bob") { battlefield "Veiled Scout" }
    end
    scout = id(game, "Veiled Scout")
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    expect(game.legal_options.map { it[:target] }).not_to include(scout)
    game.submit(type: "cancel")
    # Giant Growth needs a creature target; the only creature is bob's hexproof Scout.
    expect(game.legal_options).not_to include(type: "cast", object: ids_in(game, "alice", :hand).last)
  end
end
