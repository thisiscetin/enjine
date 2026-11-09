# frozen_string_literal: true

RSpec.describe "Emblems (CR 114)" do
  def board(loyalty: 6, hand: [], mine: ["Grizzly Bears"], theirs: ["Grizzly Bears"], mana: {})
    build_game do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: mana) do
        battlefield "Ilsa, Ember Herald", loyalty: loyalty
        mine.each { battlefield it }
        hand(*hand)
        library "Forest", count: 10
      end
      player("bob") do
        theirs.each { battlefield it }
        library "Forest", count: 10
      end
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def ilsa(game) = obj_id(game, "Ilsa, Ember Herald")

  def activate(game, index)
    options = game.legal_options.select { it[:type] == "activate" && it[:object] == ilsa(game) }
    game.submit(options.fetch(index))
    game.submit(type: "pass") until game.state.stack.empty?
  end

  def mine(game, card) = game.state.battlefield.find { game.state.object(it).card == card && game.state.object(it).controller == 0 }
  def theirs(game, card) = game.state.battlefield.find { game.state.object(it).card == card && game.state.object(it).controller == 1 }

  it "an emblem's static ability works from the command zone for the rest of the game (CR 114.4)" do
    game = board
    activate(game, 1)
    expect(game.state.command.size).to eq(1)
    emblem = game.state.object(game.state.command.first)
    expect([emblem.kind, emblem.zone, emblem.owner]).to eq(["emblem", :command, 0])
    expect(engine(game).power(engine(game).object(mine(game, "grizzly_bears")))).to eq(4)
    expect(engine(game).power(engine(game).object(theirs(game, "grizzly_bears")))).to eq(2)
    engine(game).move!(ilsa(game), :graveyard, reason: "test") if game.state.battlefield.include?(ilsa(game))
    expect(engine(game).power(engine(game).object(mine(game, "grizzly_bears")))).to eq(4)
    view = game.view_for(:observer)["command"]
    expect(view).to eq([{ "id" => emblem.id, "kind" => "emblem", "owner" => "alice",
                          "abilities" => [engine(game).chars(emblem).abilities.first.ability.to_s] }])
    expect(Enjine::Game.import(game.export, catalog: game.catalog).state.to_h).to eq(game.state.to_h)
  end

  it "an emblem's triggered ability triggers and 'this emblem' is the source (CR 114.4, 113.6p)" do
    game = board(hand: ["Lightning Bolt"], mana: { R: 1 })
    activate(game, 2)
    game.submit(type: "cast", object: obj_id(game, "Lightning Bolt", zone: :hand, player: "alice"))
    game.submit(type: "target", target: "player:bob")
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
    expect(game.state.stack.size).to eq(2) # the emblem's trigger is above the Bolt
    trigger = game.state.object(game.state.stack.first)
    expect(trigger.source).to eq(game.state.command.first)
    game.submit(type: "pass") until game.state.stack.empty?
    expect(game.state.players[1].life).to eq(16)
  end

  it "validates emblem data with paths" do
    errors = lambda do |effect|
      Enjine::CardDefinition.from_h("name" => "X", "mana_cost" => "{1}", "types" => ["sorcery"],
                                    "abilities" => [{ "spell" => { "effects" => [effect] } }])
      []
    rescue Enjine::InvalidCardDefinition => e
      e.errors
    end
    expect(errors.call("create_emblem" => { "abilities" => [] }))
      .to include("abilities[0].spell.effects[0].create_emblem.abilities: needs at least one ability")
    expect(errors.call("create_emblem" => { "abilities" => ["may_not_untap"] }))
      .to include(a_string_matching(/create_emblem\.abilities\[0\]: an emblem's abilities are triggered, static, player_rule/))
    state = board.state.to_h
    state["objects"].first["kind"] = "emblem"
    expect(Enjine::Snapshot.validate(state,
                                     CardFixtures.catalog)).to include(a_string_matching(/emblems can only exist in the command zone/))
  end
end
