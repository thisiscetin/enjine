# frozen_string_literal: true

RSpec.describe "Filter restrictions: comparisons, subtypes, supertypes, tokens, counters, modified (CR 115.1, 700.9)" do
  let(:legend) do
    { "name" => "Vault Marshal", "mana_cost" => "{2}{W}", "types" => ["creature"], "supertypes" => ["legendary"],
      "subtypes" => %w[human soldier], "power" => 3, "toughness" => 3 }
  end
  let(:trampler_lord) do
    { "name" => "Ridge Tactician", "mana_cost" => "{2}{G}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [{ "static" => { "affects" => { "each" => { "creature" => { "counters" => true } }, "controller" => "you" },
                                      "keywords" => ["trample"] } }] }
  end
  let(:watcher) do
    { "name" => "Barracks Watcher", "mana_cost" => "{1}{W}", "types" => ["creature"], "power" => 1, "toughness" => 1,
      "abilities" => [
        { "triggered" => { "when" => { "enters" => { "subject" => { "each" => { "creature" => { "subtypes" => ["soldier"] } },
                                                                    "controller" => "you", "other" => true } } },
                           "effects" => [{ "gain_life" => { "amount" => 1 } }] } },
        { "triggered" => { "when" => { "dies" => { "subject" => { "each" => { "creature" => { "counters" => "+1/+1" } } } } },
                           "effects" => [{ "draw" => { "amount" => 1 } }] } }
      ] }
  end
  let(:ray) do
    { "name" => "Giant Bane", "mana_cost" => "{R}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => [{ "creature" => { "power" => { "at_least" => 4 } } }],
                                     "effects" => [{ "destroy" => { "to" => { "target" => 0 } } }] } }] }
  end
  let(:catalog) { catalog_with(legend, trampler_lord, watcher, ray) }

  def engine(game) = game.instance_variable_get(:@engine)
  def filter(data) = Enjine::Mechanics.build_entry(:filter, data, [], "f")
  def cards(game, refs) = refs.map { game.state.object(it).card }

  def board
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        hand "Giant Bane"
        battlefield "Mountain"
        battlefield "Grizzly Bears", counters: { "+1/+1" => 2 }
        battlefield "Vault Marshal", "Ridge Tactician"
        library "Forest", count: 5
      end
      player("bob") do
        battlefield "Hill Giant", "Craw Wurm", "Glory Seeker"
        library "Forest", count: 5
      end
    end
  end

  it "targets by current power: counters count (CR 208.3, 613.4c)" do
    game = board
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    targets = game.legal_options.filter_map { it[:target] }
    expect(cards(game, targets)).to contain_exactly("grizzly_bears", "craw_wurm")
  end

  it "compares mana value and toughness, matches subtypes, supertypes and their negations" do
    game = board
    eng = engine(game)
    expect(cards(game, filter({ "creature" => { "mana_value" => { "at_most" => 2 } } }).candidates(eng, 0)))
      .to contain_exactly("grizzly_bears", "glory_seeker")
    expect(cards(game, filter({ "permanent" => { "mana_value" => { "at_least" => 4, "at_most" => 4 } } }).candidates(eng, 0)))
      .to eq(["hill_giant"])
    expect(cards(game, filter({ "creature" => { "toughness" => { "at_most" => 1 } } }).candidates(eng, 0))).to eq(["ridge_tactician"])
    expect(cards(game, filter({ "creature" => { "subtypes" => ["soldier"] } }).candidates(eng, 0)))
      .to contain_exactly("vault_marshal", "glory_seeker")
    expect(cards(game, filter({ "creature" => { "not_subtypes" => %w[soldier bear giant] } }).candidates(eng, 0)))
      .to contain_exactly("ridge_tactician", "craw_wurm")
    expect(cards(game, filter({ "creature" => { "supertypes" => ["legendary"] } }).candidates(eng, 0))).to eq(["vault_marshal"])
    expect(filter({ "creature" => { "not_supertypes" => ["legendary"] } }).candidates(eng, 0).size).to eq(5)
    expect(cards(game, filter({ "permanent" => { "types" => %w[creature land] } }).candidates(eng, 0))).to eq([])
  end

  it "tokens, counters and modified permanents (CR 111.1, 122, 700.9)" do
    game = board
    eng = engine(game)
    token = Enjine::CardDefinition.token("name" => "Recruit", "types" => ["creature"], "power" => 1, "toughness" => 1)
    game.catalog.add(token)
    eng.create_token!(token, 1)
    expect(cards(game, filter({ "creature" => { "token" => true } }).candidates(eng, 0))).to eq([token.id])
    expect(filter({ "creature" => { "token" => false } }).candidates(eng, 0).size).to eq(6)
    expect(cards(game, filter({ "creature" => { "counters" => true } }).candidates(eng, 0))).to eq(["grizzly_bears"])
    expect(cards(game, filter({ "creature" => { "counters" => "+1/+1" } }).candidates(eng, 0))).to eq(["grizzly_bears"])
    expect(filter({ "creature" => { "counters" => "stun" } }).candidates(eng, 0)).to eq([])
    expect(filter({ "creature" => { "counters" => false } }).candidates(eng, 0).size).to eq(6)
    expect(cards(game, filter({ "creature" => { "modified" => true } }).candidates(eng, 0))).to eq(["grizzly_bears"])
    expect(filter({ "creature" => { "modified" => false } }).candidates(eng, 0).size).to eq(6)
  end

  it "one_of combines filters, each with its own restrictions" do
    game = board
    either = filter({ "one_of" => [{ "permanent" => { "any_of" => ["land"] } },
                                   { "creature" => { "power" => { "at_least" => 6 } } }] })
    expect(cards(game, either.candidates(engine(game), 0))).to contain_exactly("mountain", "craw_wurm")
    expect(either.match?(engine(game), obj_id(game, "Craw Wurm"), 0)).to be(true)
    expect(either.match?(engine(game), obj_id(game, "Hill Giant"), 0)).to be(false)
    expect(either.to_s).to eq("land or creature with power 6 or greater")
  end

  it "matches spells on the stack by type: a noncreature spell" do
    game = board
    noncreature = filter({ "spell" => { "not" => ["creature"] } })
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).first)
    game.submit(type: "target", target: obj_id(game, "Craw Wurm"))
    spell = game.state.stack.first
    expect(noncreature.match?(engine(game), spell, 1)).to be(true)
    expect(filter({ "spell" => { "types" => ["creature"] } }).match?(engine(game), spell, 1)).to be(false)
  end

  it "a static ability can apply only to creatures with counters (re-evaluated continuously, CR 611.3a)" do
    game = board
    eng = engine(game)
    bears = obj_id(game, "Grizzly Bears")
    expect(eng.chars(bears).keyword?(:trample)).to be(true)
    expect(eng.chars(obj_id(game, "Vault Marshal")).keyword?(:trample)).to be(false)
    eng.add_counters!(game.state.object(obj_id(game, "Vault Marshal")), "oil", 1)
    expect(eng.chars(obj_id(game, "Vault Marshal")).keyword?(:trample)).to be(true)
    expect(eng.chars(obj_id(game, "Craw Wurm")).keyword?(:trample)).to be(false) # controller: you
  end

  it "trigger subjects use the restrictions: entering by subtype, dying with counters as it last existed (CR 603.10a)" do
    game = board
    eng = engine(game)
    countered = obj_id(game, "Grizzly Bears")
    watcher = eng.create_object("barracks_watcher", 0, :hand)
    game.state.players[0].hand << watcher.id
    eng.move!(watcher.id, :battlefield, reason: "test")
    marshal = eng.create_object("vault_marshal", 0, :hand)
    game.state.players[0].hand << marshal.id
    eng.move!(marshal.id, :battlefield, reason: "test")
    bears = eng.create_object("grizzly_bears", 0, :hand)
    game.state.players[0].hand << bears.id
    eng.move!(bears.id, :battlefield, reason: "test")
    expect(game.state.pending_triggers.size).to eq(1) # the soldier, not the bear
    eng.move!(countered, :graveyard, reason: "destroy") # had +1/+1 counters
    eng.move!(obj_id(game, "Ridge Tactician"), :graveyard, reason: "destroy") # had none
    expect(game.state.pending_triggers.size).to eq(2)
  end

  it "validates restriction data with paths" do
    bad = { "name" => "Bad Bane", "mana_cost" => "{R}", "types" => ["instant"],
            "abilities" => [{ "spell" => { "targets" => [{ "creature" => {
              "power" => { "more_than" => 1 }, "mana_value" => 3, "subtypes" => ["Big Elf"], "supertypes" => ["mythic"],
              "token" => "yes", "counters" => "Lots!", "types" => ["wizard"]
            } }, { "one_of" => ["creature"] }], "effects" => [] } }] }
    expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition) { |e|
      expect(e.errors).to include(
        a_string_matching(/targets\[0\]\.creature\.power: must be \{"at_least": n\}/),
        a_string_matching(/targets\[0\]\.creature\.mana_value: must be/),
        a_string_matching(/creature\.subtypes: must be a non-empty list of lowercase subtypes/),
        a_string_matching(/creature\.supertypes: must be a non-empty list of supertypes/),
        a_string_matching(/creature\.token: must be true or false/),
        a_string_matching(/creature\.counters: must be true, false or a counter name/),
        a_string_matching(/creature\.types: must be a list of card types/),
        a_string_matching(/targets\[1\]\.one_of: must be a list of at least two filters/)
      )
    }
    static = { "name" => "Bad Lord", "mana_cost" => "{G}", "types" => ["creature"], "power" => 1, "toughness" => 1,
               "abilities" => [{ "static" => { "affects" => { "each" => { "creature" => { "power" => { "at_least" => 2 } } } },
                                               "keywords" => ["trample"] } }] }
    expect { Enjine::CardDefinition.from_h(static) }.to raise_error(Enjine::InvalidCardDefinition, /power can't be used in a static/)
  end

  it "describes restricted filters in words" do
    words = filter({ "creature" => { "token" => false, "supertypes" => ["legendary"], "subtypes" => ["human"],
                                     "not_subtypes" => ["doctor"], "not_supertypes" => ["basic"], "modified" => true,
                                     "mana_value" => { "at_most" => 3 }, "counters" => "stun" } }).to_s
    expect(words).to eq("nontoken modified legendary nonbasic human non-doctor creature with mana value 3 or less " \
                        "with a stun counter on it")
    expect(filter({ "creature" => { "counters" => true } }).to_s).to eq("creature with a counter on it")
    expect(filter({ "creature" => { "counters" => false, "token" => true } }).to_s).to eq("token creature with no counters on it")
  end
end
