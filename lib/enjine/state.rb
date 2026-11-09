# frozen_string_literal: true

module Enjine
  # A card or token in a zone (CR 109). Refers to its definition by id only.
  # A new GameObject (with a new id) is created on every zone change (CR 400.7).
  GameObject = Struct.new(:id, :card, :owner, :controller, :zone, :tapped, :controlled_since, :kind, :counters,
                          :damage, :source, :ability, :targets, :loyalty_turn, :deathtouched, :modes, :memory,
                          :x, :mana_spent, :attached_to,
                          :paid, # paid: choices made paying costs, e.g. the creature tapped (CR 702.184a)
                          :phased_out) do # {"by" => controller, "indirectly" => bool} while phased out (CR 702.26)
    def ability? = kind == "ability"

    def to_h
      { "id" => id, "card" => card, "owner" => owner, "controller" => controller, "zone" => zone.to_s,
        "tapped" => tapped, "controlled_since" => controlled_since, "kind" => kind, "counters" => counters.dup,
        "damage" => damage, "source" => source, "ability" => ability, "targets" => targets&.dup,
        "loyalty_turn" => loyalty_turn, "deathtouched" => deathtouched,
        "modes" => modes&.dup, "memory" => Marshal.load(Marshal.dump(memory || {})), "x" => x,
        "mana_spent" => mana_spent&.dup, "attached_to" => attached_to, "paid" => paid&.map(&:dup),
        "phased_out" => phased_out&.dup }
    end
  end

  # Per-player game state.
  PlayerState = Struct.new(:name, :life, :poison, :library, :hand, :graveyard, :mana_pool, :lands_played,
                           :drew_from_empty, :lost, :mulligans, :kept, :mulligan_choice,
                           :turn_log, :game_log, # what happened this turn / this game (see Engine::History)
                           :restricted_mana, # mana with a spending restriction (CR 106.6), see Engine#add_mana!
                           :outside, # definition ids of the cards they own outside the game (CR 400.11a)
                           :speed, # nil (no speed) or 1-4 (CR 702.179), see Engine::Speed
                           :designations, # player designations, e.g. "enduring_story" (CR 702.195b), see Engine::Designations
                           :counters, # nil or {kind => n}: counters other than poison (CR 122.1), see Engine#add_player_counters!
                           :pool_sources) do # nil or [{"mana", "from"}]: sources of pool mana made by artifacts (Engine#add_mana!)
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
        "mulligans" => mulligans, "kept" => kept, "mulligan_choice" => mulligan_choice,
        "turn_log" => Marshal.load(Marshal.dump(turn_log || {})), "game_log" => Marshal.load(Marshal.dump(game_log || {})),
        "restricted_mana" => Marshal.load(Marshal.dump(restricted_mana || [])),
        "outside" => (outside || []).dup }.merge(speed ? { "speed" => speed } : {})
        .merge(designations.to_a.empty? ? {} : { "designations" => designations.dup })
        .merge(counters.nil? || counters.empty? ? {} : { "counters" => counters.dup })
        .merge(pool_sources.nil? || pool_sources.empty? ? {} : { "pool_sources" => Marshal.load(Marshal.dump(pool_sources)) })
    end
  end

  # The complete, mutable state of one game. Plain data only: everything here
  # round-trips through #to_h / Snapshot.load, and Marshal copies it cheaply.
  class State
    STARTING_LIFE = 20
    PLAYER_ZONES = %i[library hand graveyard].freeze
    # `phased_out` is not a zone of the rules: phased-out permanents are on the battlefield but treated as
    # though they don't exist (CR 702.26b, 702.26d), so they are kept apart from `battlefield`. The command
    # zone holds emblems (CR 114, 408).
    SHARED_ZONES = %i[battlefield stack exile phased_out command].freeze
    ZONES = (PLAYER_ZONES + SHARED_ZONES).freeze
    STEP_STATES = %w[begin active done].freeze

    attr_accessor :seed, :rng, :decklists, :players, :objects, :battlefield, :stack, :exile, :phased_out, :command, :turn,
                  :active,
                  :step, :step_state, :priority, :passes, :next_id, :starting_player, :pending, :result,
                  :attackers, :blockers, :effects, :frames, :attacks_declared,
                  :pending_triggers, :repeat_cleanup, :combat_damage_pass, :delayed_triggers,
                  :extra_turns, :extra_phases
    # The definition ids each player started the game with outside it (CR 400.11a, 100.4), like
    # `decklists`: a restart begins from these again. What is still outside is PlayerState#outside.
    attr_accessor :outside_lists

    def self.initial(names:, decklists:, seed:, outside: nil)
      state = new
      state.seed = seed
      state.rng = Rng.from_seed(seed)
      state.decklists = decklists.map { |l| l.dup.freeze }.freeze
      state.outside_lists = (outside || names.map { [] }).map { |l| l.dup.freeze }.freeze
      state.players = names.each_with_index.map { |name, i| new_player(name, state.outside_lists[i]) }
      state.objects = {}
      state.battlefield = []
      state.stack = []
      state.exile = []
      state.phased_out = []
      state.command = []
      state.attackers = {}
      state.blockers = {}
      state.effects = []
      state.frames = []
      state.pending_triggers = []
      state.delayed_triggers = []
      state.extra_turns = { "queue" => [], "begun" => [] } # CR 500.7
      state.extra_phases = no_extra_phases # CR 500.8
      state.repeat_cleanup = false
      state.combat_damage_pass = nil
      state.attacks_declared = 0
      state.turn = 0
      state.passes = 0
      state.next_id = 1
      state.step_state = "begin"
      state
    end

    # Phases added this turn (CR 500.8): "pending" [{"after": phase, "phases": ["combat", "main"]}] wait for
    # their phase to end, "queue" lists added phases still to come and "resume" the step the turn goes on
    # with after them (Engine::TurnStructure); "combats" counts combat phases begun this turn.
    def self.no_extra_phases = { "pending" => [], "queue" => [], "combats" => 0 }

    def self.new_player(name, outside = [])
      PlayerState.new(name: name, life: STARTING_LIFE, poison: 0, library: [], hand: [], graveyard: [],
                      mana_pool: Mana.empty_pool, lands_played: 0, drew_from_empty: false, lost: nil,
                      mulligans: 0, kept: false, mulligan_choice: nil, turn_log: {}, game_log: {}, restricted_mana: [],
                      outside: outside.dup)
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
        "battlefield" => battlefield.dup, "stack" => stack.dup, "exile" => exile.dup, "phased_out" => phased_out.dup,
        "command" => (command || []).dup,
        "attackers" => attackers.dup, "blockers" => blockers.dup, "effects" => effects.map { deep_dup(it) },
        **DEEP_FIELDS.to_h { [it, deep_dup(public_send(it))] },
        "repeat_cleanup" => repeat_cleanup, "combat_damage_pass" => combat_damage_pass,
        "attacks_declared" => attacks_declared }.merge("outside_lists" => (outside_lists || []).map(&:dup))
    end

    # Nested fields #to_h deep-copies as they are.
    DEEP_FIELDS = %w[frames pending_triggers delayed_triggers extra_turns extra_phases].freeze

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
