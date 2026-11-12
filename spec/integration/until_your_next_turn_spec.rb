# frozen_string_literal: true

# "Creatures you control gain flying until your next turn" and "until your next turn, it becomes a land"
# (CR 611.2a, 500.1): grant and become last through the opponent's turn and end as the controller's begins.
RSpec.describe "Grant and become until your next turn (CR 611.2a)" do
  let(:gale) do
    { "name" => "Spec Gale Banner", "mana_cost" => "{W}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "effects" => [
        { "grant" => { "keywords" => ["flying"], "to" => { "each" => { "creature" => { "controller" => "you" } } },
                       "duration" => "until_your_next_turn" } }
      ] } }] }
  end
  let(:stillness) do
    { "name" => "Spec Rooted Stillness", "mana_cost" => "{U}", "types" => ["instant"],
      "abilities" => [{ "spell" => { "targets" => ["creature"], "effects" => [
        { "become" => { "types" => ["land"], "loses_abilities" => true, "duration" => "until_your_next_turn",
                        "abilities" => [{ "mana" => { "cost" => ["tap"], "produce" => "{U}" } }], "to" => { "target" => 0 } } }
      ] } }] }
  end
  let(:catalog) { catalog_with(gale, stillness) }

  let(:game) do
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice", mana_pool: { W: 1, U: 1 }) do
        battlefield "Grizzly Bears"
        hand "Spec Gale Banner", "Spec Rooted Stillness"
        library "Forest", count: 5
      end
      player("bob") { library "Forest", count: 5 }
    end
  end

  def chars(game, id) = Enjine::Engine.new(game.catalog, game.state) { nil }.chars(id)

  def advance(game)
    200.times do
      return if yield

      options = game.legal_options
      game.submit(options.find { it[:type] == "pass" } || options.find { it[:type] == "done" } || options.first)
    end
    raise "never got there"
  end

  def cast(game, name)
    game.submit(type: "cast", object: ids_in(game, "alice", :hand).find { game.state.object(it).card == Enjine::CardDefinition.slug(name) })
    advance(game) { game.state.stack.empty? && game.pending_decision.kind == "priority" }
  end

  it "keeps the keyword through the opponent's turn and ends it as yours begins" do
    bears = obj_id(game, "Grizzly Bears")
    cast(game, "Spec Gale Banner")
    advance(game) { game.state.active == 1 && game.state.step == :precombat_main }
    expect(chars(game, bears).keyword?(:flying)).to be(true)
    advance(game) { game.state.active.zero? }
    expect(chars(game, bears).keyword?(:flying)).to be(false)
  end

  it "keeps a creature a land through the opponent's turn, a creature again on yours" do
    bears = obj_id(game, "Grizzly Bears")
    cast(game, "Spec Rooted Stillness")
    advance(game) { game.state.active == 1 && game.state.step == :precombat_main }
    land = chars(game, bears)
    expect(land.type?(:land)).to be(true)
    expect(land.mana_abilities.size).to eq(1)
    advance(game) { game.state.active.zero? }
    expect(chars(game, bears).type?(:land)).to be(false)
  end

  it "describes the duration" do
    grant = Enjine::CardDefinition.from_h(gale).abilities.first.effects.first
    expect(grant.to_s).to start_with("gains flying until your next turn")
    become = Enjine::CardDefinition.from_h(stillness).abilities.first.effects.first
    expect(become.to_s).to include("until your next turn")
    bad = gale.merge("abilities" => [{ "spell" => { "effects" => [{ "grant" => { "keywords" => ["flying"],
                                                                                 "duration" => "forever" } }] } }])
    expect { Enjine::CardDefinition.from_h(bad) }.to raise_error(Enjine::InvalidCardDefinition, /duration: must be one of end_of_turn/)
  end
end
