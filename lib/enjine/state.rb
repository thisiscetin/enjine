# frozen_string_literal: true

module Enjine
  # A card or token in a zone (CR 109). Refers to its definition by id only.
  # A new GameObject (with a new id) is created on every zone change (CR 400.7).
  GameObject = Struct.new(:id, :card, :owner, :controller, :zone, :tapped, :controlled_since, :kind, :counters,
                          :damage, :source, :ability, :targets, :loyalty_turn, :deathtouched) do
    def ability? = kind == "ability"

    def to_h
      { "id" => id, "card" => card, "owner" => owner, "controller" => controller, "zone" => zone.to_s,
        "tapped" => tapped, "controlled_since" => controlled_since, "kind" => kind, "counters" => counters.dup,
        "damage" => damage, "source" => source, "ability" => ability, "targets" => targets&.dup,
        "loyalty_turn" => loyalty_turn, "deathtouched" => deathtouched }
    end
  end

  # Per-player game state.
  PlayerState = Struct.new(:name, :life, :poison, :library, :hand, :graveyard, :mana_pool, :lands_played,
                           :drew_from_empty, :lost, :mulligans, :kept, :mulligan_choice) do
    def zone(name)
      case name
      when :library then library
      when :hand then hand
      when :graveyard then graveyard
      end
    end

    def to_h
      { "name" => name, "life" => life, "poison" => poison, "library" => library.dup, "hand" => hand.dup,
        "graveyard" => graveyard.dup, "mana_pool" => mana_pool.transform_keys(&:to_s),
        "lands_played" => lands_played, "drew_from_empty" => drew_from_empty, "lost" => lost,
        "mulligans" => mulligans, "kept" => kept, "mulligan_choice" => mulligan_choice }
    end
  end

  # The complete, mutable state of one game. Plain data only: everything here
  # round-trips through #to_h / Snapshot.load, and Marshal copies it cheaply.
  class State
    STARTING_LIFE = 20
    PLAYER_ZONES = %i[library hand graveyard].freeze
    SHARED_ZONES = %i[battlefield stack exile].freeze
    ZONES = (PLAYER_ZONES + SHARED_ZONES).freeze
    STEP_STATES = %w[begin active done].freeze

    attr_accessor :seed, :rng, :decklists, :players, :objects, :battlefield, :stack, :exile, :turn, :active,
                  :step, :step_state, :priority, :passes, :next_id, :starting_player, :pending, :result,
                  :attackers, :blockers, :effects, :frames, :attacks_declared,
                  :pending_triggers, :repeat_cleanup, :combat_damage_pass

    def self.initial(names:, decklists:, seed:)
      state = new
      state.seed = seed
      state.rng = Rng.from_seed(seed)
      state.decklists = decklists.map { |l| l.dup.freeze }.freeze
      state.players = names.map { |name| new_player(name) }
      state.objects = {}
      state.battlefield = []
      state.stack = []
      state.exile = []
      state.attackers = {}
      state.blockers = {}
      state.effects = []
      state.frames = []
      state.pending_triggers = []
      state.repeat_cleanup = false
      state.combat_damage_pass = nil
      state.attacks_declared = 0
      state.turn = 0
      state.passes = 0
      state.next_id = 1
      state.step_state = "begin"
      state
    end

    def self.new_player(name)
      PlayerState.new(name: name, life: STARTING_LIFE, poison: 0, library: [], hand: [], graveyard: [],
                      mana_pool: Mana.empty_pool, lands_played: 0, drew_from_empty: false, lost: nil,
                      mulligans: 0, kept: false, mulligan_choice: nil)
    end

    def zone_list(zone, owner)
      SHARED_ZONES.include?(zone) ? public_send(zone) : players[owner].zone(zone)
    end

    def object(id) = objects.fetch(id)
    def opponent(index) = 1 - index
    def over? = !result.nil?

    def to_h
      { "version" => Snapshot::VERSION, "rules" => RULES_VERSION, "seed" => seed, "rng" => rng.state,
        "decklists" => decklists.map(&:dup), "turn" => turn, "active" => active, "step" => step&.to_s,
        "step_state" => step_state, "priority" => priority, "passes" => passes, "next_id" => next_id,
        "starting_player" => starting_player, "pending" => pending&.dup, "result" => result&.dup,
        "players" => players.map(&:to_h), "objects" => objects.values.map(&:to_h),
        "battlefield" => battlefield.dup, "stack" => stack.dup, "exile" => exile.dup,
        "attackers" => attackers.dup, "blockers" => blockers.dup, "effects" => effects.map { deep_dup(it) },
        "frames" => deep_dup(frames), "pending_triggers" => deep_dup(pending_triggers),
        "repeat_cleanup" => repeat_cleanup, "combat_damage_pass" => combat_damage_pass,
        "attacks_declared" => attacks_declared }
    end

    # An independent deep copy, about 10x faster than a Marshal round trip. It walks every
    # instance variable, so fields added later are copied automatically. Strings, symbols,
    # numbers and frozen values are shared: state never mutates them in place.
    def fork
      copy = State.allocate
      instance_variables.each { |ivar| copy.instance_variable_set(ivar, deep_dup(instance_variable_get(ivar))) }
      copy
    end

    def deep_dup(value)
      case value
      when Hash then value.frozen? ? value : value.to_h { |k, v| [k, deep_dup(v)] }
      when Array then value.frozen? ? value : value.map { deep_dup(it) }
      when Struct then value.dup.tap { |copy| copy.each_pair { |k, v| copy[k] = deep_dup(v) } }
      when Rng then Rng.new(value.state)
      else value
      end
    end
  end
end
