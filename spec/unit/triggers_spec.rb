# frozen_string_literal: true

RSpec.describe Enjine::Mechanics::Triggers do
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

  def entered(id, card)
    Enjine::Events::ZoneChanged.new(card: card, old_id: "x#1", new_id: id, owner: "alice",
                                    from: "hand", to: "battlefield", reason: "resolve")
  end

  it "validates parameters with paths" do
    expect(build({ "enters" => { "subject" => 5 } })[1]).to include(a_string_matching(/when.enters.subject: must be "self"/))
    expect(build({ "enters" => { "subject" => { "each" => "creature", "controller" => "nobody" } } })[1])
      .to include(a_string_matching(/controller: must be one of/))
    expect(build({ "step_begins" => { "step" => "teatime", "whose" => "someone" } })[1])
      .to include(a_string_matching(/step: must be one of/), a_string_matching(/whose: must be one of/))
    expect(build({ "cast" => { "controller" => "x", "spell" => "big" } })[1])
      .to include(a_string_matching(/controller: must be/), a_string_matching(/spell: must be one of/))
    expect(build({ "explodes" => {} })[1]).to include(a_string_matching(/unknown trigger "explodes"/))
  end

  it "describes itself" do
    texts = [{ "enters" => {} }, { "dies" => { "subject" => { "each" => "creature", "controller" => "opponent" } } },
             { "attacks" => { "subject" => { "each" => "creature", "controller" => "you", "other" => true } } },
             { "step_begins" => { "step" => "end", "whose" => "each" } }, { "cast" => { "controller" => "any" } }]
            .map { build(it)[0].to_s }
    expect(texts).to eq(["When this enters", "When creature an opponent controls dies",
                         "Whenever another creature you control attacks", "At the beginning of each end",
                         "Whenever a player casts a spell"])
  end

  it "matches subjects by controller, type and 'other'" do
    any_opponent = build({ "enters" => { "subject" => { "each" => "creature", "controller" => "opponent" } } })[0]
    expect(any_opponent.match?(engine, entered(giant, "hill_giant"), source)).to be(true)
    expect(any_opponent.match?(engine, entered(bears, "grizzly_bears"), source)).to be(false)
    other = build({ "enters" => { "subject" => { "each" => "creature", "other" => true } } })[0]
    expect(other.match?(engine, entered(bears, "grizzly_bears"), source)).to be(false)
    lands = build({ "enters" => { "subject" => { "each" => "land" } } })[0]
    expect(lands.match?(engine, entered(giant, "hill_giant"), source)).to be(false)
    expect(lands.match?(engine, entered("forest#1", "forest").with(to: "graveyard"), source)).to be(false)
    expect(lands.match?(engine, entered("gone#99", "forest"), source)).to be(false)
  end

  it "matches casts by caster and spell type" do
    bolt = Enjine::Events::SpellCast.new(player: "bob", object: "lightning_bolt#5", card: "lightning_bolt", targets: [])
    bears_cast = bolt.with(card: "grizzly_bears", player: "alice")
    expect(build({ "cast" => { "controller" => "opponent", "spell" => "instant_or_sorcery" } })[0].match?(engine, bolt, source)).to be(true)
    expect(build({ "cast" => {} })[0].match?(engine, bolt, source)).to be(false) # "you" by default
    expect(build({ "cast" => { "spell" => "creature" } })[0].match?(engine, bears_cast, source)).to be(true)
    expect(build({ "cast" => { "spell" => "noncreature" } })[0].match?(engine, bears_cast, source)).to be(false)
  end

  it "doesn't match the wrong step or a vanished attacker" do
    upkeep = build({ "step_begins" => { "step" => "upkeep", "whose" => "opponent" } })[0]
    event = Enjine::Events::StepBegan.new(turn: 3, step: "upkeep", phase: "beginning")
    expect(upkeep.match?(engine, event, source)).to be(false) # alice is active, source is alice's
    expect(upkeep.match?(engine, event.with(step: "draw"), source)).to be(false)
    attacks = build({ "attacks" => {} })[0]
    expect(attacks.match?(engine, Enjine::Events::AttackerDeclared.new(object: "gone#1", target: "player:bob"), source)).to be(false)
  end

  it "requires a trigger condition on triggered abilities" do
    expect { Enjine::CardDefinition.from_h("name" => "X", "mana_cost" => "{1}", "types" => ["artifact"], "abilities" => [{ "triggered" => {} }]) }
      .to raise_error(Enjine::InvalidCardDefinition, /triggered.when: required/)
  end
end
