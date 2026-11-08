# frozen_string_literal: true

# Builds a game-state snapshot from a readable description of a board, then
# imports it. This is how integration specs reach any position directly:
#
#   game = build_game do
#     turn 3, active: "alice", step: :precombat_main
#     player "alice" do
#       hand "Forest"
#       battlefield "Mountain", tapped: true
#       library "Island", count: 10
#     end
#     player "bob", life: 7 do
#       hand "Forest", count: 6
#     end
#   end
class Scenario
  PlayerSpec = Struct.new(:name, :attrs, :zones)

  def initialize(catalog)
    @catalog = catalog
    @players = []
    @turn = 1
    @active = nil
    @step = :precombat_main
    @pending = nil
    @seed = 1
    @priority = nil
    @battlefield = []
  end

  def turn(number, active:, step:)
    @turn = number
    @active = active
    @step = step
  end

  def seed(value) = @seed = value
  def priority(name) = @priority = name
  def pending(kind, player:, **details) = @pending = { "kind" => kind.to_s, "player" => player, **details.transform_keys(&:to_s) }

  def player(name, **attrs, &block)
    spec = PlayerSpec.new(name, attrs, Hash.new { |h, k| h[k] = [] })
    @current = spec
    instance_eval(&block) if block
    @players << spec
  end

  %i[hand library graveyard].each do |zone|
    define_method(zone) do |*cards, count: 1|
      cards.each { |c| count.times { @current.zones[zone] << { card: c } } }
    end
  end

  def battlefield(*cards, count: 1, tapped: false, controlled_since: nil, counters: {}, damage: 0, loyalty: nil)
    cards.each do |c|
      entry = { card: c, tapped: tapped, controlled_since: controlled_since, damage: damage,
                counters: counters.transform_keys(&:to_s).merge(loyalty ? { "loyalty" => loyalty } : {}) }
      count.times { @current.zones[:battlefield] << entry }
    end
  end

  def to_h
    raise ArgumentError, "a scenario needs exactly 2 players" unless @players.size == 2

    names = @players.map(&:name)
    index = ->(name) { names.index(name) || raise(ArgumentError, "unknown player #{name}") }
    active = index.call(@active || names.first)
    next_id = 1
    objects = []
    battlefield = []
    players = @players.each_with_index.map do |spec, owner|
      zones = %i[library hand graveyard].to_h do |zone|
        ids = spec.zones[zone].map do |entry|
          id = "#{CardDefinition_slug(entry[:card])}##{next_id}"
          next_id += 1
          objects << object_h(id, entry, owner, zone)
          id
        end
        [zone.to_s, ids]
      end
      spec.zones[:battlefield].each do |entry|
        id = "#{CardDefinition_slug(entry[:card])}##{next_id}"
        next_id += 1
        objects << object_h(id, entry, owner, :battlefield)
        battlefield << id
      end
      player_h(spec, zones)
    end
    priority = @priority ? index.call(@priority) : active
    pending = @pending&.merge("player" => index.call(@pending["player"])) || { "kind" => "priority", "player" => priority }
    {
      "version" => Enjine::Snapshot::VERSION, "rules" => Enjine::RULES_VERSION, "seed" => @seed,
      "rng" => Enjine::Rng.from_seed(@seed).state,
      "decklists" => players.each_index.map { |i| objects.select { it["owner"] == i }.map { it["card"] } },
      "turn" => @turn, "active" => active, "step" => @step.to_s, "step_state" => "active",
      "priority" => pending["kind"] == "priority" ? pending["player"] : nil, "passes" => 0,
      "next_id" => next_id, "starting_player" => 0, "pending" => pending, "result" => nil,
      "players" => players, "objects" => objects, "battlefield" => battlefield, "stack" => [], "exile" => []
    }
  end

  def game = Enjine::Game.import({ "state" => to_h }, catalog: @catalog)

  private

  def CardDefinition_slug(card) = Enjine::CardDefinition.slug(card) # rubocop:disable Naming/MethodName

  def object_h(id, entry, owner, zone)
    { "id" => id, "card" => id.split("#").first, "owner" => owner, "controller" => owner, "zone" => zone.to_s,
      "tapped" => entry.fetch(:tapped, false), "controlled_since" => zone == :battlefield ? entry[:controlled_since] || 0 : nil,
      "kind" => "card", "counters" => default_counters(id, entry, zone), "damage" => entry.fetch(:damage, 0), "source" => nil,
      "ability" => nil, "targets" => nil, "loyalty_turn" => nil }
  end

  # Planeswalkers placed on the battlefield start with their printed loyalty unless given one.
  def default_counters(id, entry, zone)
    counters = entry.fetch(:counters, {})
    loyalty = @catalog.fetch(id.split("#").first).loyalty
    zone == :battlefield && loyalty && !counters.key?("loyalty") ? counters.merge("loyalty" => loyalty) : counters
  end

  def player_h(spec, zones)
    attrs = spec.attrs
    { "name" => spec.name, "life" => attrs.fetch(:life, 20), "poison" => attrs.fetch(:poison, 0),
      **zones, "mana_pool" => Enjine::Mana::TYPES.to_h { |t| [t.to_s, attrs.fetch(:mana_pool, {}).fetch(t, 0)] },
      "lands_played" => attrs.fetch(:lands_played, 0), "drew_from_empty" => attrs.fetch(:drew_from_empty, false),
      "lost" => nil, "mulligans" => 0, "kept" => true, "mulligan_choice" => nil }
  end
