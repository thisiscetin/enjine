# frozen_string_literal: true

module Enjine
  # Snapshot validation of object ids and of player-level lists (cards outside the game, restricted mana).
  module Snapshot
    module_function

    # The id names its card ("card#n"): its own card for a copy (Engine::Copies), none if face down (CR 406.3),
    # the card (not the face up) for a card with faces ("alfa/1" is "alfa#n", CardDefinition::Faces).
    def validate_object_id(obj, path, catalog, next_id, errors)
      id = obj["id"]
      match = /\A([a-z0-9_]+)#(\d+)\z/.match(id.to_s)
      own = (obj["memory"].is_a?(Hash) && obj["memory"]["own_card"]) || obj["card"]
      face_down = match && match[1] == Engine::FACE_DOWN_ID && obj["zone"].to_s == "exile" && obj.dig("memory", "face_down") == true
      named = own.to_s.split(CardDefinition::FACE_SEPARATOR).first
      errors << "#{path}.id: malformed #{id.inspect}" unless match && (match[1] == named || face_down)
      errors << "#{path}.memory.own_card: #{own.inspect} is not in the catalog" unless catalog.include?(own.to_s)
      errors << "#{path}.id: #{id} is not below next_id #{next_id}" if match && match[2].to_i >= next_id.to_i
      errors << "#{path}.card: #{obj["card"].inspect} is not in the catalog" unless catalog.include?(obj["card"].to_s)
    end

    # Cards outside the game (CR 400.11a): definition ids only (they aren't objects, CR 400.11), each in the
    # catalog; absent in older snapshots. `outside_lists` holds what each player started with.
    def validate_outside(data, catalog, errors)
      check = lambda do |list, path|
        next errors << "#{path}: must be a list of card ids" unless list.is_a?(Array)

        list.each_with_index do |id, j|
          errors << "#{path}[#{j}]: #{id.inspect} is not in the catalog" unless id.is_a?(String) && catalog[id]&.id == id
        end
      end
      lists = data.fetch("outside_lists", [[], []])
      shaped = lists.is_a?(Array) && lists.size == 2
      errors << "outside_lists: must be a list of 2 card id lists" unless shaped
      lists.each_with_index { |list, i| check.call(list, "outside_lists[#{i}]") } if shaped
      Array(data["players"]).each_with_index do |pl, i|
        check.call(pl.fetch("outside", []), "players[#{i}].outside") if pl.is_a?(Hash)
      end
    end

    # The format and the commanders (CR 903.3): constructed has none; a Commander game has one per player, and
    # only a player's own commander card (besides emblems, CR 114.1) is ever in the command zone. Absent in
    # snapshots of constructed games.
    def build_commanders(state, data)
      state.format = Format.fetch(data.fetch("format", Format::CONSTRUCTED.name))
      state.commanders = data.fetch("commanders", [nil, nil]).dup.freeze
      state.commander_returns = data.fetch("commander_returns", []).dup
    end

    def validate_commanders(data, catalog, errors)
      format = Format::ALL.find { it.name == data.fetch("format", Format::CONSTRUCTED.name) }
      return errors << "format: unknown #{data["format"].inspect}" unless format

      commanders = data.fetch("commanders", [nil, nil])
      listed = commanders.is_a?(Array) && commanders.size == 2 && commanders.all? { it.nil? || (it.is_a?(String) && catalog[it]&.id == it) }
      return errors << "commanders: must be a list of 2 card ids or nulls" unless listed

      errors << "commanders: a Commander game has one each (CR 903.3)" if format.commander? && commanders.any?(&:nil?)
      errors << "commanders: only a Commander game has them (CR 903.3)" if !format.commander? && commanders.any?
      return unless errors.empty? # the objects and players are well formed

      validate_commander_zone(data, commanders, errors)
      validate_commander_progress(data, commanders, errors)
    end

    def validate_commander_zone(data, commanders, errors)
      data["objects"].each do |obj|
        next unless obj["zone"].to_s == "command" && obj.fetch("kind", "card") == "card"

        unless commanders[obj["owner"]] == obj["card"]
          errors << "#{obj["id"]}: only emblems and its owner's commander are in the command zone (CR 114.1, 903.6)"
        end
      end
    end

    # Casts from the command zone (CR 903.8) and combat damage by each commander (CR 903.10a).
    def validate_commander_progress(data, commanders, errors)
      data["players"].each_with_index do |pl, i|
        path = "players[#{i}]"
        casts = pl.fetch("commander_casts", 0)
        errors << "#{path}.commander_casts: must be a non-negative integer" unless non_negative?(casts)
        damage = pl.fetch("commander_damage", {})
        ok = damage.is_a?(Hash) && damage.all? { |card, n| commanders.include?(card) && non_negative?(n) }
        errors << "#{path}.commander_damage: must map commander card ids to non-negative integers" unless ok
      end
    end

    # Pool mana kept apart: restricted (CR 106.6) and/or kept until end of combat (CR 702.189a):
    # [{"mana" => "C", "spend_only" => {...}, "until" => "end_of_combat"}]; absent in older snapshots.
    def validate_restricted_mana(list, errors, path)
      return errors << "#{path}: must be a list" unless list.is_a?(Array)

      list.each_with_index do |entry, i|
        ok = entry.is_a?(Hash) && (entry.keys - %w[mana spend_only until from]).empty? && Mana::TYPES.include?(entry["mana"].to_s.to_sym) &&
             [nil, "end_of_combat"].include?(entry["until"]) && (entry.key?("spend_only") || entry.key?("until")) &&
             (!entry.key?("from") || valid_mana_source?(entry["from"]))
        problems = []
        Mechanics::SpendOnly.build(entry["spend_only"], problems, "#{path}[#{i}].spend_only") if ok && entry.key?("spend_only")
        unless ok
          errors << "#{path}[#{i}]: must be {\"mana\": W/U/B/R/G/C, \"spend_only\": restriction, \"until\": \"end_of_combat\", " \
                    "\"from\": source}"
        end
        errors.concat(problems)
      end
    end

    # The remembered sources of pool mana: one per mana at most (Engine::ManaSources#add_mana!).
    def validate_pool_sources(player, errors, path)
      list = player.fetch("pool_sources", [])
      pool = player["mana_pool"].is_a?(Hash) ? player["mana_pool"] : {}
      ok = list.is_a?(Array) && list.all? do |entry|
        entry.is_a?(Hash) && entry.keys.sort == %w[from mana] && Mana::TYPES.include?(entry["mana"].to_s.to_sym) &&
          valid_mana_source?(entry["from"])
      end
      ok &&= list.map { it["mana"] }.tally.all? { |type, n| n <= pool.fetch(type, 0).to_i }
      errors << "#{path}: must list {\"mana\": type, \"from\": source}, at most one per mana in the pool" unless ok
    end

    # A mana source's remembered characteristics (Engine::ManaSources#mana_provenance).
    def valid_mana_source?(from)
      from.is_a?(Hash) && from.keys.sort == %w[colors name subtypes supertypes types] && from["name"].is_a?(String) &&
        %w[colors subtypes supertypes types].all? { from[it].is_a?(Array) && from[it].all?(String) }
    end

    # Player designations (Engine::Designations): distinct known names; absent in older snapshots.
    def validate_designations(list, errors, path)
      known = Engine::Designations::NAMES
      return if list.is_a?(Array) && list.uniq.size == list.size && list.all? { known.include?(it) }

      errors << "#{path}: must be a list of distinct designations (#{known.join(", ")})"
    end
  end
end
