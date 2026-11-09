# frozen_string_literal: true

RSpec.describe "Library, hand and graveyard effects, edicts and linked exile: card data validation (unit)" do
  def errors_for(effects, targets: [])
    card = { "name" => "Probe Card", "mana_cost" => "{R}", "types" => ["instant"],
             "abilities" => [{ "spell" => { "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? } }] }
    Enjine::CardDefinition.from_h(card)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def effect(data, targets: [])
    Enjine::CardDefinition.from_h({ "name" => "Probe Card", "mana_cost" => "{R}", "types" => ["instant"],
                                    "abilities" => [{ "spell" => { "targets" => targets, "effects" => [data] }
                                                                   .reject { |_, v| v.empty? } }] }).spell_ability.effects.first
  end

  def spec_errors(data)
    errors = []
    Enjine::Mechanics::CardSpec.build(data, errors, "s")
    errors
  end

  let(:base) { "abilities[0].spell.effects[0]" }

  describe "card specs (CR 110.4a, 202.3)" do
    it "validates not_types, permanent and mana_value by path" do
      expect(spec_errors({ "not_types" => ["spaceship"] })).to eq(['s.not_types: unknown type "spaceship"'])
      expect(spec_errors({ "permanent" => false })).to eq(["s.permanent: must be true"])
      expect(spec_errors({ "mana_value" => 3 })).to eq(['s.mana_value: must be {"at_least"|"at_most"|"equal": amount}'])
      expect(spec_errors({ "mana_value" => { "below" => 3 } })).to eq(['s.mana_value: must be {"at_least"|"at_most"|"equal": amount}'])
      expect(spec_errors({ "mana_value" => { "at_most" => "lots" } }).first).to start_with("s.mana_value.at_most: must be")
      expect(spec_errors({ "permanent" => true, "not_types" => ["land"], "mana_value" => { "at_most" => 3 } })).to be_empty
    end

    it "describes them" do
      describe = ->(data) { Enjine::Mechanics::CardSpec.build(data, [], "s").to_s }
      expect(describe.call({ "not_types" => %w[creature land] })).to eq("noncreature nonland card")
      expect(describe.call({ "permanent" => true, "mana_value" => { "at_most" => 3 } }))
        .to eq("permanent card with mana value at most 3")
      expect(Enjine::Mechanics::CardSpec.build({ "permanent" => true }, [], "s")).not_to be_any
    end

    it "matches by current characteristics; amount bounds need an effect context" do
      game = build_game(catalog_with) do
        player("alice") do
          library "Grizzly Bears", "Forest", "Lightning Bolt"
        end
        player("bob") { library "Forest" }
      end
      engine = game.instance_variable_get(:@engine)
      bears, forest, bolt = game.state.players[0].library.map { game.state.object(it) }
      spec = ->(data) { Enjine::Mechanics::CardSpec.build(data, [], "s") }
      expect([bears, forest, bolt].map { spec.call({ "permanent" => true }).match?(engine, it) }).to eq([true, true, false])
      expect([bears, forest, bolt].map { spec.call({ "not_types" => ["land"] }).match?(engine, it) }).to eq([true, false, true])
      at_most_one = spec.call({ "mana_value" => { "at_most" => 1 } })
      expect([bears, forest, bolt].map { at_most_one.match?(engine, it) }).to eq([false, true, true])
      expect(spec.call({ "mana_value" => { "equal" => 2 } }).match?(engine, bears)).to be(true)
      x_bound = spec.call({ "mana_value" => { "at_least" => "x" } })
      expect(x_bound.match?(engine, bears)).to be(false) # no context: a computed bound can't be met
      ctx = Enjine::Mechanics::EffectContext.new(0, nil, nil, [], [])
      expect(x_bound.match?(engine, bears, ctx)).to be(true) # X is 0 here
    end
  end

  it "checks dig's amount, count, put, reveal, rest and flags (CR 701.20, 401.4)" do
    expect(errors_for([{ "dig" => {} }])).to eq(["#{base}.dig.amount: required"])
    expect(errors_for([{ "dig" => { "amount" => 3, "count" => 0, "put" => "exile", "reveal" => "some", "rest" => "top",
                                    "optional" => "yes", "tapped" => 1 } }]))
      .to eq(["#{base}.dig.count: must be a positive integer, \"all\" or \"any\"", "#{base}.dig.optional: must be true or false",
              "#{base}.dig.put: must be one of hand, battlefield, graveyard", "#{base}.dig.tapped: must be true or false",
              "#{base}.dig.reveal: must be one of none, chosen, all",
              "#{base}.dig.rest: must be one of bottom_random, bottom_any, graveyard"])
    expect(effect({ "dig" => { "amount" => 6, "for" => { "types" => ["artifact"] }, "optional" => true } }).to_s)
      .to eq("look at the top 6 cards, up to 1 artifact card → hand, rest → bottom random")
    expect(effect({ "dig" => { "amount" => 5, "reveal" => "all", "count" => "all", "rest" => "graveyard" } }).to_s)
      .to eq("reveal the top 5 cards, all card → hand, rest → graveyard")
  end

  it "checks reveal_until and exile_top" do
    errors = errors_for([{ "reveal_until" => { "count" => -1, "put" => "graveyard" } }])
    expect(errors.first).to start_with("#{base}.reveal_until.count: must be an integer >= 0, \"x\" or one of ")
    expect(errors.drop(1)).to eq(["#{base}.reveal_until.put: must be one of hand, battlefield"])
    expect(effect({ "reveal_until" => { "for" => { "types" => ["land"] }, "count" => 2, "put" => "battlefield", "tapped" => true } }).to_s)
      .to eq("reveal until 2 land card → battlefield tapped, rest → bottom random")
    expect(errors_for([{ "exile_top" => { "amount" => 2, "link" => "yes" } }])).to eq(["#{base}.exile_top.link: must be true or false"])
  end

  it "checks choose_cards' from, count, put, reveal and nested lists" do
    expect(errors_for([{ "choose_cards" => {} }])).to eq(["#{base}.choose_cards.from: required",
                                                          "#{base}.choose_cards.put: must be one of hand, graveyard, exile, " \
                                                          "battlefield, library_top, library_bottom"])
    expect(errors_for([{ "choose_cards" => { "from" => { "hand" => { "target" => 0 } }, "count" => "few", "put" => "hand",
                                             "reveal" => "some", "otherwise" => [{ "exile" => { "to" => { "result" => 0 } } }] } }]))
      .to eq(["#{base}.choose_cards.from.hand.target: must refer to one of the 0 declared targets",
              "#{base}.choose_cards.count: must be a positive integer or \"any\"",
              "#{base}.choose_cards.reveal: must be one of chosen, all",
              "#{base}.choose_cards.otherwise[0].exile.to.result: must refer to one of the 0 earlier effects"])
    choose = effect({ "choose_cards" => { "from" => { "graveyard" => "you" }, "count" => "any", "put" => "library_bottom" } })
    expect(choose.to_s).to eq("choose any number of card from the graveyard of you → library bottom")
    expect(effect({ "choose_cards" => { "from" => "exiled_with", "optional" => true, "put" => "hand" } }).to_s)
      .to eq("choose up to 1 card from the cards exiled with it → hand")
  end

  it "checks sacrifice_choice, put_in_library and the small zone effects" do
    expect(errors_for([{ "sacrifice_choice" => { "count" => 0 } }]))
      .to eq(["#{base}.sacrifice_choice.filter: required", "#{base}.sacrifice_choice.count: must be a positive integer or \"any\""])
    expect(effect({ "sacrifice_choice" => { "filter" => "creature", "to" => "each_opponent" } }).to_s)
      .to eq("each opponent sacrifices 1 creature of their choice")
    expect(errors_for([{ "put_in_library" => { "to" => "self", "position" => "middle" } }]))
      .to eq(["#{base}.put_in_library.position: must be one of top, bottom, owner_choice"])
    expect(effect({ "put_in_library" => { "to" => "self", "position" => "owner_choice" } }).to_s)
      .to eq("put into its owner's library (owner choice) → itself")
    expect(errors_for([{ "shuffle_into_library" => { "to" => "you" } }, { "shuffle_library" => {} },
                       { "look_at_hand" => { "to" => "each_opponent" } }, { "explore" => { "to" => "self" } }])).to be_empty
    expect(errors_for([{ "exile" => { "to" => "self", "link" => 1, "until_source_leaves" => true } }]))
      .to eq(["#{base}.exile.link: must be true or false"])
    expect(effect({ "exile" => { "to" => "self", "until_source_leaves" => true } }).to_s).to eq("exile until the source leaves → itself")
    expect(effect({ "exile" => { "to" => "self", "link" => true } }).to_s).to eq("exile (linked) → itself")
  end

  it "checks search_library's searcher, may, computed count and counters (CR 701.23)" do
    search = ->(params) { [{ "draw" => { "amount" => 1 } }, { "search_library" => params }] }
    path = "abilities[0].spell.effects[1].search_library"
    expect(errors_for(search.call({ "count" => { "count" => { "result" => 0 } }, "put" => "battlefield",
                                    "counters" => { "+1/+1" => 2 } }))).to be_empty
    expect(errors_for(search.call({ "count" => { "count" => { "result" => 1 } } })))
      .to eq(["#{path}.count.count.result: must refer to one of the 1 earlier effects"])
    expect(errors_for(search.call({ "count" => "many" }))).to eq(["#{path}.count: must be a positive integer, \"any\" or an amount"])
    expect(errors_for(search.call({ "counters" => { "+1/+1" => 0 } })))
      .to eq(["#{path}.counters: must be {counter name: positive integer}"])
    expect(errors_for(search.call({ "counters" => { "shield" => 1 } })))
      .to eq(["#{path}.counters: only cards put onto the battlefield enter with counters"])
    expect(errors_for(search.call({ "may" => 1, "searcher" => { "controller_of" => { "target" => 0 } } })))
      .to eq(["#{path}.may: must be true or false", "#{path}.searcher.controller_of.target: must refer to one of the 0 declared targets"])
    expect(errors_for(search.call({ "searcher" => { "controller_of" => "self", "x" => 1 } })))
      .to eq(["#{path}.searcher: unknown parameter \"x\""])
    computed = Enjine::CardDefinition.from_h({ "name" => "Probe Card", "mana_cost" => "{R}", "types" => ["instant"],
                                               "abilities" => [{ "spell" => {
                                                 "effects" => search.call({ "count" => { "count" => "you" } })
                                               } }] })
    expect(computed.spell_ability.effects.last.to_s).to include("up to the count of you (computed)")
  end

  it "selector and condition forms: exiled_with, controller_of and share_card_type (CR 607.2a)" do
    expect(Enjine::Mechanics::Selector.build("exiled_with", [], "s", targets_count: 0).to_s).to eq("the cards exiled with it")
    controller = Enjine::Mechanics::Selector.build({ "controller_of" => { "target" => 0 } }, [], "s", targets_count: 1)
    expect(controller.to_s).to eq("the controller of target #1")
    errors = []
    condition = Enjine::Mechanics::Condition.build({ "share_card_type" => "exiled_with", "x" => 1 }, errors, "c")
    expect(errors).to eq(["c: unknown parameter \"x\""])
    expect(condition.to_s).to eq("the cards exiled with it share a card type")
  end
end
