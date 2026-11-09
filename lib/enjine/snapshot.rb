# frozen_string_literal: true

require_relative "snapshot/turn_checks"
require_relative "snapshot/player_checks"

module Enjine
  # Converts State to and from plain data, with complete consistency validation.
  #
  # The validation doubles as the engine's invariant check: the fuzzer runs it
  # after every decision of every random game.
  module Snapshot
    VERSION = 2
    PLAYER_KEYS = %w[name life poison library hand graveyard mana_pool lands_played drew_from_empty lost
                     mulligans kept mulligan_choice].freeze

    module_function

    def validate(data, catalog)
      errors = []
      return ["snapshot must be an object"] unless data.is_a?(Hash)
      return ["version: expected #{VERSION}, got #{data["version"].inspect}"] unless data["version"] == VERSION

      validate_header(data, errors)
      validate_players(data, errors)
      validate_objects(data, catalog, errors)
      validate_combat(data, errors) if errors.empty?
      validate_turn(data, errors) if errors.empty?
      validate_delayed_triggers(data, catalog, errors) if errors.empty?
      validate_extra_turns(data, errors)
      validate_outside(data, catalog, errors)
      errors
    end

    def load(data, catalog)
      data = deep_stringify(data)
      errors = validate(data, catalog)
      raise InvalidSnapshot, errors unless errors.empty?

      build(data)
    end

    def build(data)
      state = State.new
      state.seed = data["seed"]
      state.rng = Rng.new(data["rng"])
      state.decklists = data["decklists"].map { |l| l.dup.freeze }.freeze
      state.players = data["players"].map { |p| build_player(p) }
      state.objects = data["objects"].to_h do |o|
        [o["id"], build_object(o)]
      end
      State::SHARED_ZONES.each { |z| state.public_send("#{z}=", data.fetch(z.to_s, []).dup) }
      state.attackers = deep_copy(data.fetch("attackers", {}))
      state.blockers = deep_copy(data.fetch("blockers", {}))
      state.effects = deep_copy(data.fetch("effects", []))
      state.frames = deep_copy(data.fetch("frames", []))
      state.pending_triggers = deep_copy(data.fetch("pending_triggers", []))
      state.delayed_triggers = deep_copy(data.fetch("delayed_triggers", []))
      state.extra_turns = deep_copy(data.fetch("extra_turns", { "queue" => [], "begun" => [] }))
      state.outside_lists = data.fetch("outside_lists", [[], []]).map { |l| l.dup.freeze }.freeze
      state.repeat_cleanup = data.fetch("repeat_cleanup", false)
      state.combat_damage_pass = data["combat_damage_pass"]
      state.attacks_declared = data.fetch("attacks_declared", 0)
      %w[turn active step_state priority passes next_id starting_player].each do |k|
        state.public_send("#{k}=", data[k])
      end
      state.step = data["step"]&.to_sym
      state.pending = data["pending"]&.dup
      state.result = data["result"]&.dup
      state
    end

    def build_object(hash)
      GameObject.new(id: hash["id"], card: hash["card"], owner: hash["owner"], controller: hash["controller"],
                     zone: hash["zone"].to_sym, tapped: hash["tapped"], controlled_since: hash["controlled_since"],
                     kind: hash.fetch("kind", "card"), counters: deep_copy(hash.fetch("counters", {})),
                     damage: hash.fetch("damage", 0), source: hash["source"], ability: hash["ability"],
                     targets: deep_copy(hash["targets"]), loyalty_turn: hash["loyalty_turn"],
                     deathtouched: hash.fetch("deathtouched", false), modes: hash["modes"]&.dup,
                     memory: deep_copy(hash.fetch("memory", {})), x: hash["x"], mana_spent: hash["mana_spent"]&.dup,
                     attached_to: hash["attached_to"], paid: hash["paid"] && deep_copy(hash["paid"]),
                     phased_out: hash["phased_out"]&.dup)
    end

    def deep_copy(value) = Marshal.load(Marshal.dump(value))

    def build_player(hash)
      PlayerState.new(**PLAYER_KEYS.to_h { |k| [k.to_sym, hash[k]] }).tap do |pl|
        pl.library = pl.library.dup
        pl.hand = pl.hand.dup
        pl.graveyard = pl.graveyard.dup
        pl.mana_pool = Mana::TYPES.to_h { |t| [t, hash["mana_pool"].fetch(t.to_s, 0)] }
        pl.turn_log = deep_copy(hash.fetch("turn_log", {}))
        pl.game_log = deep_copy(hash.fetch("game_log", {}))
        pl.restricted_mana = deep_copy(hash.fetch("restricted_mana", []))
        pl.outside = hash.fetch("outside", []).dup
        pl.speed = hash["speed"] # CR 702.179; absent: no speed
        pl.designations = hash.fetch("designations", []).dup # CR 702.195b (Engine::Designations)
      end
    end

    def validate_header(data, errors)
      errors << "rng: must be a non-negative integer" unless non_negative?(data["rng"])
      errors << "next_id: must be a positive integer" unless data["next_id"].is_a?(Integer) && data["next_id"].positive?
      errors << "decklists: must be a list of card id lists" unless data["decklists"].is_a?(Array) && data["decklists"].all?(Array)
      %w[battlefield stack exile].each { |z| errors << "#{z}: must be a list" unless data[z].is_a?(Array) }
      errors << "phased_out: must be a list" unless data.fetch("phased_out", []).is_a?(Array)
    end

    def validate_players(data, errors)
      players = data["players"]
      return errors << "players: must be a list of 2 players" unless players.is_a?(Array) && players.size == 2

      players.each_with_index do |pl, i|
        path = "players[#{i}]"
        next errors << "#{path}: must be an object" unless pl.is_a?(Hash)

        (PLAYER_KEYS - pl.keys).each { |k| errors << "#{path}.#{k}: missing" }
        %w[life poison lands_played mulligans].each do |k|
          errors << "#{path}.#{k}: must be an integer" unless pl[k].is_a?(Integer)
        end
        %w[library hand graveyard].each { |z| errors << "#{path}.#{z}: must be a list" unless pl[z].is_a?(Array) }
        pool = pl["mana_pool"]
        unless pool.is_a?(Hash) && pool.all? { |t, n| Mana::TYPES.include?(t.to_sym) && non_negative?(n) }
          errors << "#{path}.mana_pool: must map W/U/B/R/G/C to non-negative integers"
        end
        validate_restricted_mana(pl.fetch("restricted_mana", []), errors, "#{path}.restricted_mana")
        errors << "#{path}.speed: must be 1, 2, 3 or 4 (or absent)" unless [nil, 1, 2, 3, 4].include?(pl["speed"]) # CR 702.179
        validate_designations(pl.fetch("designations", []), errors, "#{path}.designations")
      end
      validate_logs(players, errors)
      names = players.map { it.is_a?(Hash) ? it["name"] : nil }
      errors << "players: names must be distinct non-empty strings" unless names.all?(String) && names.uniq.size == 2
    end

    # What happened this turn and this game (Engine::TurnHistory); absent in older snapshots.
    def validate_logs(players, errors)
      players.each_with_index.select { |pl, _| pl.is_a?(Hash) }.each do |pl, i|
        %w[turn_log game_log].each { |k| errors << "players[#{i}].#{k}: must be an object" unless pl.fetch(k, {}).is_a?(Hash) }
      end
    end

    def validate_objects(data, catalog, errors)
      objects = data["objects"]
      return errors << "objects: must be a list" unless objects.is_a?(Array)
      return unless errors.empty?

      seen = {}
      objects.each_with_index do |o, i|
        path = "objects[#{i}]"
        next errors << "#{path}: must be an object" unless o.is_a?(Hash)

        id = o["id"]
        errors << "#{path}: duplicate id #{id.inspect}" if seen.key?(id)
        seen[id] = o
        validate_object(o, path, catalog, data["next_id"], errors)
      end
      validate_zone_membership(data, seen, errors)
    end

    def validate_object(obj, path, catalog, next_id, errors)
      validate_object_id(obj, path, catalog, next_id, errors)
      %w[owner controller].each { |k| errors << "#{path}.#{k}: must be 0 or 1" unless [0, 1].include?(obj[k]) }
      zone = obj["zone"].to_s
      errors << "#{path}.zone: unknown zone #{zone.inspect}" unless State::ZONES.map(&:to_s).include?(zone)
      errors << "#{path}.tapped: must be true or false" unless [true, false].include?(obj["tapped"])
      validate_object_state(obj, path, zone, errors)
      validate_phasing(obj, path, zone, errors)
      return if %w[battlefield stack phased_out].include?(zone)

      errors << "#{path}: only permanents on the battlefield can be tapped" if obj["tapped"]
      errors << "#{path}: controller must equal owner outside the battlefield and stack" if obj["controller"] != obj["owner"]
    end

    def validate_object_state(obj, path, zone, errors)
      kind = obj.fetch("kind", "card")
      errors << "#{path}.kind: must be \"card\" or \"ability\"" unless %w[card ability].include?(kind)
      if kind == "ability"
        errors << "#{path}: abilities can only exist on the stack" unless zone == "stack"
        errors << "#{path}.ability: must be an ability reference" unless obj["ability"].is_a?(String)
      end
      counters = obj.fetch("counters", {})
      unless counters.is_a?(Hash) && counters.all? { |k, v| Mechanics::Counters.valid?(k) && non_negative?(v) }
        errors << "#{path}.counters: must map counter kinds to non-negative integers"
      end
      errors << "#{path}.damage: must be a non-negative integer" unless non_negative?(obj.fetch("damage", 0))
      errors << "#{path}.memory: must be an object" unless obj.fetch("memory", {}).is_a?(Hash)
      validate_cast_info(obj, path, errors)
      validate_attachment(obj, path, zone, errors)
      return if ON_BATTLEFIELD.include?(zone)

      return unless counters.values.any?(&:positive?) || obj["damage"].to_i.positive?

      errors << "#{path}: only permanents have counters or damage"
    end

    # The X announced for a spell or ability and the mana spent on it (CR 107.3a, 702.44a).
    def validate_cast_info(obj, path, errors)
      errors << "#{path}.x: must be a non-negative integer" unless obj["x"].nil? || non_negative?(obj["x"])
      spent = obj["mana_spent"]
      return if spent.nil? || (spent.is_a?(Array) && spent.all? { Mana::TYPES.map(&:to_s).include?(it) })

      errors << "#{path}.mana_spent: must be a list of mana types"
    end

    # CR 701.3: only a permanent is attached, never to itself. The object it names may already
    # be gone: state-based actions (704.5m/n) clean that up before the next priority.
    def validate_attachment(obj, path, zone, errors)
      to = obj["attached_to"]
      return if to.nil?

      errors << "#{path}.attached_to: must be another object's id" unless to.is_a?(String) && to != obj["id"]
      errors << "#{path}: only permanents on the battlefield can be attached" unless ON_BATTLEFIELD.include?(zone)
    end

    # Phased out (CR 702.26): still a permanent on the battlefield, kept in the `phased_out` list with who
    # controlled it as it phased out and whether it phased out indirectly.
    ON_BATTLEFIELD = %w[battlefield phased_out].freeze

    def validate_phasing(obj, path, zone, errors)
      info = obj["phased_out"]
      return errors << "#{path}.phased_out: only phased-out permanents have it" if info && zone != "phased_out"
      return if zone != "phased_out"
      return if info.is_a?(Hash) && [0, 1].include?(info["by"]) && [true, false].include?(info["indirectly"])

      errors << "#{path}.phased_out: must be {\"by\": 0 or 1, \"indirectly\": true or false}"
    end

    def validate_combat(data, errors)
      battlefield = data["battlefield"]
      attackers = data.fetch("attackers", {})
      blockers = data.fetch("blockers", {})
      return errors << "attackers/blockers: must be objects" unless attackers.is_a?(Hash) && blockers.is_a?(Hash)

      attackers.each_key { |id| errors << "attackers: #{id} is not on the battlefield" unless battlefield.include?(id) }
      blockers.each do |id, attacker|
        errors << "blockers: #{id} is not on the battlefield" unless battlefield.include?(id)
        errors << "blockers: #{id} blocks #{attacker}, which is not attacking" unless attackers.key?(attacker)
      end
      errors << "effects: must be a list" unless data.fetch("effects", []).is_a?(Array)
      validate_frames(data, errors)
    end

    def validate_frames(data, errors)
      frames = data.fetch("frames", [])
      return errors << "frames: must be a list" unless frames.is_a?(Array)

      frames.each_with_index do |frame, i|
        klass = frame.is_a?(Hash) && Frames::KINDS[frame["type"]]
        next errors << "frames[#{i}]: unknown frame #{frame.inspect[0, 60]}" unless klass

        klass.validate(frame, data, errors)
      end
      top = frames.last
      kind = data.dig("pending", "kind")
      return unless top && kind && !Frames.fetch(top["type"]).decisions.include?(kind)

      errors << "pending: #{kind} can't be pending while a #{top["type"]} frame is in progress"
    end

    def validate_zone_membership(data, objects, errors)
      placed = Hash.new(0)
      lists = State::SHARED_ZONES.map { |z| [z.to_s, nil, data.fetch(z.to_s, [])] }
      data["players"].each_with_index do |pl, i|
        State::PLAYER_ZONES.each { |z| lists << [z.to_s, i, pl[z.to_s]] }
      end
      lists.each do |zone, owner, ids|
        ids.each do |id|
          placed[id] += 1
          obj = objects[id]
          next errors << "#{zone}: unknown object #{id.inspect}" unless obj
          next errors << "#{id}: listed in #{zone} but its zone is #{obj["zone"]}" unless obj["zone"].to_s == zone
          next unless owner && obj["owner"] != owner

          errors << "#{id}: in #{data["players"][owner]["name"]}'s #{zone} but owned by player #{obj["owner"]}"
        end
      end
      objects.each_key { |id| errors << "#{id}: in #{placed[id]} zones, expected exactly 1" if placed[id] != 1 }
    end

    def non_negative?(value) = value.is_a?(Integer) && !value.negative?

    def deep_stringify(value)
      case value
      when Hash then value.to_h { |k, v| [k.to_s, deep_stringify(v)] }
      when Array then value.map { deep_stringify(it) }
      when Symbol then value.to_s
      else value
      end
    end
  end
end
