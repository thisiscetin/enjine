# frozen_string_literal: true

# Trigger, history and stack mechanics on invented cards (spec/fixtures/cards): "those creatures" of a cast trigger,
# lands played from other zones and the turn's land history, boast triggers, die rolls, fixed coin flips, choosing
# new targets, and copying an attack trigger or an activated ability.
RSpec.describe "Triggers, turn history and the stack" do
  let(:extra) do
    [{ "name" => "Test Growth", "mana_cost" => "{G}", "types" => ["instant"],
       "abilities" => [{ "spell" => { "targets" => ["creature"],
                                      "effects" => [{ "pump" => { "power" => 1, "toughness" => 1, "to" => { "target" => 0 } } }] } }] },
     { "name" => "Test Ping", "mana_cost" => "{R}", "types" => ["instant"],
       "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                      "effects" => [{ "deal_damage" => { "amount" => 1, "to" => { "target" => 0 } } }] } }] }]
  end
  let(:catalog) { catalog_with(*extra) }

  def board(hand: [], battlefield: [], graveyard: [], theirs: [], their_hand: [], mana: {}, step: :precombat_main, seed: 1)
    build_game(catalog) do
      seed seed
      turn 3, active: "alice", step: step
      player("alice", mana_pool: mana) do
        hand(*hand)
        graveyard(*graveyard)
        library "Island", count: 10
        battlefield.each { battlefield it }
      end
      player("bob") do
        hand(*their_hand)
        library "Swamp", count: 10
        theirs.each { battlefield it }
      end
    end
  end

  def play(game, action, *answers)
    game.submit(action) if action
    until game.over? || ((decision = game.pending_decision).kind == "priority" && game.state.stack.empty?)
      case decision.kind
      when "priority" then game.submit(type: "pass")
      when "pay_cost" then game.submit(game.legal_options.find { it[:type] == "pay_mana" } || raise("can't pay"))
      else
        answer = answers.shift or raise "no answer for #{decision.kind}: #{game.legal_options}"
        game.submit(answer.respond_to?(:call) ? answer.call(game) : answer)
      end
    end
    expect(answers).to be_empty
    game
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def cast(game, card, *) = play(game, { type: "cast", object: obj_id(game, card, zone: :hand, player: "alice") }, *)
  def target(ref) = { type: "target", target: ref }
  def life(game, index) = game.state.players[index].life
  def events(game) = game.history_for(:observer).flat_map { it["events"] }

  it "\"those creatures\": the cast spell's targets that matched the trigger gain flying (CR 601.2c)" do
    game = board(hand: ["Test Growth"], battlefield: ["Galeborne Paragon", "Grizzly Bears"], mana: { G: 1 })
    bears = obj_id(game, "Grizzly Bears")
    cast(game, "Test Growth", target(bears))
    expect(engine(game).chars(engine(game).object(bears)).keyword?(:flying)).to be(true)
  end

  it "a land played from the graveyard triggers and counts as a land played from anywhere other than the hand (CR 305.1)" do
    game = board(battlefield: ["Wayward Cartographer"], graveyard: ["Forest"])
    cartographer = obj_id(game, "Wayward Cartographer")
    play(game, game.legal_options.find { it[:type] == "play_land" })
    expect(game.state.object(cartographer).counters["+1/+1"]).to eq(1)
    amount = Enjine::Mechanics::Amount.build({ "lands_played_this_turn" => { "by" => "you", "from" => "graveyard" } }, [], "x",
                                             targets_count: 0)
    expect(amount.value(engine(game), Enjine::Mechanics::EffectContext.new(0, cartographer))).to eq(1)
    skip_to(game, :end)
    play(game, nil)
    expect(ids_in(game, "alice", :hand).size).to eq(1)
  end

  it "a land played from the hand neither triggers it nor counts" do
    game = board(battlefield: ["Wayward Cartographer"], hand: ["Forest"])
    play(game, game.legal_options.find { it[:type] == "play_land" })
    skip_to(game, :end)
    play(game, nil)
    expect(game.state.object(obj_id(game, "Wayward Cartographer")).counters["+1/+1"].to_i).to eq(0)
    expect(ids_in(game, "alice", :hand)).to be_empty
  end

  it "\"whenever a creature you control boasts\" triggers on a boast ability (CR 702.142b)" do
    game = board(battlefield: ["Boastful Herald"], mana: { R: 1 })
    herald = obj_id(game, "Boastful Herald")
    engine(game).object(herald).memory["attacked"] = { "turn" => 3, "count" => 1 } # it attacked this turn
    game = Enjine::Game.import({ "state" => game.state.to_h }, catalog: catalog)
    play(game, { type: "activate", object: herald, ability: "printed:0" })
    expect(life(game, 0)).to eq(21)
  end

  it "rolls a die: the result is the amount this way (CR 706.2)" do
    game = board(battlefield: ["Chaos Die"], mana: { C: 2 })
    play(game, { type: "activate", object: obj_id(game, "Chaos Die"), ability: "printed:0" })
    roll = events(game).find { it["type"] == "rolled_die" }
    expect(roll["sides"]).to eq(6)
    expect(life(game, 0)).to eq(20 + roll["result"])
    expect(life(game, 1)).to eq(roll["result"] >= 5 ? 18 : 20)
    expect(Enjine::CLI::Text.new(game).event(roll)).to eq("alice rolls a d6: #{roll["result"]}") if defined?(Enjine::CLI::Text)
  end

  it "fixed coin flips need no call and are won only the first time each turn (CR 705.3)" do
    game = board(battlefield: ["Lucky Charm Vault", "Lucky Charm Vault"], mana: { C: 2 })
    vaults = game.state.battlefield.select { game.state.object(it).card == "lucky_charm_vault" }
    play(game, { type: "activate", object: vaults[0], ability: "printed:1" })
    expect(ids_in(game, "alice", :hand).size).to eq(1)
    play(game, { type: "activate", object: vaults[1], ability: "printed:1" }, { type: "call", call: "heads" })
    expect(events(game).count { it["type"] == "coin_flipped" }).to eq(2)
  end

  it "an opponent's spell targeting the sprite can be redirected, keeping or changing each target (CR 115.7d)" do
    game = board(battlefield: ["Redirecting Sprite"], their_hand: ["Test Ping"], step: :upkeep)
    game.state.players[1].mana_pool[:R] = 1
    sprite = obj_id(game, "Redirecting Sprite")
    game.submit(type: "pass")
    game.submit(type: "cast", object: ids_in(game, "bob", :hand).first)
    game.submit(target(sprite))
    game.submit(game.legal_options.find { it[:type] == "pay_mana" })
    play(game, nil, target(sprite)) # keep the target
    expect(game.state.object(sprite).damage).to eq(1)
    expect(events(game).count { it["type"] == "target_chosen" }).to eq(1) # only as it was cast
  end

  it "copies a creature's attack trigger (CR 603.2, 707.10)" do
    game = board(battlefield: ["Echoing Drillmaster"], step: :beginning_of_combat)
    pass_both(game)
    game.submit(type: "attack", object: obj_id(game, "Echoing Drillmaster"), target: "player:bob")
    game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
    attack = game.state.pending_triggers.find { it["ability"] == "printed:0" }
    game.submit(type: "trigger", trigger: attack["id"])
    play(game, nil, { type: "yes" })
    expect(life(game, 1)).to eq(18)
  end

  it "has nothing to copy once the triggered ability has left the stack" do
    game = board(battlefield: ["Echoing Drillmaster"], step: :beginning_of_combat)
    pass_both(game)
    game.submit(type: "attack", object: obj_id(game, "Echoing Drillmaster"), target: "player:bob")
    game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
    copier = game.state.pending_triggers.find { it["ability"] == "printed:1" }
    game.submit(type: "trigger", trigger: copier["id"]) # the attack trigger resolves first
    play(game, nil, { type: "yes" })
    expect(life(game, 1)).to eq(19)
    expect(events(game).map { it["type"] }).not_to include("spell_copied")
  end

  it "Mimic Lens copies the next ability activated this turn" do
    game = board(battlefield: ["Mimic Lens", "Chaos Die"], mana: { C: 4 })
    play(game, { type: "activate", object: obj_id(game, "Mimic Lens"), ability: "printed:0" })
    play(game, { type: "activate", object: obj_id(game, "Chaos Die"), ability: "printed:0" })
    expect(events(game).count { it["type"] == "rolled_die" }).to eq(2)
  end

  it "Swap Tactics only exchanges permanents that still share a card type (CR 701.12a)" do
    game = board(hand: ["Swap Tactics"], battlefield: ["Grizzly Bears"], theirs: ["Hill Giant"], mana: { U: 4 })
    bears = obj_id(game, "Grizzly Bears")
    giant = obj_id(game, "Hill Giant")
    cast(game, "Swap Tactics", target(bears), target(giant))
    expect([game.state.object(bears).controller, game.state.object(giant).controller]).to eq([1, 0])
  end

  it "Withering Mirror: the copy and the original both deal damage as -1/-1 counters (CR 702.80a)" do
    game = board(hand: ["Withering Mirror", "Test Ping"], theirs: ["Hill Giant"], mana: { R: 4 })
    giant = obj_id(game, "Hill Giant")
    ping = obj_id(game, "Test Ping", zone: :hand, player: "alice")
    game.submit(type: "cast", object: ping)
    game.submit(target(giant))
    game.submit(game.legal_options.find { it[:type] == "pay_mana" })
    mirror = obj_id(game, "Withering Mirror", zone: :hand, player: "alice")
    play(game, { type: "cast", object: mirror }, target(game.state.stack.first), target(giant))
    expect(game.state.object(giant).counters["-1/-1"]).to eq(2)
  end
end
