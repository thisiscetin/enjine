# frozen_string_literal: true

# Keyword filters (CR 702.1) and remembered choices: "as this enters, choose a color / creature type /
# card type / word" (CR 614.12, 607.2d, 607.2f) and the same choices made while a spell resolves.
RSpec.describe "Keyword filters and chosen values (CR 702.1, 614.12, 607.2d)" do
  let(:sky_snare) do
    { "name" => "Spec Sky Snare", "mana_cost" => "{U}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => [{ "creature" => { "keywords" => ["flying", "first strike"] } }],
                                     "effects" => [{ "tap" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:ground_snare) do
    { "name" => "Spec Ground Snare", "mana_cost" => "{1}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => [{ "creature" => { "not_keywords" => ["flying"] } }],
                                     "effects" => [{ "tap" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:wing_gift) do
    { "name" => "Spec Wing Gift", "mana_cost" => "{U}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["creature"],
                                     "effects" => [{ "grant" => { "keywords" => ["flying"], "to" => { "target" => 0 } } }] } }] }
  end
  let(:kin_banner) do
    { "name" => "Spec Kin Banner", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "choose_creature_type" => {} },
                      { "static" => { "affects" => { "each" => { "creature" => { "subtypes" => "chosen" } }, "controller" => "you" },
                                      "pump" => { "power" => 1, "toughness" => 1 } } }] }
  end
  let(:hue_totem) do
    { "name" => "Spec Hue Totem", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "choose_color" => {} },
                      { "triggered" => { "when" => { "cast" => { "spell" => { "spell" => { "colors" => "chosen" } } } },
                                         "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }
  end
  let(:hue_purge) do
    same_color = { "each" => { "creature" => { "colors" => "chosen" } } }
    { "name" => "Spec Hue Purge", "mana_cost" => "{1}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [{ "choose_color" => {} }, { "destroy" => { "to" => same_color } }] } }] }
  end
  let(:kin_call) do
    { "name" => "Spec Kin Call", "mana_cost" => "{1}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [
        { "choose_creature_type" => {} },
        { "gain_life" => { "amount" => { "count" => { "each" => { "creature" => { "subtypes" => "chosen" } } } } } }
      ] } }] }
  end
  let(:omen_coin) do
    { "name" => "Spec Omen Coin", "mana_cost" => "{1}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => [
        { "choose_option" => { "options" => %w[odd even] } },
        { "gain_life" => { "amount" => 1, "if" => { "chosen" => "odd" } } },
        { "gain_life" => { "amount" => 2, "if" => { "chosen" => "even" } } }
      ] } }] }
  end
  let(:siege_post) do
    { "name" => "Spec Siege Post", "mana_cost" => "{1}", "types" => ["enchantment"],
      "abilities" => [{ "choose_option" => { "options" => %w[khans dragons] } },
                      { "static" => { "if" => { "chosen" => "khans" }, "affects" => { "each" => "creature", "controller" => "you" },
                                      "pump" => { "power" => 1, "toughness" => 0 } } }] }
  end
  let(:type_ward) do
    { "name" => "Spec Type Ward", "mana_cost" => "{1}", "types" => ["artifact"],
      "abilities" => [{ "choose_card_type" => {} },
                      { "static" => { "affects" => { "each" => { "permanent" => { "types" => "chosen" } }, "controller" => "you" },
                                      "keywords" => ["hexproof"] } }] }
  end
  let(:catalog) do
    catalog_with(sky_snare, ground_snare, wing_gift, kin_banner, hue_totem, hue_purge, kin_call, omen_coin, siege_post, type_ward)
  end

  def game_with(hand:, board: [], opponent: [], lands: 2)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand(*hand)
        battlefield "Island", count: lands
        battlefield(*board) unless board.empty?
        library "Island", count: 5
      end
      player("bob") do
        battlefield(*opponent) unless opponent.empty?
        library "Island", count: 5
      end
    end
  end

  def cast(game, name)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(name) })
  end

  def pay(game, mana)
    mana.times do
      land = game.state.battlefield.find { game.state.object(it).card == "island" && !game.state.object(it).tapped }
      game.submit(type: "activate_mana", object: land, ability: "intrinsic:island")
    end
    game.submit(type: "pay_mana", mana: "U") while game.pending_decision.kind == "pay_cost"
  end

  def engine(game) = game.instance_variable_get(:@engine)

  def target_cards(game) = game.legal_options.filter_map { it[:target] && game.state.object(it[:target]).card }

  describe "keyword filters" do
    it "targets only creatures with (or without) the keywords, by current characteristics" do
      game = game_with(hand: ["Spec Sky Snare", "Spec Wing Gift"], board: ["Cloud Kite", "Vigil Knight"], opponent: ["Hill Giant"])
      cast(game, "Spec Sky Snare")
      expect(target_cards(game)).to contain_exactly("cloud_kite", "vigil_knight")
      game.submit(type: "cancel")
      cast(game, "Spec Wing Gift")
      game.submit(type: "target", target: obj_id(game, "Hill Giant"))
      pay(game, 1)
      pass_both(game)
      cast(game, "Spec Sky Snare")
      expect(target_cards(game)).to contain_exactly("cloud_kite", "vigil_knight", "hill_giant")
    end

    it "'without flying' excludes fliers" do
      game = game_with(hand: ["Spec Ground Snare"], board: ["Cloud Kite"], opponent: ["Hill Giant"])
      cast(game, "Spec Ground Snare")
      expect(target_cards(game)).to eq(["hill_giant"])
    end
  end

  describe "as this enters, choose" do
    it "a creature type: creatures of the chosen type get +1/+1, and the choice survives export" do
      game = game_with(hand: ["Spec Kin Banner"], board: ["Moss Grower", "Raging Goblin"])
      cast(game, "Spec Kin Banner")
      pay(game, 1)
      pass_both(game)
      expect(game.pending_decision).to have_attributes(kind: "enter_choice")
      expect(game.legal_options).to include({ type: "creature_type", creature_type: "elf" })
      game = Enjine::Game.import(game.export, catalog: catalog)
      game.submit(type: "creature_type", creature_type: "elf")
      grower = game.state.object(obj_id(game, "Moss Grower"))
      expect(engine(game).power_toughness(grower)).to eq([2, 3])
      expect(engine(game).power_toughness(game.state.object(obj_id(game, "Raging Goblin")))).to eq([1, 1])
      expect(game.state.object(obj_id(game, "Spec Kin Banner")).memory["chosen_type"]).to eq("elf")
    end

    it "a color: casting a spell of the chosen color triggers" do
      game = game_with(hand: ["Spec Hue Totem", "Spec Wing Gift", "Spec Ground Snare"], board: ["Hill Giant"], lands: 4)
      cast(game, "Spec Hue Totem")
      pay(game, 1)
      pass_both(game)
      expect(game.legal_options.map { it[:color] }).to eq(%w[W U B R G])
      game.submit(type: "color", color: "U")
      cast(game, "Spec Ground Snare") # colorless: no trigger
      game.submit(type: "target", target: obj_id(game, "Hill Giant"))
      pay(game, 1)
      expect(game.state.stack.size).to eq(1)
      pass_both(game)
      cast(game, "Spec Wing Gift")
      game.submit(type: "target", target: obj_id(game, "Hill Giant"))
      pay(game, 1)
      expect(game.state.stack.size).to eq(2)
      pass_both(game, 2)
      expect(game.state.players[0].life).to eq(21)
    end

    it "a card type: permanents of that type you control have hexproof" do
      game = game_with(hand: ["Spec Type Ward"], board: ["Hill Giant"])
      cast(game, "Spec Type Ward")
      pay(game, 1)
      pass_both(game)
      expect(game.legal_options.map { it[:card_type] }).to include("artifact", "battle", "kindred")
      game.submit(type: "card_type", card_type: "creature")
      expect(engine(game).chars(obj_id(game, "Hill Giant")).keywords).to include(:hexproof)
      expect(engine(game).chars(obj_id(game, "Spec Type Ward")).keywords).not_to include(:hexproof)
    end

    it "a word: an ability conditioned on the chosen word" do
      game = game_with(hand: ["Spec Siege Post"], board: ["Hill Giant"])
      cast(game, "Spec Siege Post")
      pay(game, 1)
      pass_both(game)
      expect(game.legal_options).to eq([{ type: "option", option: "khans" }, { type: "option", option: "dragons" }])
      game.submit(type: "option", option: "khans")
      expect(engine(game).power(game.state.object(obj_id(game, "Hill Giant")))).to eq(4)
    end
  end

  describe "choosing while resolving" do
    it "a color, then destroying each creature of that color" do
      game = game_with(hand: ["Spec Hue Purge"], board: ["Cloud Kite"], opponent: ["Hill Giant"])
      cast(game, "Spec Hue Purge")
      pay(game, 1)
      pass_both(game)
      expect(game.pending_decision).to have_attributes(kind: "effect_choice")
      game = Enjine::Game.import(game.export, catalog: catalog)
      game.submit(type: "color", color: "R")
      expect(game.state.battlefield.map { game.state.object(it).card }).to include("cloud_kite")
      expect(game.state.battlefield.map { game.state.object(it).card }).not_to include("hill_giant")
    end

    it "a creature type counted by a later effect" do
      game = game_with(hand: ["Spec Kin Call"], board: ["Moss Grower", "Brood Matron"], opponent: ["Raging Goblin"])
      cast(game, "Spec Kin Call")
      pay(game, 1)
      pass_both(game)
      game.submit(type: "creature_type", creature_type: "druid")
      expect(game.state.players[0].life).to eq(22)
    end

    it "a word, read by conditions" do
      game = game_with(hand: ["Spec Omen Coin"])
      cast(game, "Spec Omen Coin")
      pay(game, 1)
      pass_both(game)
      game.submit(type: "option", option: "even")
      expect(game.state.players[0].life).to eq(22)
    end
  end

  describe "validation" do
    def errors_for(abilities)
      Enjine::CardDefinition.from_h({ "name" => "Spec Bad", "mana_cost" => "{1}", "types" => ["sorcery"], "abilities" => abilities })
      []
    rescue Enjine::InvalidCardDefinition => e
      e.errors
    end

    def spell_with(target) = [{ "spell" => { "targets" => [target], "effects" => [{ "tap" => { "to" => { "target" => 0 } } }] } }]

    it "reports path-addressed errors" do
      expect(errors_for(spell_with({ "creature" => { "keywords" => ["soaring"] } })))
        .to include(a_string_including("abilities[0].spell.targets[0].creature.keywords: must be a non-empty list of keywords"))
      expect(errors_for(spell_with({ "creature" => { "not_keywords" => [] } })))
        .to include(a_string_including("creature.not_keywords: must be a non-empty list"))
      expect(errors_for(spell_with({ "creature" => { "supertypes" => "chosen" } })))
        .to include(a_string_including("creature.supertypes: must be a non-empty list"))
      expect(errors_for(spell_with({ "creature" => { "any_of" => "chosen" } })))
        .to include(a_string_including("creature.any_of: must be a list of card types"))
      expect(errors_for(spell_with({ "creature" => { "colors" => "red" } })))
        .to include(a_string_including("creature.colors: must be a non-empty list of W, U, B, R, G (any of them) or \"chosen\""))
      expect(errors_for([{ "choose_option" => { "options" => ["only"] } }]))
        .to include(a_string_including("abilities[0].choose_option.options: must list two or more different lowercase words"))
      expect(errors_for([{ "choose_color" => { "options" => %w[a b] } }])).to include(a_string_including("abilities[0].choose_color"))
      expect(errors_for([{ "spell" => { "effects" => [{ "choose_option" => { "options" => %w[a a] } }] } }]))
        .to include(a_string_including("spell.effects[0].choose_option.options"))
      expect(errors_for([{ "spell" => { "effects" => [{ "gain_life" => { "amount" => 1, "if" => { "chosen" => "Not A Word" } } }] } }]))
        .to include(a_string_including("effects[0].gain_life.if.chosen: must be a lowercase word"))
    end

    it "describes the filters and choices" do
      filter = Enjine::Mechanics.build_entry(:filter, { "creature" => { "keywords" => ["flying"], "not_keywords" => ["reach"],
                                                                        "subtypes" => "chosen", "not" => "chosen" } }, [], "f")
      expect(filter.to_s).to include("with flying", "without reach", "chosen-subtypes", "non-chosen-not")
      ability = Enjine::Mechanics.build_entry(:ability, { "choose_option" => { "options" => %w[odd even] } }, [], "a")
      expect(ability.to_s).to eq("as this enters, choose odd or even")
      effect = Enjine::Mechanics.build_entry(:effect, { "choose_creature_type" => {} }, [], "e")
      expect(effect.to_s).to eq("choose a creature type")
      expect(Enjine::Mechanics::Condition.build({ "chosen" => "odd" }, [], "c").to_s).to eq("odd was chosen")
    end
  end
end
