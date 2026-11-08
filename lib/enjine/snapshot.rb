# frozen_string_literal: true

module Enjine
  # Converts State to and from plain data, with complete consistency validation.
  #
  # The validation doubles as the engine's invariant check: the fuzzer runs it
  # after every decision of every random game.
  module Snapshot
    VERSION = 1
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
      validate_turn(data, errors) if errors.empty?
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
        [o["id"], GameObject.new(id: o["id"], card: o["card"], owner: o["owner"], controller: o["controller"],
                                 zone: o["zone"].to_sym, tapped: o["tapped"], controlled_since: o["controlled_since"])]
      end
      %w[battlefield stack exile].each { |z| state.public_send("#{z}=", data[z].dup) }
      %w[turn active step_state priority passes next_id starting_player].each do |k|
        state.public_send("#{k}=", data[k])
      end
      state.step = data["step"]&.to_sym
      state.pending = data["pending"]&.dup
      state.result = data["result"]&.dup
      state
    end

    def build_player(hash)
      PlayerState.new(**PLAYER_KEYS.to_h { |k| [k.to_sym, hash[k]] }).tap do |pl|
        pl.library = pl.library.dup
        pl.hand = pl.hand.dup
        pl.graveyard = pl.graveyard.dup
        pl.mana_pool = Mana::TYPES.to_h { |t| [t, hash["mana_pool"].fetch(t.to_s, 0)] }
      end
    end

    def validate_header(data, errors)
      errors << "rng: must be a non-negative integer" unless non_negative?(data["rng"])
      errors << "next_id: must be a positive integer" unless data["next_id"].is_a?(Integer) && data["next_id"].positive?
      unless data["decklists"].is_a?(Array) && data["decklists"].all?(Array)
        errors << "decklists: must be a list of card id lists"
      end
      %w[battlefield stack exile].each { |z| errors << "#{z}: must be a list" unless data[z].is_a?(Array) }
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
      end
      names = players.map { it.is_a?(Hash) ? it["name"] : nil }
      errors << "players: names must be distinct non-empty strings" unless names.all?(String) && names.uniq.size == 2
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
      id = obj["id"]
      match = /\A([a-z0-9_]+)#(\d+)\z/.match(id.to_s)
      errors << "#{path}.id: malformed #{id.inspect}" unless match && match[1] == obj["card"]
      errors << "#{path}.id: #{id} is not below next_id #{next_id}" if match && match[2].to_i >= next_id.to_i
      errors << "#{path}.card: #{obj["card"].inspect} is not in the catalog" unless catalog.include?(obj["card"].to_s)
      %w[owner controller].each { |k| errors << "#{path}.#{k}: must be 0 or 1" unless [0, 1].include?(obj[k]) }
      zone = obj["zone"].to_s
      errors << "#{path}.zone: unknown zone #{zone.inspect}" unless State::ZONES.map(&:to_s).include?(zone)
      errors << "#{path}.tapped: must be true or false" unless [true, false].include?(obj["tapped"])
      return if zone == "battlefield"

      errors << "#{path}: only permanents on the battlefield can be tapped" if obj["tapped"]
      errors << "#{path}: controller must equal owner outside the battlefield" if obj["controller"] != obj["owner"]
    end

    def validate_zone_membership(data, objects, errors)
      placed = Hash.new(0)
      lists = State::SHARED_ZONES.map { |z| [z.to_s, nil, data[z.to_s]] }
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

    def validate_turn(data, errors)
      unless State::STEP_STATES.include?(data["step_state"])
        errors << "step_state: must be one of #{State::STEP_STATES.join(", ")}"
      end
      step = data["step"]
      errors << "step: unknown step #{step.inspect}" unless step.nil? || Steps::BY_NAME.key?(step.to_sym)
      if step
        errors << "active: must be 0 or 1" unless [0, 1].include?(data["active"])
        errors << "turn: must be a positive integer" unless data["turn"].is_a?(Integer) && data["turn"].positive?
        errors << "starting_player: must be 0 or 1" unless [0, 1].include?(data["starting_player"])
      end
      validate_pending(data, errors)
    end

    def validate_pending(data, errors)
      pending = data["pending"]
      if data["result"]
        errors << "pending: must be empty once the game is over" if pending
        return
      end
      return errors << "pending: a game in progress needs a pending decision" unless pending.is_a?(Hash)

      errors << "pending.kind: unknown decision #{pending["kind"].inspect}" unless Decisions::KINDS.key?(pending["kind"])
      errors << "pending.player: must be 0 or 1" unless [0, 1].include?(pending["player"])
      return unless pending["kind"] == "priority" && pending["player"] != data["priority"]

      errors << "pending: priority decision for player #{pending["player"]} but priority is #{data["priority"].inspect}"
    end

    def non_negative?(value) = value.is_a?(Integer) && !value.negative?

    def deep_stringify(value)
      case value
      when Hash then value.to_h { |k, v| [k.to_s, deep_stringify(v)] }
      when Array then value.map { deep_stringify(it) }
      else value
      end
    end
  end
end
