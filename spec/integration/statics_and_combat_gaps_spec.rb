# frozen_string_literal: true

# Invented cards for the statics, grants and combat shapes: a granted cost that taps the granting permanent
# (CR 602.2b, 607.1a), a chosen color bound into a granted ability (CR 607.2d), "can't become untapped"
# (CR 701.26b), "attacks alone" (CR 506.5), chosen card names (CR 201.4, 602.5), riot granted by a static
# (CR 614.12, 702.136b), attack and block restrictions by flying (CR 508.1c, 509.1b) and sized tokens.
RSpec.describe "Statics, grants and combat gaps (invented cards)" do
  let(:stand_ins) do
    [{ "name" => "Spec Sky Bird", "mana_cost" => "{1}{W}", "types" => ["creature"], "subtypes" => ["bird"], "power" => 1,
       "toughness" => 1, "keywords" => ["flying"] },
     { "name" => "Spec Rouse", "mana_cost" => "{W}", "types" => ["instant"],
       "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [{ "untap" => { "to" => { "target" => 0 } } }] } }] },
     { "name" => "Spec Gate", "types" => ["land"],
       "abilities" => [{ "mana" => { "cost" => ["tap"], "produce" => "{C}" } },
                       { "activated" => { "cost" => ["tap"], "effects" => [{ "gain_life" => { "amount" => 1 } }] } }] }]
  end

  def board(hand: [], battlefield: [], theirs: [], their_hand: [], mana: {}, step: :precombat_main, active: "alice")
    build_game(catalog_with(*stand_ins)) do
      turn 3, active: active, step: step
      player("alice", mana_pool: mana) do
        hand(*hand) unless hand.empty?
        library "Island", count: 10
        battlefield.each { battlefield it }
      end
      player("bob") do
        hand(*their_hand) unless their_hand.empty?
        library "Swamp", count: 10
        theirs.each { battlefield it }
      end
    end
  end

  # Submits `action`, answers other decisions with `answers` (options or lambdas), pays from the pool and passes
  # until the stack is empty.
  def play(game, action, *answers)
    game.submit(action) if action
    until (decision = game.pending_decision).kind == "priority" && game.state.stack.empty?
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" # colorless first, so colored mana stays for later costs
        pays = game.legal_options.select { it[:type] == "pay_mana" }
        game.submit(pays.find { it[:mana].to_s == "C" } || pays.first || raise("can't pay"))
      else
        answer = answers.shift or raise "no answer for #{decision.kind}: #{game.legal_options}"
        game.submit(answer.respond_to?(:call) ? answer.call(game) : answer)
      end
    end
    game
  end

  def cast(game, card, *) = play(game, { type: "cast", object: obj_id(game, card, zone: :hand, player: "alice") }, *)
  def activations(game, id) = game.legal_options.select { it[:type] == "activate" && it[:object] == id }
  def pick(type, **details) = ->(game) { game.legal_options.find { |o| o[:type] == type && details.all? { |k, v| o[k] == v } } }
  def aim(card) = ->(game) { { type: "target", target: obj_id(game, card) } }
  def engine(game) = game.instance_variable_get(:@engine)
  def chars(game, id) = engine(game).chars(id)
  def obj(game, id) = game.state.object(id)

  def attack_with(game, *names)
    game.submit(type: "pass") until game.pending_decision.kind == "declare_attackers"
    names.each { game.submit(type: "attack", object: obj_id(game, it), target: "player:bob") }
    game.submit(type: "done") if option_types(game).include?("done")
    game
  end

  it "Lure Angler's Rod: the granted ability taps the creature and the Rod; untapping turns bait into a Fish (CR 602.2b)" do
    game = board(hand: ["Spec Rouse"], battlefield: ["Lure Angler's Rod", "Grizzly Bears"], mana: { C: 3, W: 1 })
    rod = obj_id(game, "Lure Angler's Rod")
    bears = obj_id(game, "Grizzly Bears")
    play(game, activations(game, rod).first, aim("Grizzly Bears"))
    play(game, activations(game, bears).first)
    expect([obj(game, bears).tapped, obj(game, rod).tapped, obj(game, rod).counters]).to eq([true, true, { "bait" => 1 }])
    expect(activations(game, bears)).to be_empty # the Rod is tapped
    cast(game, "Spec Rouse", aim("Grizzly Bears"))
    expect(obj(game, rod).counters["bait"].to_i).to eq(0)
    expect(game.state.battlefield.count { chars(game, it).name == "Fish" }).to eq(1)
  end

  it "Chameleon Gecko: each activation binds its own color into the hexproof it grants (CR 607.2d)" do
    game = board(battlefield: ["Chameleon Gecko"], mana: { C: 2 })
    gecko = obj_id(game, "Chameleon Gecko")
    play(game, activations(game, gecko).first, pick("color", color: "R"))
    play(game, activations(game, gecko).first, pick("color", color: "G"))
    expect(chars(game, gecko).colors).to eq([:G])
    hexproof = chars(game, gecko).abilities.map(&:ability).select { it.kind == :hexproof_from }
    expect(hexproof.map { it.quality.colors }).to contain_exactly([:R], [:G])
  end

  it "Frostbind Sentry: the tapped creature can't become untapped while you control the Sentry (CR 701.26b)" do
    game = board(hand: ["Frostbind Sentry", "Spec Rouse"], theirs: ["Grizzly Bears"], mana: { W: 4, C: 2 })
    cast(game, "Frostbind Sentry", aim("Grizzly Bears"))
    bears = obj_id(game, "Grizzly Bears")
    cast(game, "Spec Rouse", aim("Grizzly Bears"))
    expect(obj(game, bears).tapped).to be(true)
    engine(game).move!(obj_id(game, "Frostbind Sentry"), :graveyard, reason: "test")
    skip_to(game, :precombat_main, turn: 4)
    expect(obj(game, bears).tapped).to be(false)
  end

  describe "Lone Duelist (CR 506.5)" do
    it "a creature attacking alone gains double strike" do
      game = attack_with(board(battlefield: ["Lone Duelist", "Grizzly Bears"], step: :beginning_of_combat), "Grizzly Bears")
      play(game, nil)
      expect(chars(game, obj_id(game, "Grizzly Bears")).keyword?(:double_strike)).to be(true)
    end

    it "two attackers don't trigger it" do
      game = attack_with(board(battlefield: ["Lone Duelist", "Grizzly Bears"], step: :beginning_of_combat),
                         "Grizzly Bears", "Lone Duelist")
      expect(game.state.stack).to be_empty
    end
  end

  it "Silencing Lens: names a card as it enters; that source's non-mana abilities can't be activated (CR 201.4, 602.5)" do
    game = board(hand: ["Silencing Lens"], theirs: ["Spec Gate"], their_hand: ["Grizzly Bears"], mana: { C: 2 })
    cast(game, "Silencing Lens", pick("name", name: "Spec Gate"))
    gate = obj_id(game, "Spec Gate")
    e = engine(game)
    expect(e.activatable?(1, gate, "printed:1")).to be(false)
    expect(e.chars(gate).mana_abilities).not_to be_empty
  end

  it "Hollow Cairn: chooses a land card name as it enters; lands with that name tap for {C} (CR 607.2d)" do
    game = board(hand: ["Hollow Cairn"], theirs: ["Spec Gate"])
    play(game, { type: "play_land", object: obj_id(game, "Hollow Cairn", zone: :hand, player: "alice") },
         pick("card_name", card_name: "Island"))
    expect(obj(game, obj_id(game, "Hollow Cairn")).memory["chosen_name"]).to eq("Island")
    game = board(hand: ["Hollow Cairn"], theirs: ["Spec Gate"])
    play(game, { type: "play_land", object: obj_id(game, "Hollow Cairn", zone: :hand, player: "alice") },
         pick("card_name", card_name: "Spec Gate"))
    expect(engine(game).chars(obj_id(game, "Spec Gate")).mana_abilities.size).to eq(2)
  end

  it "Sentinel Monolith: an X/X token for the greatest toughness among your creatures" do
    game = board(battlefield: ["Sentinel Monolith", "Pillarfield Ox", "Grizzly Bears"], mana: { C: 2 })
    play(game, activations(game, obj_id(game, "Sentinel Monolith")).first)
    spirit = game.state.battlefield.find { chars(game, it).name == "Spirit" }
    expect(engine(game).power_toughness(obj(game, spirit))).to eq([4, 4])
  end

  it "Stalwart Bastion: a creature you control with greater toughness assigns combat damage by toughness (CR 510.1a)" do
    game = attack_with(board(battlefield: ["Stalwart Bastion", "Pillarfield Ox"], step: :beginning_of_combat), "Pillarfield Ox")
    skip_to(game, :end_of_combat)
    expect(game.state.players[1].life).to eq(16)
  end

  describe "Riot Chorus Spider (CR 614.12, 702.136b)" do
    it "another Spider entering chooses riot from the static; haste stays after the Chorus leaves" do
      game = board(hand: ["Webling Scout"], battlefield: ["Riot Chorus Spider"], mana: { G: 1 })
      cast(game, "Webling Scout", pick("option", option: "haste"))
      scout = obj_id(game, "Webling Scout")
      engine(game).move!(obj_id(game, "Riot Chorus Spider"), :graveyard, reason: "test")
      expect([chars(game, scout).keyword?(:riot), chars(game, scout).keyword?(:haste)]).to eq([false, true])
    end

    it "a Spider with riot of its own chooses once for each instance; a non-Spider doesn't choose" do
      game = board(hand: ["Riot Chorus Spider", "Grizzly Bears"], battlefield: ["Riot Chorus Spider"], mana: { R: 2, G: 2 })
      cast(game, "Grizzly Bears")
      expect(obj(game, obj_id(game, "Grizzly Bears")).counters).to be_empty
      cast(game, "Riot Chorus Spider", pick("option", option: "counter"), pick("option", option: "counter"))
      second = game.state.battlefield.select { obj(game, it).card == "riot_chorus_spider" }.max
      expect(obj(game, second).counters).to eq("+1/+1" => 2)
    end
  end

  describe "Skyward Bulwark (CR 508.1c, 509.1b)" do
    it "creatures with flying can't attack you" do
      game = board(battlefield: ["Skyward Bulwark"], theirs: ["Spec Sky Bird", "Grizzly Bears"], step: :beginning_of_combat,
                   active: "bob")
      expect(engine(game).eligible_attackers).to eq([obj_id(game, "Grizzly Bears")])
    end

    it "creatures with flying can't block your creatures" do
      game = board(battlefield: ["Skyward Bulwark", "Grizzly Bears"], theirs: ["Spec Sky Bird", "Savannah Lions"],
                   step: :beginning_of_combat)
      attack_with(game, "Grizzly Bears")
      game.submit(type: "pass") until game.pending_decision.kind == "declare_blockers"
      expect(game.legal_options.select { it[:type] == "block" }.map { it[:object] }.uniq).to eq([obj_id(game, "Savannah Lions")])
    end
  end
end