end

# Helpers available in every example.
module ScenarioHelpers
  def core_catalog = Enjine::CardPool::Core.catalog

  # A catalog of the core pool plus extra card data blocks defined in the spec.
  def catalog_with(*cards) = Enjine::Catalog.from_definitions(Enjine::CardPool::Core.cards + cards)

  def obj_id(game, card, zone: :battlefield, player: nil)
    ids = zone == :battlefield ? game.state.battlefield : game.state.players[game.names.index(player)].public_send(zone)
    ids.find { game.state.object(it).card == Enjine::CardDefinition.slug(card) } or raise "no #{card} in #{zone}"
  end

  def view_of(game, id) = (game.view_for(:observer)["battlefield"] + game.view_for(:observer)["stack"]).find { it["id"] == id }

  def build_game(catalog = core_catalog, &)
    builder = Scenario.new(catalog)
    builder.instance_eval(&)
    builder.game
  end

  def basics_deck(counts = { "Forest" => 30, "Mountain" => 30 })
    { "cards" => Enjine::CardPool::Core.cards, "main" => counts.map { |name, n| { "card" => name, "count" => n } } }
  end

  def basics_setup(names = %w[alice bob])
    Enjine::Setup.new(*names.map { Enjine::Player.new(name: it, deck: basics_deck) })
  end

  def option_types(game) = game.legal_options.map { it[:type] }

  # Passes priority (and declares no attackers/blockers) until `step` of `turn` is reached.
  def skip_to(game, step, turn: game.turn, limit: 500)
    limit.times do
      return game if game.step == step && game.turn == turn && game.pending_decision&.kind == "priority"

      types = option_types(game)
      game.submit(if types.include?("pass")
                    { type: "pass" }
                  else
                    { type: types.include?("done") ? "done" : types.first }
                  end)
    end
    raise "never reached #{step} of turn #{turn}"
  end

  def pass_both(game, times = 1)
    (times * 2).times { game.submit(type: "pass") }
  end

  def ids_in(game, player, zone)
    index = game.names.index(player)
    game.state.players[index].public_send(zone)
  end

  # Advances a freshly started game through play/draw and keeping both hands.
  def through_pregame(game, choice: "play")
    game.submit(type: choice)
    game.submit(type: "keep")
    game.submit(type: "keep")
    game
  end
end
