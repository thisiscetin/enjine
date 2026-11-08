# frozen_string_literal: true

RSpec.describe "Combat and event trigger conditions" do
  def build(data)
    errors = []
    built = Enjine::Mechanics.build_entry(:trigger, data, errors, "when")
    [built, errors]
  end

  let(:game) do
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice") { battlefield "Grizzly Bears", "Forest" }
      player("bob") { battlefield "Hill Giant" }
    end
  end
  let(:engine) { game.instance_variable_get(:@engine) }
  let(:bears) { game.state.battlefield[0] }
  let(:giant) { game.state.battlefield[2] }
  let(:source) { { "id" => bears, "card" => "grizzly_bears", "controller" => 0 } }

  def damage(from, to, combat: true) = Enjine::Events::DamageDealt.new(source: from, target: to, amount: 2, combat: combat)
  def life(player, from, to) = Enjine::Events::LifeChanged.new(player: player, from: from, to: to)

  it "validates parameters with paths" do
    expect(build({ "deals_damage" => { "combat" => "yes", "to" => "planet" } })[1])
      .to include("when.deals_damage.combat: must be true or false", a_string_matching(/when.deals_damage.to: must be one of/))
    %w[player_attacks gains_life loses_life draws].each do |name|
      expect(build({ name => { "controller" => "nobody" } })[1]).to include(a_string_matching(/when.#{name}.controller: must be/))
    end
    expect(build({ "any_of" => [{ "enters" => {} }] })[1]).to include("when.any_of: must be a list of at least two trigger conditions")
    expect(build({ "any_of" => [{ "enters" => {} }, { "explodes" => {} }] })[1])
      .to include(a_string_matching(/when.any_of\[1\]: unknown trigger "explodes"/))
    expect(build({ "becomes_blocked" => { "subject" => 1 } })[1]).to include(a_string_matching(/subject: must be/))
  end

  it "describes itself" do
    texts = [{ "deals_damage" => { "combat" => true, "to" => "player" } }, { "deals_damage" => {} },
             { "player_attacks" => {} }, { "player_attacks" => { "controller" => "opponent" } },
             { "becomes_blocked" => {} }, { "gains_life" => {} }, { "loses_life" => { "controller" => "any" } },
             { "draws" => { "controller" => "opponent" } }, { "any_of" => [{ "enters" => {} }, { "attacks" => {} }] }]
            .map { build(it)[0].to_s }
    expect(texts).to eq(["Whenever this deals combat damage to a player", "Whenever this deals damage",
                         "Whenever you attack", "Whenever an opponent attacks", "Whenever this becomes blocked",
                         "Whenever you gain life", "Whenever a player loses life", "Whenever an opponent draws a card",
                         "When this enters or this attacks"])
  end

  it "deals_damage: combat flag, recipient and subject" do
    combat_to_player = build({ "deals_damage" => { "combat" => true, "to" => "player" } })[0]
    expect(combat_to_player.match?(engine, damage(bears, "player:bob"), source)).to be(true)
    expect(combat_to_player.match?(engine, damage(bears, "player:bob", combat: false), source)).to be(false)
    expect(combat_to_player.match?(engine, damage(bears, giant), source)).to be(false)
    expect(combat_to_player.match?(engine, damage(giant, "player:alice"), source)).to be(false)
    expect(combat_to_player.match?(engine, damage("gone#99", "player:bob"), source)).to be(false)
    to_creature = build({ "deals_damage" => { "to" => "creature" } })[0]
    expect(to_creature.match?(engine, damage(bears, giant, combat: false), source)).to be(true)
    expect(to_creature.match?(engine, damage(bears, "player:bob"), source)).to be(false)
    any = build({ "deals_damage" => { "subject" => { "each" => "creature", "controller" => "opponent" } } })[0]
    expect(any.match?(engine, damage(giant, bears), source)).to be(true)
  end

  it "player triggers match by whose event it is" do
    gains = build({ "gains_life" => {} })[0]
    expect(gains.match?(engine, life("alice", 20, 23), source)).to be(true)
    expect(gains.match?(engine, life("alice", 20, 18), source)).to be(false)
    expect(gains.match?(engine, life("bob", 20, 23), source)).to be(false)
    loses = build({ "loses_life" => { "controller" => "any" } })[0]
    expect(loses.match?(engine, life("bob", 20, 18), source)).to be(true)
    attacks = build({ "player_attacks" => { "controller" => "opponent" } })[0]
    expect(attacks.match?(engine, Enjine::Events::AttacksDeclared.new(player: "bob", attackers: [giant]), source)).to be(true)
    draws = build({ "draws" => {} })[0]
    drew = Enjine::Events::ZoneChanged.new(card: "forest", old_id: "forest#1", new_id: "forest#2", owner: "alice",
                                           from: "library", to: "hand", reason: "draw")
    expect(draws.match?(engine, drew, source)).to be(true)
    expect(draws.match?(engine, drew.with(owner: "bob"), source)).to be(false)
    expect(draws.match?(engine, drew.with(reason: "bounce", from: "battlefield"), source)).to be(false)
  end

  it "becomes_blocked needs the attacker still on the battlefield" do
    blocked = build({ "becomes_blocked" => {} })[0]
    expect(blocked.match?(engine, Enjine::Events::BecameBlocked.new(object: bears, blockers: [giant]), source)).to be(true)
    expect(blocked.match?(engine, Enjine::Events::BecameBlocked.new(object: "gone#9", blockers: []), source)).to be(false)
  end

  it "any_of watches every listed event and leaves the battlefield if any part does" do
    either = build({ "any_of" => [{ "dies" => {} }, { "gains_life" => {} }] })[0]
    expect(either.leaves_battlefield?).to be(true)
    expect(either.watches?(life("alice", 1, 2))).to be(true)
    expect(either.watches?(Enjine::Events::Tapped.new(object: bears))).to be(false)
    expect(either.match?(engine, life("alice", 1, 2), source)).to be(true)
  end

  it "events keep old snapshots readable and describe life changes" do
    expect(Enjine::Events::DamageDealt.new(source: "a", target: "b", amount: 1).combat).to be(false)
    old = Enjine::Events.from_h({ "type" => "damage_dealt", "source" => "a", "target" => "b", "amount" => 1 })
    expect(old.combat).to be_nil
    expect([life("a", 5, 8).gain, life("a", 5, 8).loss, life("a", 5, 3).loss]).to eq([3, 0, 2])
  end

  it "restriction flags are keywords that cards, statics and grants can name" do
    %w[cant_attack cant_block cant_be_blocked attacks_each_combat].each do |name|
      expect(Enjine.registry.fetch(:keyword, name)).not_to be_nil
    end
    card = Enjine::CardDefinition.from_h({ "name" => "Test Brute", "mana_cost" => "{1}", "types" => ["creature"],
                                           "power" => 1, "toughness" => 1, "keywords" => ["cant attack"] })
    expect(card.keyword?(:cant_attack)).to be(true)
  end
end
