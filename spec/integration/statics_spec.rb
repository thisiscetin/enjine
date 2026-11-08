# frozen_string_literal: true

RSpec.describe "Static abilities and keyword grants (CR 604, 611, 613)" do
  let(:banner) do
    { "name" => "War Banner", "mana_cost" => "{2}", "types" => ["artifact"],
      "abilities" => [{ "static" => { "affects" => { "each" => "creature", "controller" => "you" },
                                      "pump" => { "power" => 1, "toughness" => 1 } } }] }
  end
  let(:captain) do
    { "name" => "Sky Captain", "mana_cost" => "{2}{W}", "types" => ["creature"], "power" => 2, "toughness" => 2,
      "abilities" => [{ "static" => { "affects" => { "each" => "creature", "controller" => "you", "other" => true },
                                      "keywords" => ["flying"] } }] }
  end
  let(:wings) do
    { "name" => "Sudden Wings", "mana_cost" => "{U}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["creature"],
                                     "effects" => [{ "grant" => { "keywords" => %w[flying], "to" => { "target" => 0 } } }] } }] }
  end
  let(:catalog) { catalog_with(banner, captain, wings) }

  def board(alice, bob = [], hand: nil)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        alice.each { battlefield it }
        hand hand if hand
        library "Forest", count: 5
      end
      player("bob") do
        bob.each { battlefield it }
        library "Forest", count: 5
      end
    end
  end

  it "an anthem pumps your creatures only, and stops when its source leaves" do
    game = board(["War Banner", "Grizzly Bears"], ["Hill Giant"])
    bears = obj_id(game, "Grizzly Bears")
    expect(view_of(game, bears).values_at("power", "toughness")).to eq([3, 3])
    expect(view_of(game, obj_id(game, "Hill Giant")).values_at("power", "toughness")).to eq([3, 3])
    engine = game.instance_variable_get(:@engine)
    engine.move!(obj_id(game, "War Banner"), :graveyard, reason: "destroy")
    expect(view_of(game, bears).values_at("power", "toughness")).to eq([2, 2])
  end

  it "applies to creatures that arrive later (not a locked set, CR 611.3a)" do
    game = board(["War Banner"])
    engine = game.instance_variable_get(:@engine)
    token = Enjine::CardDefinition.token("name" => "Recruit", "types" => ["creature"], "power" => 1, "toughness" => 1)
    game.catalog.add(token) # normally registered by the card that creates it
    id = engine.create_token!(token, 0).id
    expect(engine.power_toughness(engine.object(id))).to eq([2, 2])
  end

  it "grants keywords to other creatures you control, which changes how they can be blocked" do
    game = board(["Sky Captain", "Grizzly Bears"])
    expect(view_of(game, obj_id(game, "Grizzly Bears"))["keywords"]).to be_nil # view shows printed keywords
    engine = game.instance_variable_get(:@engine)
    expect(engine.chars(obj_id(game, "Grizzly Bears")).keyword?(:flying)).to be(true)
    expect(engine.chars(obj_id(game, "Sky Captain")).keyword?(:flying)).to be(false) # "other"
  end

  it "'gains flying until end of turn' lasts until cleanup" do
    game = board(["Island", "Grizzly Bears"], hand: "Sudden Wings")
    bears = obj_id(game, "Grizzly Bears")
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: bears)
    game.submit(type: "activate_mana", object: obj_id(game, "Island"), ability: "intrinsic:island")
    game.submit(type: "pay_mana", mana: "U")
    pass_both(game)
    engine = game.instance_variable_get(:@engine)
    expect(engine.chars(bears).keyword?(:flying)).to be(true)
    skip_to(game, :upkeep, turn: 4)
    expect(engine.chars(bears).keyword?(:flying)).to be(false)
  end

  it "validates static abilities and grants" do
    expect { Enjine::CardDefinition.from_h(banner.merge("abilities" => [{ "static" => { "affects" => "all" } }])) }
      .to raise_error(Enjine::InvalidCardDefinition, %r{affects: must be.*needs pump and/or keywords}m)
    expect { Enjine::CardDefinition.from_h(wings.merge("abilities" => [{ "spell" => { "effects" => [{ "grant" => { "keywords" => ["shiny"], "to" => "you" } }] } }])) }
      .to raise_error(Enjine::InvalidCardDefinition, /unknown keyword "shiny"/)
    expect(Enjine::CardDefinition.from_h(banner).abilities.first.to_s).to eq("creatures you control get +1/+1")
    expect(Enjine::CardDefinition.from_h(captain).abilities.first.to_s).to eq("other creatures you control get flying")
  end
end
