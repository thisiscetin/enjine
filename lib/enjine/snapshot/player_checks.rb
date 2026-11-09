# frozen_string_literal: true

module Enjine
  # Snapshot validation of object ids and of player-level lists (cards outside the game, restricted mana).
  module Snapshot
    module_function

    # The id names its card ("card#n"): its own card for a copy (Engine::Copies), none if face down (CR 406.3).
    def validate_object_id(obj, path, catalog, next_id, errors)
      id = obj["id"]
      match = /\A([a-z0-9_]+)#(\d+)\z/.match(id.to_s)
      own = (obj["memory"].is_a?(Hash) && obj["memory"]["own_card"]) || obj["card"]
      face_down = match && match[1] == Engine::FACE_DOWN_ID && obj["zone"].to_s == "exile" && obj.dig("memory", "face_down") == true
      errors << "#{path}.id: malformed #{id.inspect}" unless match && (match[1] == own || face_down)
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

    # Restricted pool mana (CR 106.6): [{"mana" => "C", "spend_only" => {...}}]; absent in older snapshots.
    def validate_restricted_mana(list, errors, path)
      return errors << "#{path}: must be a list" unless list.is_a?(Array)

      list.each_with_index do |entry, i|
        ok = entry.is_a?(Hash) && entry.keys.sort == %w[mana spend_only] && Mana::TYPES.include?(entry["mana"].to_s.to_sym)
        problems = []
        Mechanics::SpendOnly.build(entry["spend_only"], problems, "#{path}[#{i}].spend_only") if ok
        errors << "#{path}[#{i}]: must be {\"mana\": W/U/B/R/G/C, \"spend_only\": restriction}" unless ok
        errors.concat(problems)
      end
    end
  end
end
