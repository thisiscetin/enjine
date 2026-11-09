# frozen_string_literal: true

RSpec.describe "Play permissions, beam me up, free casts: card data validation (unit)" do
  def errors_for(card)
    Enjine::CardDefinition.from_h({ "name" => "Probe Card", "mana_cost" => "{R}" }.merge(card))
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def spell_errors(effects) = errors_for("types" => ["sorcery"], "abilities" => [{ "spell" => { "effects" => effects } }])

  def creature(abilities, keywords: [])
    { "types" => ["creature"], "power" => 1, "toughness" => 1, "abilities" => abilities, "keywords" => keywords }
  end

  def text(card) = Enjine::CardDefinition.from_h({ "name" => "Probe Card", "mana_cost" => "{R}" }.merge(card)).abilities.map(&:to_s)

  let(:base) { "abilities[0].spell.effects[0]" }

  it "checks play_from: zone, play, cards, once_each_turn and enters_with (CR 601.3, 113.6e)" do
    expect(errors_for(creature([{ "play_from" => { "zone" => "hand", "play" => "steal", "once_each_turn" => 1,
                                                   "enters_with" => { "finality" => 0 }, "cards" => 7, "x" => 1 } }])))
      .to eq(["abilities[0].play_from: unknown parameter \"x\"",
              "abilities[0].play_from.zone: must be one of graveyard, exile, library_top, outside",
              "abilities[0].play_from.play: must be one of cast, play",
              "abilities[0].play_from.cards: must be \"card\" or an object (#{Enjine::Mechanics::CardSpec::KEYS.join(", ")})",
              "abilities[0].play_from.once_each_turn: must be true or false",
              "abilities[0].play_from.enters_with.finality: must be an integer >= 1"])
    expect(text(creature([{ "play_from" => { "zone" => "graveyard", "enters_with" => { "finality" => 1 } } },
                          { "play_from" => { "zone" => "library_top", "cards" => { "types" => ["land"] }, "play" => "play",
                                             "once_each_turn" => true } }, "look_at_top"])))
      .to eq(["you may cast this card from your graveyard; it enters with 1 finality counter(s)",
              "Once during each of your turns, you may play land cards from the top of your library",
              "Its controller sees the top card of their library (CR 401.5)"])
    expect(errors_for(creature(["look_at_top", { "look_at_top" => { "x" => 1 } }])))
      .to eq(["abilities[1].look_at_top: unknown parameter \"x\""])
  end

  it "checks play_from zones, including outside the game (CR 400.11a)" do
    expect(errors_for(creature([{ "play_from" => { "zone" => "graveyard", "zones" => ["exile"], "cards" => "card" } },
                                { "play_from" => { "zones" => %w[outside hand], "cards" => "card" } },
                                { "play_from" => { "zones" => [], "cards" => "card" } },
                                { "play_from" => { "zones" => ["outside"] } }])))
      .to eq(["abilities[0].play_from: give `zone` or `zones`, not both",
              "abilities[1].play_from.zones: must be a non-empty list of graveyard, exile, library_top, outside",
              "abilities[2].play_from.zones: must be a non-empty list of graveyard, exile, library_top, outside",
              "abilities[3].play_from.zones: \"outside\" needs a card spec in `cards`"])
    expect(text(creature([{ "play_from" => { "zones" => %w[outside graveyard], "cards" => { "permanent" => true },
                                             "play" => "play", "once_each_turn" => true } }])))
      .to eq(["Once during each of your turns, you may play permanent cards from outside the game or from your graveyard"])
  end

  it "checks play_permission to_player and cost_increase (CR 108.3, 601.2f)" do
    errors = spell_errors([{ "exile_top" => { "amount" => 1 } },
                           { "play_permission" => { "to" => { "result" => 0 }, "to_player" => "nobody", "cost_increase" => 0 } }])
    path = "abilities[0].spell.effects[1].play_permission"
    expect(errors.first).to start_with("#{path}.to_player: must be {\"target\": n}")
    expect(errors.drop(1)).to eq(["#{path}.cost_increase: must be an integer >= 1"])
    card = { "name" => "Probe Card", "mana_cost" => "{R}", "types" => ["sorcery"], "abilities" => [{ "spell" => {
      "targets" => ["opponent"], "effects" => [
        { "exile_top" => { "amount" => 1 } },
        { "play_permission" => { "to" => { "result" => 0 }, "to_player" => "owner", "cost_increase" => 2, "duration" => "while_exiled" } },
        { "play_permission" => { "to" => { "result" => 0 }, "to_player" => { "target" => 0 } } }
      ]
    } }] }
    expect(Enjine::CardDefinition.from_h(card).abilities.first.effects.drop(1).map(&:to_s))
      .to eq(["its owner may play card (while exiled, costs {2} more) → the object(s) from effect #1",
              "target #1 may play card (end of turn) → the object(s) from effect #1"])
  end

  it "checks beam me up: a mana cost, only on instants and sorceries (CR 702.196a)" do
    expect(errors_for("types" => ["sorcery"], "abilities" => [{ "beam_me_up" => { "cost" => "3W" } }]))
      .to eq(["abilities[0].beam_me_up.cost: unexpected characters in \"3W\""])
    expect(errors_for(creature([{ "beam_me_up" => { "cost" => "{2}" } }])))
      .to eq(["abilities[0]: beam_me_up abilities need a instant/sorcery card"])
    expect(errors_for(creature([{ "grants_beam_me_up" => { "x" => 1 } }])))
      .to eq(["abilities[0].grants_beam_me_up: unknown parameter \"x\""])
    expect(text("types" => ["sorcery"], "abilities" => [{ "beam_me_up" => { "cost" => "{2}{R}" } }])).to eq(["Beam me up {2}{R}"])
    expect(text(creature(["grants_beam_me_up"], keywords: ["cant_be_beamed_up"])).first).to start_with("During your main phase")
  end

  it "checks play_permission, cast_free, exile_until and discover parameters" do
    expect(spell_errors([{ "play_permission" => { "to" => "you", "duration" => "forever", "play" => "borrow",
                                                  "choose" => "all", "not_types" => ["goblin"] } }]))
      .to eq(["#{base}.play_permission.duration: must be one of end_of_turn, end_of_your_next_turn, while_exiled",
              "#{base}.play_permission.play: must be play or cast", "#{base}.play_permission.choose: must be one_per_owner",
              "#{base}.play_permission.not_types: must be a list of card types"])
    errors = spell_errors([{ "cast_free" => { "count" => 2, "max_mana_value" => "lots" } }])
    expect(errors.first).to start_with("#{base}.cast_free.max_mana_value: must be an integer >= 0, \"x\" or one of ")
    expect(errors.drop(1)).to eq(["#{base}.cast_free.count: must be 1 or \"any\""])
    expect(spell_errors([{ "exile_until" => { "until" => "creature" } }]))
      .to eq(["#{base}.exile_until.until: must be one of nonland"])
    expect(spell_errors([{ "discover" => {} }])).to eq(["#{base}.discover.amount: required"])
  end

  it "describes the effects" do
    effects = [{ "exile_top" => { "amount" => 2 } }, { "exile_until" => { "until" => "nonland" } },
               { "play_permission" => { "to" => { "result" => 0 }, "not_types" => ["land"], "duration" => "end_of_your_next_turn" } },
               { "cast_free" => { "to" => { "result" => 0 }, "count" => "any", "for" => { "types" => ["instant"] } } },
               { "cast_free" => { "to" => { "result" => 0 } } }, { "discover" => { "amount" => 3 } }]
    abilities = Enjine::CardDefinition.from_h({ "name" => "Probe Card", "mana_cost" => "{R}", "types" => ["sorcery"],
                                                "abilities" => [{ "spell" => { "effects" => effects } }] }).abilities
    expect(abilities.first.effects.map(&:to_s)).to eq(
      ["exile top 2 → you", "exile from the top until a nonland card → you",
       "you may play nonland card (end of your next turn) → the object(s) from effect #1",
       "you may cast any number of instant card free → the object(s) from effect #1",
       "you may cast a card free → the object(s) from effect #1", "discover 3 → you"]
    )
  end

  describe "engine" do
    let(:sorcery) do
      { "name" => "Probe Rite", "mana_cost" => "{R}", "types" => ["sorcery"],
        "abilities" => [{ "spell" => { "effects" => [
          { "exile_top" => { "amount" => 1, "if" => { "life" => "you", "at_most" => 5 } } },
          { "play_permission" => { "to" => { "result" => 0 }, "if" => { "life" => "you", "at_most" => 5 } } },
          { "cast_free" => { "to" => { "result" => 0 }, "if" => { "life" => "you", "at_most" => 5 } } },
          { "discover" => { "amount" => 2, "if" => { "life" => "you", "at_most" => 5 } } }
        ] } }] }
    end

    def game_for(catalog)
      build_game(catalog) do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand "Probe Rite"
          battlefield "Mountain"
          exile "Grizzly Bears"
          library "Forest", count: 3
        end
        player("bob") { library "Forest", count: 3 }
      end
    end

    it "skips each effect whose condition is false, and refuses an unknown way to play a card" do
      catalog = catalog_with(sorcery)
      game = game_for(catalog)
      game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
      game.submit(game.legal_options.find { it[:type] == "activate_mana" })
      game.submit(type: "pay_mana", mana: "R")
      pass_both(game)
      expect(game.state.exile.size).to eq(1)
      expect(game.state.effects).to be_empty
      engine = Enjine::Engine.new(catalog, game.state) { nil }
      expect { engine.play_method(0, game.state.exile.first, "self:printed:9") }.to raise_error(ArgumentError, /can't be played/)
    end

    it "ends a permission once none of its cards is still in exile (CR 400.7)" do
      catalog = catalog_with(sorcery)
      game = game_for(catalog)
      engine = Enjine::Engine.new(catalog, game.state) { nil }
      card = game.state.exile.first
      engine.grant_play_permission!(0, [card], duration: "while_exiled", play: "cast")
      engine.grant_play_permission!(0, [], duration: "while_exiled", play: "cast") # nothing to allow
      engine.expire_permissions!
      expect(game.state.effects.size).to eq(1)
      engine.move!(card, :graveyard, reason: "test")
      engine.expire_permissions!
      expect(game.state.effects).to be_empty
    end
  end
end
