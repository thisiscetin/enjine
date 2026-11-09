# frozen_string_literal: true

# Costs paid while casting or activating (CR 118.3, 601.2h, 602.2b): discarding, paying life, exiling cards from
# a graveyard, beholding; monocolored hybrid mana (CR 107.4e); improvise (CR 702.126); mana of the chosen color
# (CR 607.2d) and "activate only once" (CR 602.5b).
RSpec.describe "Costs and mana (CR 118.3, 119.4, 701.4, 701.9, 107.4e, 702.126, 602.5b)" do
  def draw(n = 1) = [{ "draw" => { "amount" => n } }]
  def creature(name, extra) = { "name" => name, "types" => ["creature"], "power" => 1, "toughness" => 1, "mana_cost" => "{R}" }.merge(extra)

  def activated(cost, effects = draw, **more)
    { "activated" => { "cost" => cost, "effects" => effects }.merge(more.transform_keys(&:to_s)) }
  end

  let(:cards) do
    [creature("Spec Rummager", "abilities" => [activated([{ "mana" => "{1}" }, "discard"])]),
     creature("Spec Land Tosser", "abilities" => [activated([{ "discard" => { "card" => { "types" => ["land"] } } }],
                                                            [{ "gain_life" => { "amount" => 3 } }])]),
     creature("Spec Chaos Gambler", "abilities" => [activated([{ "discard" => { "count" => 2, "random" => true } }], draw(3))]),
     creature("Spec Bone Collector", "abilities" => [activated([{ "exile_from_graveyard" => { "count" => 2 } }],
                                                               [{ "gain_life" => { "amount" => 2 } }])]),
     creature("Spec Blood Pact", "abilities" => [activated([{ "pay_life" => 2 }],
                                                           [{ "pump" => { "power" => 2, "toughness" => 2, "to" => "self" } }],
                                                           limit: "once_each_turn")]),
     { "name" => "Spec Blood Town", "types" => ["land"],
       "abilities" => [{ "mana" => { "cost" => ["tap", { "pay_life" => 1 }], "color" => "any_one" } }] },
     { "name" => "Spec Blood Tithe", "types" => ["sorcery"], "mana_cost" => "{B}",
       "abilities" => [{ "additional_cost" => { "cost" => [{ "pay_life" => "X" }] } }, { "spell" => { "effects" => draw("x") } }] },
     creature("Spec Blood Engine", "abilities" => [activated([{ "mana" => "{X}" }, { "pay_life" => "X" }],
                                                             [{ "add_counters" => { "counter" => "+1/+1", "amount" => "x",
                                                                                    "to" => "self" } }])]),
     { "name" => "Spec Hybrid Bolt", "types" => ["instant"], "mana_cost" => "{2/R}",
       "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                      "effects" => [{ "deal_damage" => { "amount" => 2, "to" => { "target" => 0 } } }] } }] },
     creature("Spec Goblin Scout", "subtypes" => ["goblin"]),
     creature("Spec Goblin Champion", "mana_cost" => "{1}{R}", "subtypes" => ["goblin"], "abilities" => [
                { "additional_cost" => { "cost" => [{ "behold" => { "card" => { "subtypes" => ["goblin"] }, "exile" => true } }] } },
                { "triggered" => { "when" => { "leaves_battlefield" => {} },
                                   "effects" => [{ "return_to_hand" => { "to" => "exiled_with" } }] } }
              ]),
     creature("Spec Dragon Seeker", "abilities" => [{ "triggered" => { "when" => { "enters" => {} }, "effects" => [{ "may" => {
                "effects" => [{ "behold" => { "card" => { "subtypes" => ["dragon"] } } }], "then" => [{ "gain_life" => { "amount" => 3 } }]
              } }] } }]),
     creature("Spec Dragon Whelp", "subtypes" => ["dragon"]),
     creature("Spec Librarian", "abilities" => [activated([{ "mana" => "{1}" }], draw, limit: "once")]),
     { "name" => "Spec Haven", "types" => ["land"],
       "abilities" => [{ "choose_color" => {} }, { "mana" => { "cost" => ["tap"], "color" => "chosen" } }] },
     { "name" => "Spec Gadget Insight", "types" => ["sorcery"], "mana_cost" => "{3}{U}", "keywords" => ["improvise"],
       "abilities" => [{ "spell" => { "effects" => draw(2) } }] },
     { "name" => "Spec Cog", "types" => ["artifact"], "mana_cost" => "{1}" }]
  end
  let(:catalog) { catalog_with(*cards) }

  def board(life: 20, &)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", life: life) do
        instance_eval(&)
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
  end

  def activate(game, name)
    option = game.legal_options.find { it[:type] == "activate" && it[:object] == obj_id(game, name) }
    raise "#{name} can't be activated: #{game.legal_options}" unless option

    game.submit(option)
  end

  def tap_land(game) = game.submit(game.legal_options.find { it[:type] == "activate_mana" })
  def pay(game) = game.submit(game.legal_options.find { it[:type] == "pay_mana" })
  def hand(game) = ids_in(game, "alice", :hand)
  def cards_in(game, zone) = ids_in(game, "alice", zone).map { game.state.object(it).card }

  def cast(game, name)
    game.submit(type: "cast", object: hand(game).find { game.state.object(it).card == Enjine::CardDefinition.slug(name) })
  end

  def alice(game) = game.state.players[0]

  describe "discarding as a cost (CR 701.9a-b, 601.2h)" do
    it "discards a chosen card as the ability becomes activated, and needs a card to discard (CR 118.3)" do
      game = board do
        battlefield "Spec Rummager", "Mountain"
      end
      expect(option_types(game)).not_to include("activate")
      game = board do
        battlefield "Spec Rummager", "Mountain"
        hand "Forest", "Grizzly Bears"
      end
      activate(game, "Spec Rummager")
      expect(game.pending_decision.kind).to eq("choose_cost")
      bears = obj_id(game, "Grizzly Bears", zone: :hand, player: "alice")
      game.submit(type: "cost", object: bears)
      expect(hand(game)).to include(bears) # discarded as it becomes activated
      tap_land(game)
      pay(game)
      expect(cards_in(game, :graveyard)).to eq(["grizzly_bears"])
      moved = game.history.flat_map(&:events).grep(Enjine::Events::ZoneChanged).last
      expect([moved.card, moved.reason]).to eq(%w[grizzly_bears discard])
    end

    it "discards only a card matching the spec" do
      game = board do
        battlefield "Spec Land Tosser"
        hand "Forest", "Grizzly Bears"
      end
      activate(game, "Spec Land Tosser")
      expect(game.legal_options.select do
        it[:type] == "cost"
      end.map { it[:object] }).to eq([obj_id(game, "Forest", zone: :hand, player: "alice")])
      game.submit(game.legal_options.first)
      expect([cards_in(game, :graveyard), alice(game).life]).to eq([["forest"], 20])
      pass_both(game)
      expect(alice(game).life).to eq(23)
    end

    it "discards at random without a choice, and needs enough cards" do
      game = board do
        battlefield "Spec Chaos Gambler"
        hand "Forest"
      end
      expect(option_types(game)).not_to include("activate")
      game = board do
        battlefield "Spec Chaos Gambler"
        hand "Forest", "Grizzly Bears", "Mountain"
      end
      activate(game, "Spec Chaos Gambler")
      expect(game.pending_decision.kind).to eq("priority")
      expect([hand(game).size, ids_in(game, "alice", :graveyard).size]).to eq([1, 2])
    end
  end

  it "exiles chosen cards from your graveyard as a cost (CR 406.1, 601.2h)" do
    game = board do
      battlefield "Spec Bone Collector"
      graveyard "Forest"
    end
    expect(option_types(game)).not_to include("activate")
    game = board do
      battlefield "Spec Bone Collector"
      graveyard "Forest", "Grizzly Bears", "Mountain"
    end
    activate(game, "Spec Bone Collector")
    2.times { game.submit(game.legal_options.find { it[:type] == "cost" }) }
    expect([ids_in(game, "alice", :graveyard).size, game.state.exile.size]).to eq([1, 2])
  end

  describe "paying life (CR 119.4, 118.3b)" do
    it "pays life as the ability is activated, only with that much life" do
      game = board(life: 1) { battlefield "Spec Blood Pact" }
      expect(option_types(game)).not_to include("activate")
      game = board(life: 2) { battlefield "Spec Blood Pact" }
      activate(game, "Spec Blood Pact")
      expect(alice(game).life).to eq(0)
    end

    it "pays life for a mana ability, which then can't be cancelled" do
      game = board { battlefield "Spec Blood Town" }
      game.submit(game.legal_options.find { it[:type] == "activate_mana" && it[:mana] == "{B}" })
      expect([alice(game).life, alice(game).mana_pool[:B]]).to eq([19, 1])
    end

    it "announces X for 'pay X life' as an additional cost, at most the life total (CR 601.2b)" do
      game = board(life: 3) do
        hand "Spec Blood Tithe"
        battlefield "Swamp"
      end
      cast(game, "Spec Blood Tithe")
      expect(game.pending_decision.kind).to eq("choose_x")
      expect(game.legal_options.filter_map { it[:value] }.max).to eq(3)
      game.submit(type: "x", value: 2)
      tap_land(game)
      pay(game)
      expect(alice(game).life).to eq(1)
      expect(game.state.object(game.state.stack.first).x).to eq(2)
      pass_both(game)
      expect(hand(game).size).to eq(2)
    end

    it "pays {X} and X life for an ability, X bounded by both mana and life" do
      game = board(life: 5) { battlefield "Spec Blood Engine", "Swamp", "Swamp" }
      activate(game, "Spec Blood Engine")
      expect(game.legal_options.filter_map { it[:value] }.max).to eq(2)
      game.submit(type: "x", value: 2)
      2.times do
        tap_land(game)
        pay(game)
      end
      expect(alice(game).life).to eq(3)
      pass_both(game)
      expect(game.state.object(obj_id(game, "Spec Blood Engine")).counters).to eq("+1/+1" => 2)
    end
  end

  describe "monocolored hybrid {2/R} (CR 107.4e, 202.3f)" do
    it "is paid with one red mana or two mana of any type" do
      { %w[Mountain] => 1, %w[Forest Forest] => 2 }.each do |lands, taps|
        game = board do
          hand "Spec Hybrid Bolt"
          battlefield(*lands)
        end
        cast(game, "Spec Hybrid Bolt")
        game.submit(type: "target", target: "player:bob")
        taps.times do
          tap_land(game)
          pay(game)
        end
        expect(game.state.stack.size).to eq(1), lands.join
        expect(game.pending_decision.kind).to eq("priority")
      end
    end

    it "can't be cast with a single non-red mana" do
      game = board do
        hand "Spec Hybrid Bolt"
        battlefield "Forest"
      end
      expect(option_types(game)).not_to include("cast")
    end
  end

  describe "behold (CR 701.4)" do
    it "beholds a Goblin you control or one in your hand, exiles it, and returns it when the champion leaves (CR 607.2a)" do
      game = board do
        hand "Spec Goblin Champion", "Spec Goblin Scout"
        battlefield "Mountain", "Mountain"
      end
      cast(game, "Spec Goblin Champion")
      scout = obj_id(game, "Spec Goblin Scout", zone: :hand, player: "alice")
      expect(game.legal_options.select { it[:type] == "cost" }.map { it[:object] }).to eq([scout])
      game.submit(type: "cost", object: scout)
      expect(game.history.last.events.map(&:type)).to include("card_revealed")
      2.times do
        tap_land(game)
        pay(game)
      end
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["spec_goblin_scout"])
      pass_both(game)
      champion = obj_id(game, "Spec Goblin Champion")
      game.instance_variable_get(:@engine).move!(champion, :graveyard, reason: "destroy")
      game.submit(type: "pass") until game.state.stack.empty? && game.pending_decision.kind == "priority" &&
                                      cards_in(game, :hand).include?("spec_goblin_scout")
      expect(game.state.exile.map { game.state.object(it).card }).to be_empty
    end

    it "can't be cast without something to behold" do
      game = board do
        hand "Spec Goblin Champion"
        battlefield "Mountain", "Mountain"
      end
      expect(option_types(game)).not_to include("cast")
    end

    it "may behold a Dragon as an effect: yes is offered only with one" do
      [["Spec Dragon Whelp", 23], [nil, 20]].each do |whelp, life|
        game = board do
          hand "Spec Dragon Seeker"
          battlefield "Mountain"
          battlefield whelp if whelp
        end
        cast(game, "Spec Dragon Seeker")
        tap_land(game)
        pay(game)
        pass_both(game)
        pass_both(game) if game.state.stack.any?
        while game.pending_decision.kind == "effect_choice"
          game.submit(game.legal_options.find { %w[yes behold].include?(it[:type]) } || game.legal_options.first)
        end
        expect(alice(game).life).to eq(life)
      end
    end
  end

  it "activates an 'activate only once' ability once for as long as the object exists (CR 602.5b)" do
    game = board { battlefield "Spec Librarian", "Forest", "Forest" }
    activate(game, "Spec Librarian")
    tap_land(game)
    pay(game)
    pass_both(game)
    skip_to(game, :precombat_main, turn: 5)
    expect(game.legal_options.none? { it[:type] == "activate" && it[:object] == obj_id(game, "Spec Librarian") }).to be(true)
  end

  it "adds one mana of the color chosen as the land entered (CR 607.2d)" do
    game = board { hand "Spec Haven" }
    game.submit(type: "play_land", object: hand(game).first)
    game.submit(game.legal_options.find { it[:color] == "U" }) if game.pending_decision.kind != "priority"
    option = game.legal_options.find { it[:type] == "activate_mana" }
    expect(option).not_to have_key(:mana)
    game.submit(option)
    expect(alice(game).mana_pool[:U]).to eq(1)
  end

  describe "improvise (CR 702.126)" do
    it "taps artifacts for generic mana only" do
      game = board do
        hand "Spec Gadget Insight"
        battlefield "Spec Cog", count: 3
        battlefield "Island"
      end
      cast(game, "Spec Gadget Insight")
      improvise = game.legal_options.select { it[:type] == "improvise" }
      expect(improvise.size).to eq(3)
      3.times { game.submit(game.legal_options.find { it[:type] == "improvise" }) }
      expect(game.legal_options.map { it[:type] }).not_to include("improvise")
      tap_land(game)
      pay(game)
      expect(game.state.stack.size).to eq(1)
    end

    it "isn't castable when the artifacts can't pay the colored part" do
      game = board do
        hand "Spec Gadget Insight"
        battlefield "Spec Cog", count: 4
      end
      expect(option_types(game)).not_to include("cast")
    end
  end
end
