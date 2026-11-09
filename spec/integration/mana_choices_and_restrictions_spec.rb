# frozen_string_literal: true

# Mana abilities whose amount is computed or whose colors are chosen as they are activated (CR 605.3b,
# 106.1a), and mana that can be spent only on some spells or abilities (CR 106.6).
RSpec.describe "Mana choices and restricted mana (CR 605.3b, 106.6)" do
  let(:spire) do
    { "name" => "Spec Academy Spire", "types" => ["land"],
      "abilities" => [{ "mana" => { "cost" => ["tap"], "color" => "any_one",
                                    "amount" => { "count" => { "each" => "creature", "controller" => "you" } } } }] }
  end
  let(:well) do
    { "name" => "Spec Prism Well", "mana_cost" => "{2}", "types" => ["artifact"],
      "abilities" => [{ "mana" => { "cost" => ["tap"], "color" => "any", "amount" => 2, "colors" => %w[R G] } }] }
  end
  let(:core) do
    { "name" => "Spec Isolinear Core", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "mana" => { "cost" => ["tap"], "produce" => "{C}",
                                    "spend_only" => { "spells" => { "types" => ["artifact"] },
                                                      "abilities" => { "types" => ["artifact"] } } } }] }
  end
  let(:golem) { { "name" => "Spec Gear Golem", "mana_cost" => "{2}", "types" => %w[artifact creature], "power" => 2, "toughness" => 2 } }
  let(:lamp) do
    { "name" => "Spec Tinker Lamp", "mana_cost" => "{3}", "types" => ["artifact"],
      "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{1}" }], "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
  end
  let(:ritual) do
    { "name" => "Spec Gear Ritual", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "effects" => [{ "add_mana" => { "produce" => "{C}{C}",
                                                                     "spend_only" => { "spells" => "card" } } }] } }] }
  end
  let(:filter) do
    { "name" => "Spec Filter Spring", "types" => ["land"],
      "abilities" => [{ "mana" => { "cost" => [{ "mana" => "{1}" }, "tap"], "color" => "any_one", "amount" => 2,
                                    "colors" => %w[W U] } }] }
  end
  let(:catalog) { catalog_with(spire, well, core, golem, lamp, ritual, filter) }

  def board(field:, hand: [], creatures: 0)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand(*hand) unless hand.empty?
        battlefield(*field)
        battlefield("Grizzly Bears", count: creatures) if creatures.positive?
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
  end

  def mana_options(game, card) = game.legal_options.select { it[:type] == "activate_mana" && it[:object] == obj_id(game, card) }
  def pool(game) = game.state.players[0].mana_pool.reject { |_, n| n.zero? }

  describe "a computed amount of one chosen color" do
    it "offers one activation per color, adding as many mana as the amount counts (CR 605.3b)" do
      game = board(field: ["Spec Academy Spire"], creatures: 2)
      options = mana_options(game, "Spec Academy Spire")
      expect(options.map { it[:mana] }).to eq(%w[{W}{W} {U}{U} {B}{B} {R}{R} {G}{G}])
      game.submit(options.find { it[:mana] == "{U}{U}" })
      expect(pool(game)).to eq(U: 2)
      expect(game.state.stack).to be_empty # a mana ability doesn't use the stack
    end

    it "pays during casting, and counts toward affordability" do
      game = board(field: ["Spec Academy Spire"], hand: ["Divination"], creatures: 3)
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(game.legal_options.find { it[:type] == "activate_mana" && it[:mana] == "{U}{U}{U}" })
      3.times { game.submit(game.legal_options.find { it[:type] == "pay_mana" }) }
      expect(game.state.stack.size).to eq(1)
      expect(pool(game)).to be_empty
    end

    it "adds nothing with an amount of 0 (one activation, no choice)" do
      game = board(field: ["Spec Academy Spire"])
      options = mana_options(game, "Spec Academy Spire")
      expect(options.map { it[:mana] }).to eq([""])
      game.submit(options.first)
      expect(pool(game)).to be_empty
      expect(game.state.object(obj_id(game, "Spec Academy Spire")).tapped).to be(true)
    end
  end

  it "\"any combination\" offers each combination of the allowed colors" do
    game = board(field: ["Spec Prism Well"])
    options = mana_options(game, "Spec Prism Well")
    expect(options.map { it[:mana] }).to contain_exactly("{R}{R}", "{R}{G}", "{G}{G}")
    game.submit(options.find { it[:mana] == "{R}{G}" })
    expect(pool(game)).to eq(R: 1, G: 1)
  end

  describe "a mana ability with a mana cost (CR 605.3a)" do
    it "is activatable only with the mana in the pool, which pays for it" do
      game = board(field: ["Spec Filter Spring", "Forest"])
      expect(mana_options(game, "Spec Filter Spring")).to be_empty
      game.submit(type: "activate_mana", object: obj_id(game, "Forest"), ability: mana_ref(game, obj_id(game, "Forest")))
      expect(mana_options(game, "Spec Filter Spring").map { it[:mana] }).to eq(%w[{W}{W} {U}{U}])
      game.submit(mana_options(game, "Spec Filter Spring").last)
      expect(pool(game)).to eq(U: 2)
    end

    it "pays colored symbols with matching mana and generic with colorless first" do
      game = board(field: ["Forest"])
      engine = Enjine::Engine.new(game.catalog, game.state) { nil }
      game.state.players[0].mana_pool.merge!(G: 2, C: 1, U: 1)
      engine.pay_from_pool!(0, Enjine::Mana::Cost.parse("{1}{G}"), nil)
      expect(pool(game)).to eq(G: 1, U: 1)
      engine.pay_from_pool!(0, Enjine::Mana::Cost.parse("{1}"), nil)
      expect(pool(game).values.sum).to eq(1)
    end

    it "is rewound with a cancelled payment, mana and all" do
      game = board(field: ["Spec Filter Spring", "Forest", "Forest", "Island"], hand: ["Divination"])
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      forest = game.legal_options.find { it[:type] == "activate_mana" && it[:object] != obj_id(game, "Spec Filter Spring") }
      game.submit(forest)
      game.submit(game.legal_options.find { it[:type] == "activate_mana" && it[:mana] == "{U}{U}" })
      game.submit(type: "cancel")
      expect(pool(game)).to be_empty
      expect(game.state.battlefield.map { game.state.object(it).tapped }).to all(be(false))
    end
  end

  describe "restricted mana (CR 106.6)" do
    it "stays apart in the pool and in the view, and empties with it (CR 500.5)" do
      game = board(field: ["Spec Isolinear Core"])
      game.submit(mana_options(game, "Spec Isolinear Core").first)
      entry = game.state.players[0].restricted_mana.first
      expect(entry["mana"]).to eq("C")
      expect(pool(game)).to be_empty
      view = game.view_for("alice")["players"][0]["restricted_mana"].first
      expect(view["text"]).to include("artifact")
      reloaded = Enjine::Game.import({ "state" => game.state.to_h }, catalog: catalog)
      expect(reloaded.state.players[0].restricted_mana).to eq([entry])
      game.submit(type: "pass") until game.step != :precombat_main
      expect(game.state.players[0].restricted_mana).to be_empty
    end

    it "can't pay for a spell the restriction doesn't allow" do
      game = board(field: ["Spec Isolinear Core", "Forest"], hand: ["Grizzly Bears"])
      expect(game.legal_options).not_to include(hash_including(type: "cast"))
    end

    it "pays for an allowed spell, offered as its own pool option" do
      game = board(field: ["Spec Isolinear Core", "Forest"], hand: ["Spec Gear Golem"])
      game.submit(mana_options(game, "Spec Isolinear Core").first)
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      expect(game.legal_options).to include({ type: "pay_mana", mana: "C", restricted: 0 })
      game.submit(type: "pay_mana", mana: "C", restricted: 0)
      game.submit(game.legal_options.find { it[:type] == "activate_mana" })
      game.submit(type: "pay_mana", mana: "G")
      expect(game.state.stack.size).to eq(1)
    end

    it "is usable for an allowed source's activated ability, and its source is offered while paying" do
      game = board(field: ["Spec Isolinear Core", "Spec Tinker Lamp"])
      game.submit(type: "activate", object: obj_id(game, "Spec Tinker Lamp"), ability: "printed:0")
      expect(game.legal_options).to include(hash_including(type: "activate_mana", object: obj_id(game, "Spec Isolinear Core")))
      game.submit(game.legal_options.find { it[:type] == "activate_mana" })
      game.submit(game.legal_options.find { it[:type] == "pay_mana" })
      expect(game.state.stack.size).to eq(1)
    end

    it "a cancelled payment gives restricted mana back (CR 734.1)" do
      game = board(field: ["Spec Isolinear Core", "Forest"], hand: ["Spec Gear Golem"])
      game.submit(mana_options(game, "Spec Isolinear Core").first)
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(type: "pay_mana", mana: "C", restricted: 0)
      game.submit(type: "cancel")
      expect(game.state.players[0].restricted_mana.size).to eq(1)
    end

    it "from a spell: `add_mana` with spend_only (spells only, not abilities)" do
      game = board(field: ["Mountain", "Spec Tinker Lamp"], hand: ["Spec Gear Ritual"])
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(game.legal_options.find { it[:type] == "activate_mana" })
      game.submit(type: "pay_mana", mana: "R")
      pass_both(game)
      expect(game.state.players[0].restricted_mana.size).to eq(2)
      expect(game.legal_options).not_to include(hash_including(type: "activate", object: obj_id(game, "Spec Tinker Lamp")))
    end
  end

  describe "validation" do
    def errors_for(mana)
      Enjine::CardDefinition.from_h("name" => "Spec Bad Source", "types" => ["land"], "abilities" => [{ "mana" => mana }])
      []
    rescue Enjine::InvalidCardDefinition => e
      e.errors
    end

    it "needs exactly one of produce and color, and a known color choice" do
      expect(errors_for("cost" => ["tap"], "produce" => "{G}", "color" => "any_one").first).to include("exactly one of produce, color")
      expect(errors_for("cost" => ["tap"], "color" => "some").first).to include("color: must be one of")
      expect(errors_for("cost" => ["tap"], "produce" => "{G}", "colors" => %w[R G]).first).to include("colors: must list")
    end

    it "checks spend_only" do
      expect(errors_for("cost" => ["tap"], "produce" => "{C}", "spend_only" => { "lands" => "card" }).first)
        .to include("spend_only: must be")
      expect(errors_for("cost" => ["tap"], "produce" => "{C}", "spend_only" => { "spells" => { "types" => ["wizard"] } }).first)
        .to include("spend_only.spells.types")
    end

    it "describes the abilities" do
      expect(Enjine::CardDefinition.from_h(spire).ability_instances.first.ability.to_s).to include("any one color")
      expect(Enjine::CardDefinition.from_h(well).ability_instances.first.ability.to_s).to include("(R/G)")
      expect(Enjine::CardDefinition.from_h(core).ability_instances.first.ability.to_s).to include("Spend this mana only")
    end

    it "rejects malformed restricted pool entries in a snapshot" do
      game = board(field: ["Forest"])
      data = game.state.to_h
      data["players"][0]["restricted_mana"] = [{ "mana" => "Q", "spend_only" => {} }]
      expect { Enjine::Game.import({ "state" => data }, catalog: catalog) }.to raise_error(Enjine::InvalidSnapshot, /restricted_mana\[0\]/)
    end
  end
end
