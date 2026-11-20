# frozen_string_literal: true

# Primitives that let more real cards be written exactly (docs/plans/dsl-gaps.md, ranking of 2026-11-20):
# who put counters (CR 122.6a), ownership filters (CR 108.3), more card-spec qualities, and durations counted
# in a player's turns (CR 611.2a).
RSpec.describe "DSL reach: counters you put, ownership, card qualities, turn durations" do
  def engine(game) = game.instance_variable_get(:@engine)
  def pay(game) = (game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost")

  let(:grow_charm) do
    { "name" => "Grow Charm", "mana_cost" => "{G}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["creature"],
                                     "effects" => [{ "add_counters" => { "counter" => "+1/+1", "amount" => 1,
                                                                         "to" => { "target" => 0 } } }] } }] }
  end
  let(:tally_keeper) do
    { "name" => "Tally Keeper", "mana_cost" => "{1}{G}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "triggered" => { "when" => { "counters_placed" => {
        "subject" => { "each" => "creature", "controller" => "you" }, "counter" => "+1/+1", "by" => "you"
      } }, "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
  end

  describe "counters_placed by: you (CR 122.6a)" do
    def board(caster)
      build_game(catalog_with(grow_charm, tally_keeper)) do
        turn 3, active: caster, step: :precombat_main
        player("alice", mana_pool: { G: 1 }) do
          battlefield "Tally Keeper", "Grizzly Bears"
          hand "Grow Charm" if caster == "alice"
          library "Forest", count: 5
        end
        player("bob", mana_pool: { G: 1 }) do
          hand "Grow Charm" if caster == "bob"
          library "Forest", count: 5
        end
      end
    end

    def grow(game, caster)
      game.submit(type: "cast", object: obj_id(game, "Grow Charm", zone: :hand, player: caster))
      game.submit(type: "target", target: obj_id(game, "Grizzly Bears"))
      pay(game)
      game.submit(type: "pass") until game.state.stack.empty?
    end

    it "triggers on counters you put" do
      game = board("alice")
      grow(game, "alice")
      expect(game.state.players[0].life).to eq(21)
    end

    it "doesn't trigger on counters an opponent puts on your creature" do
      game = board("bob")
      grow(game, "bob")
      expect(engine(game).object(obj_id(game, "Grizzly Bears")).counters["+1/+1"]).to eq(1)
      expect(game.state.players[0].life).to eq(20)
    end

    it "reads as the card does and rejects other values" do
      defn = Enjine::CardDefinition.from_h(tally_keeper)
      expect(defn.abilities.first.to_s).to start_with("Whenever you put one or more +1/+1 counters on")
      bad = tally_keeper.merge("abilities" => [{ "triggered" => { "when" => { "counters_placed" => { "by" => "anyone" } },
                                                                  "effects" => [{ "gain_life" => { "amount" => 1 } }] } }])
      expect do
        Enjine::CardDefinition.from_h(bad)
      end.to raise_error(Enjine::InvalidCardDefinition, /counters_placed.by: must be you or opponent/)
    end

    it "keeps who put them in the event" do
      game = board("alice")
      grow(game, "alice")
      event = game.history.flat_map(&:events).grep(Enjine::Events::CountersChanged).last
      expect(event.by).to eq("alice")
      expect(Enjine::Events.from_h(event.to_h.except("by")).by).to be_nil # older histories
    end
  end

  describe "owner filters (CR 108.3)" do
    let(:reclaim) do
      { "name" => "Reclaim the Stolen", "mana_cost" => "{U}", "types" => ["instant"],
        "abilities" => [{ "spell" => { "targets" => [{ "creature" => { "owner" => "you" } }],
                                       "effects" => [{ "return_to_hand" => { "to" => { "target" => 0 } } }] } }] }
    end
    let(:turncoat_banner) do
      { "name" => "Turncoat Banner", "mana_cost" => "{2}", "types" => ["artifact"],
        "abilities" => [{ "static" => { "affects" => { "each" => { "creature" => { "controller" => "you", "owner" => "opponent" } } },
                                        "pump" => { "power" => 2, "toughness" => 0 } } }] }
    end

    # alice owns a Grizzly Bears bob controls; bob owns a Cloud Kite alice controls.
    def swapped
      game = build_game(catalog_with(reclaim, turncoat_banner)) do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { U: 1 }) do
          hand "Reclaim the Stolen"
          battlefield "Grizzly Bears", "Turncoat Banner"
          library "Forest", count: 5
        end
        player("bob") do
          battlefield "Cloud Kite"
          library "Forest", count: 5
        end
      end
      bears = obj_id(game, "Grizzly Bears")
      kite = obj_id(game, "Cloud Kite")
      context = ->(index) { Enjine::Mechanics::EffectContext.new(index, nil, nil, []) }
      engine(game).gain_control_for!(engine(game).object(bears), 1, context.call(1))
      engine(game).gain_control_for!(engine(game).object(kite), 0, context.call(0))
      [game, bears, kite]
    end

    it "targets only creatures you own, whoever controls them" do
      game, bears, = swapped
      game.submit(type: "cast", object: obj_id(game, "Reclaim the Stolen", zone: :hand, player: "alice"))
      expect(game.legal_options.select { it[:type] == "target" }.map { it[:target] }).to eq([bears])
    end

    it "applies to statics: creatures you control but don't own" do
      game, bears, kite = swapped
      expect(engine(game).power(engine(game).object(kite))).to eq(3)
      expect(engine(game).power(engine(game).object(bears))).to eq(2)
      errors = []
      filter = Enjine::Mechanics.build_entry(:filter, { "creature" => { "controller" => "you", "owner" => "opponent" } }, errors, "f")
      expect(filter.to_s).to eq("creature you control an opponent owns")
    end

    it "rejects other values" do
      bad = reclaim.merge("abilities" => [{ "spell" => { "targets" => [{ "creature" => { "owner" => "me" } }], "effects" => [] } }])
      expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition, /owner: must be you or opponent/)
    end
  end

  describe "card spec qualities" do
    let(:pool) do
      [{ "name" => "Hill Kite", "mana_cost" => "{1}{W}", "types" => ["creature"], "subtypes" => ["bird"], "power" => 1,
         "toughness" => 1, "keywords" => ["flying"] },
       { "name" => "Hill Avatar", "mana_cost" => "{3}", "types" => ["creature"], "subtypes" => ["avatar"], "power" => 4, "toughness" => 4 }]
    end

    def spec(data)
      errors = []
      Enjine::Mechanics::CardSpec.build(data, errors, "spec").tap { expect(errors).to eq([]) }
    end

    def graveyard_game
      cards = pool
      build_game(catalog_with(*cards)) do
        player("alice") do
          graveyard "Hill Kite", "Hill Avatar", "Thornhedge Knight // Clear the Thicket"
          library "Forest", count: 5
        end
        player("bob") { library "Forest", count: 5 }
      end
    end

    def matching(game, data)
      game.state.players[0].graveyard.select { spec(data).match?(engine(game), engine(game).object(it)) }
                           .map { engine(game).definition(engine(game).object(it)).name }
    end

    it "matches keywords, non-subtypes, power and toughness, and layout" do
      game = graveyard_game
      expect(matching(game, { "keywords" => ["flying"] })).to eq(["Hill Kite"])
      expect(matching(game, { "types" => ["creature"], "not_subtypes" => ["avatar"] })).to contain_exactly("Hill Kite", "Thornhedge Knight")
      expect(matching(game, { "power" => { "at_most" => 1 } })).to eq(["Hill Kite"])
      expect(matching(game, { "toughness" => { "at_least" => 4 } })).to eq(["Hill Avatar"])
      expect(matching(game, { "layout" => "adventure" })).to eq(["Thornhedge Knight"])
    end

    it "describes itself and reports bad values" do
      expect(spec({ "types" => ["creature"], "keywords" => ["flying"], "not_subtypes" => ["avatar"] }).to_s)
        .to eq("non-Avatar creature card with flying")
      expect(spec({ "layout" => "adventure" }).to_s).to eq("card that has an Adventure")
      expect(spec({ "power" => { "at_most" => 1 } }).to_s).to eq("card with power at most 1")
      expect(spec({ "power" => { "at_most" => 1 } }).any?).to be(false)
      errors = []
      Enjine::Mechanics::CardSpec.build({ "layout" => "split", "keywords" => ["nope"], "not_subtypes" => ["Bad Type!"] }, errors, "s")
      expect(errors.join("\n")).to include("s.layout: must be one of", "s.keywords: unknown keyword", "s.not_subtypes: invalid subtype")
    end
  end

  describe "durations in a player's own turns (CR 611.2a)" do
    def duel(extra = [])
      build_game(catalog_with(*extra)) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          battlefield "Grizzly Bears"
          library "Forest", count: 20
        end
        player("bob") do
          battlefield "Cloud Kite"
          exile "Lightning Bolt"
          library "Forest", count: 20
        end
      end
    end

    let(:ctx) { ->(_game) { Enjine::Mechanics::EffectContext.new(0, nil, nil, []) } }

    it "become_copy until_your_next_turn lasts through the opponent's turn" do
      game = duel
      bears = engine(game).object(obj_id(game, "Grizzly Bears"))
      engine(game).become_copy!(bears, ["cloud_kite", {}], duration: "until_your_next_turn", controller: 0)
      skip_to(game, :upkeep, turn: 4)
      expect(engine(game).object(bears.id).card).to eq("cloud_kite")
      skip_to(game, :upkeep, turn: 5)
      expect(engine(game).object(bears.id).card).to eq("grizzly_bears")
    end

    it "parses the new become_copy duration" do
      card = { "name" => "Mimic", "mana_cost" => "{U}", "types" => ["instant"],
               "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [{ "become_copy" => {
                 "to" => { "target" => 0 }, "of" => { "target" => 0 }, "duration" => "until_your_next_turn"
               } }] } }] }
      expect(Enjine::CardDefinition.from_h(card).abilities.first.try_effects.first.to_s).to include("(until your next turn)")
    end

    it "gain_control end_of_your_next_turn returns control after your next turn's cleanup" do
      game = duel
      kite = engine(game).object(obj_id(game, "Cloud Kite"))
      engine(game).gain_control_for!(kite, 0, ctx.call(game), duration: "end_of_your_next_turn")
      skip_to(game, :upkeep, turn: 4)
      expect(engine(game).object(kite.id).controller).to eq(0)
      skip_to(game, :end, turn: 5)
      expect(engine(game).object(kite.id).controller).to eq(0)
      skip_to(game, :upkeep, turn: 6)
      expect(engine(game).object(kite.id).controller).to eq(1)
      expect(game.state.effects).to be_empty
    end

    it "gain_control reads its new duration" do
      card = { "name" => "Thrall", "mana_cost" => "{B}", "types" => ["sorcery"],
               "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [{ "gain_control" => {
                 "to" => { "target" => 0 }, "duration" => "end_of_your_next_turn"
               } }] } }] }
      expect(Enjine::CardDefinition.from_h(card).abilities.first.try_effects.first.to_s).to include("until the end of your next turn")
    end

    def permission(game) = game.state.effects.select { it["kind"] == "permission" }

    it "until_your_next_end_step, granted in your main phase, ends as this turn's end step begins" do
      game = duel
      bolt = game.state.exile.first
      engine(game).grant_play_permission!(0, [bolt], duration: "until_your_next_end_step", play: "play")
      skip_to(game, :postcombat_main, turn: 3)
      expect(permission(game).size).to eq(1)
      skip_to(game, :end, turn: 3)
      expect(permission(game)).to be_empty
    end

    it "until_your_next_end_step, granted during your end step, lasts until next turn's" do
      game = duel
      skip_to(game, :end, turn: 3)
      engine(game).grant_play_permission!(0, [game.state.exile.first], duration: "until_your_next_end_step", play: "play")
      skip_to(game, :postcombat_main, turn: 5)
      expect(permission(game).size).to eq(1)
      skip_to(game, :end, turn: 5)
      expect(permission(game)).to be_empty
    end

    it "until_your_next_end_step, granted on the opponent's turn, lasts until your next end step" do
      game = duel
      skip_to(game, :upkeep, turn: 4)
      engine(game).grant_play_permission!(0, [game.state.exile.first], duration: "until_your_next_end_step", play: "play")
      skip_to(game, :end, turn: 4)
      expect(permission(game).size).to eq(1)
      skip_to(game, :end, turn: 5)
      expect(permission(game)).to be_empty
    end
  end
end
