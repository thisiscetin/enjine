# frozen_string_literal: true

module Enjine
  class Engine
    # Mana the player could make (CR 106, 605): affordability of costs, mana abilities and their options,
    # restricted mana (CR 106.6) and mana costs of mana abilities paid from the pool (CR 605.3a).
    module ManaSources
      # Whether the cost could be paid with the mana pool plus untapped mana sources (CR 601.2g-h).
      # Each colored symbol needs mana of that color, a hybrid symbol mana of either of its colors
      # (CR 107.4e); generic is paid by anything left. `purpose` ({"spell" => id} or {"ability" => source})
      # lets restricted mana count where it may be spent (CR 106.6).
      def affordable?(index, cost, excluded_source, purpose = nil)
        return true if cost.nil? || cost.mana_value.zero?

        units = mana_units(index, excluded_source, purpose)
        return false if units.size < cost.mana_value

        match_colored(cost.requirements, units)
      end

      # Every unit of mana the player could make: pool mana (one fixed type each), restricted pool mana
      # that may be spent on `purpose`, and one unit per untapped source, with the set of types it could
      # produce (a Treasure: any color).
      def mana_units(index, excluded_source, purpose = nil)
        pool_units(index, player(index).mana_pool, purpose) + source_units(index, [excluded_source], purpose)
      end

      def pool_units(index, pool, purpose, restricted = player(index).restricted_mana)
        units = pool.flat_map { |type, n| Array.new([n, 0].max) { [type] } } +
                restricted.select { spendable?(it, purpose) }.map { [it["mana"].to_sym] }
        as_any_type(units, purpose)
      end

      # CR 609.4b: mana spent "as though it were mana of any type" can pay any symbol.
      def as_any_type(units, purpose) = purpose&.[]("any_type") ? units.map { Mana::TYPES } : units

      # Whether a restricted pool entry may be spent on `purpose` (CR 106.6).
      def spendable?(entry, purpose) = Mechanics::SpendOnly.from_data(entry["spend_only"]).allows?(self, purpose)

      # One unit per untapped source not in `excluded`; a source that makes several mana ({C}{C})
      # gives that many units. A source of restricted mana counts only where that mana may be spent; one
      # whose ability costs mana isn't counted (it converts pool mana, CR 605.3a).
      def source_units(index, excluded, purpose = nil)
        by_source = Hash.new { |h, k| h[k] = [] }
        all_mana_sources(index).each do |id, ref|
          next if excluded.include?(id)

          ability = chars(id).ability(ref)
          next if ability.mana_cost || (ability.spend_only && !ability.spend_only.allows?(self, purpose))

          by_source[id].concat(ability.outcomes(self, object(id)))
        end
        units = by_source.values.flat_map { |options| Array.new(options.map(&:size).max) { options.flatten.uniq } }
        as_any_type(units, purpose)
      end

      # Bipartite matching (augmenting paths): can every colored or hybrid symbol (the list of types
      # that can pay it) get its own unit?
      def match_colored(symbols, units)
        owner = Array.new(units.size)
        symbols.each_index.all? { |s| augment(s, symbols, units, owner, Array.new(units.size, false)) }
      end

      def augment(symbol, symbols, units, owner, seen)
        units.each_index.any? do |u|
          next false if seen[u] || !units[u].intersect?(symbols[symbol])

          seen[u] = true
          next false unless owner[u].nil? || augment(owner[u], symbols, units, owner, seen)

          owner[u] = symbol
          true
        end
      end

      def mana_sources(index, excluded_source)
        list = all_mana_sources(index)
        excluded_source ? list.reject { it[0] == excluded_source } : list
      end

      # Every activatable mana ability [id, ability_index] the player controls. Memoized only
      # while legal options are being computed (state can't change then); recomputed otherwise.
      def all_mana_sources(index)
        return scan_mana_sources(index) unless @options_memo

        @options_memo[index] ||= scan_mana_sources(index)
      end

      def scan_mana_sources(index)
        out = []
        state.battlefield.each do |id|
          obj = object(id)
          next unless obj.controller == index

          chars(obj).mana_abilities.each { |inst| out << [id, inst.ref] if inst.ability.activatable?(self, obj) }
        end
        out
      end

      # Activation options for mana abilities: one per source, or one per mana it could add when the
      # mana is chosen as it's activated (`mana`: e.g. "{G}{G}", CR 605.3b).
      def mana_activation_options(sources)
        sources.flat_map do |id, ref|
          ability = chars(id).ability(ref)
          next [{ type: "activate_mana", object: id, ability: ref }] unless ability.choice?

          ability.outcomes(self, object(id)).map { { type: "activate_mana", object: id, ability: ref, mana: Mana.symbols(it) } }
        end
      end

      # CR 605.3: pay the ability's costs and add its mana immediately. Shared by priority and payment.
      # `mana`: the mana chosen as it was activated (an option's "mana"). Restricted mana keeps its
      # restriction in the pool (CR 106.6).
      def activate_mana_ability!(index, id, ability_ref, mana = nil)
        obj = object(id)
        ability = chars(obj).ability(ability_ref) or raise ArgumentError, "#{id} has no ability #{ability_ref}"
        chosen = mana && Mana.parse_produce(mana, [], "mana")
        pay_from_pool!(index, ability.mana_cost, id) if ability.mana_cost
        ability.costs.each { |cost| cost.pay!(self, obj) }
        produced = chosen || ability.outcomes(self, obj).first # CR 605.3b: a fixed amount is counted as it resolves
        add_mana!(index, produced, id, restriction: ability.spend_only&.data)
      end

      # Whether the mana in the pool (unrestricted) can pay `cost` (a mana ability's mana cost, CR 605.3a).
      def pool_covers?(index, cost)
        units = player(index).mana_pool.flat_map { |type, n| Array.new(n) { [type] } }
        units.size >= cost.mana_value && match_colored(cost.requirements, units)
      end

      # Pays a mana ability's mana cost from the pool: each colored or hybrid symbol with mana that keeps
      # the rest payable, then generic mana with colorless first, then the most plentiful color.
      def pay_from_pool!(index, cost, source)
        pool = player(index).mana_pool
        units = pool.flat_map { |type, n| Array.new(n) { type } }
        reqs = cost.requirements
        spent = reqs.each_with_index.map do |req, i|
          type = req.find do |t|
            at = units.index(t) or next false
            match_colored(reqs.drop(i + 1), units.dup.tap { it.delete_at(at) }.map { [it] })
          end
          units.delete_at(units.index(type))
          type
        end
        cost.generic.times do
          type = units.include?(:C) ? :C : units.tally.max_by { |_, n| n }.first
          spent << units.delete_at(units.index(type))
        end
        spent.each do |type|
          pool[type] -= 1
          emit Events::ManaPaid.new(player: name(index), mana: "{#{type}}", object: source)
        end
      end
    end
    include ManaSources
  end
end
