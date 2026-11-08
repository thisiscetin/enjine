# frozen_string_literal: true

module Enjine
  class Engine
    # Casting spells (CR 601) and activating abilities (CR 602), one atomic decision
    # at a time: announce -> choose targets -> pay mana (tapping sources manually)
    # -> cast. Until every cost is paid the whole process can be cancelled and is
    # rewound (CR 733, "Handling Illegal Actions"). The in-progress context lives in
    # casting so a game can be exported mid-cast.
    module Casting
      # ---- what can be started ---------------------------------------------------

      def castable?(index, id)
        obj = object(id)
        defn = definition(obj)
        return false unless defn.castable?
        return false unless defn.instant_speed? || sorcery_timing?(index)

        ability_targetable?(defn.spell_ability, index, id) && affordable?(index, total_cost(index, defn.mana_cost, spell: obj), nil)
      end

      def activatable?(index, id, ability_ref)
        obj = object(id)
        ability = chars(obj).ability(ability_ref)
        return false unless ability && %i[activated loyalty].include?(ability.kind)
        return false unless obj.zone == ability.zone # CR 113.6: e.g. cycling only from the hand (702.29a)
        return false if ability.sorcery_speed? && !sorcery_timing?(index)
        return false unless ability.costs.reject(&:mana?).all? { it.payable?(self, obj) }

        if (ability.kind == :loyalty) && (obj.loyalty_turn == state.turn || (loyalty(obj) + ability.loyalty_cost).negative?)
          # CR 606.3: once per turn. CR 118.3: a cost can't remove more counters than there are.
          return false
        end

        cost = total_cost(index, ability.mana_cost, ability: ability, source: id)
        ability_targetable?(ability, index, nil, id) && affordable?(index, cost, needs_tap?(ability) ? id : nil)
      end

      # Whether the ability can get legal targets: for modal abilities, enough modes must (CR 700.2).
      def ability_targetable?(ability, index, exclude, source = nil)
        return true if ability.nil?
        return targets_available?(ability.targets, index, exclude, source) unless ability.modal?

        available_modes(ability, index, exclude, source).size >= ability.choose
      end

      def available_modes(ability, index, exclude, source = nil)
        ability.modes.each_index.select { targets_available?(ability.modes[it].targets, index, exclude, source) }
      end

      def targets_available?(specs, index, exclude, source = nil)
        specs.all? { |spec| spec.candidates_for(self, index, source).any? { it != exclude && targetable?(it, index) } }
      end

      # CR 702.11b: hexproof permanents can't be targeted by their controller's opponents.
      def targetable?(ref, index)
        obj = state.objects[ref]
        return true unless obj && obj.zone == :battlefield && obj.controller != index

        !chars(obj).keyword?(:hexproof)
      end

      # Whether the cost could be paid with the mana pool plus untapped mana sources (CR 601.2g-h).
      # Each colored symbol needs mana of that color; generic is paid by anything left. This is
      # exact while every source produces a fixed kind of mana; sources with a choice of colors
      # will need a matching here.
      def affordable?(index, cost, excluded_source)
        return true if cost.nil? || cost.mana_value.zero?

        units = mana_units(index, excluded_source)
        return false if units.size < cost.mana_value

        symbols = cost.colored.flat_map { |color, n| [color] * n }
        match_colored(symbols, units)
      end

      # Every unit of mana the player could make: pool mana (one fixed type each) and one unit per
      # untapped source, with the set of types it could produce (a Treasure: any color).
      # A source that makes several mana ({C}{C}) gives that many units.
      def mana_units(index, excluded_source)
        units = player(index).mana_pool.flat_map { |type, n| Array.new(n) { [type] } }
        by_source = Hash.new { |h, k| h[k] = [] }
        all_mana_sources(index).each do |id, ref|
          by_source[id] << chars(id).ability(ref).produce unless id == excluded_source
        end
        units + by_source.values.flat_map { |options| Array.new(options.map(&:size).max) { options.flatten.uniq } }
      end

      # Bipartite matching (augmenting paths): can every colored symbol get its own unit?
      def match_colored(symbols, units)
        owner = Array.new(units.size)
        symbols.each_index.all? { |s| augment(s, symbols, units, owner, Array.new(units.size, false)) }
      end

      def augment(symbol, symbols, units, owner, seen)
        units.each_index.any? do |u|
          next false if seen[u] || !units[u].include?(symbols[symbol])

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

      # CR 605.3: pay the ability's costs and add its mana immediately. Shared by priority and payment.
      def activate_mana_ability!(index, id, ability_ref)
        obj = object(id)
        ability = chars(obj).ability(ability_ref) or raise ArgumentError, "#{id} has no ability #{ability_ref}"
        ability.costs.each { |cost| cost.pay!(self, obj) }
        add_mana!(index, ability.produce, id)
      end

      # The ability an ability object on the stack represents. It keeps existing even if its
      # source has left the battlefield (CR 113.7a), so it's looked up on the source's card.
      def stack_ability(obj) = definition(obj).ability(obj.ability)

      def needs_tap?(ability) = ability.costs.any?(Mechanics::Costs::Tap)

      # ---- starting ----------------------------------------------------------------

      # CR 601.2a: the card moves to the stack.
      def begin_cast!(index, hand_id)
        hand = player(index).hand
        origin = { "id" => hand_id, "index" => hand.index(hand_id) }
        obj = move!(hand_id, :stack, controller: index, reason: "cast")
        defn = definition(obj)
        start_casting!(index, obj.id, "spell", origin: origin, cost: defn.mana_cost)
      end

      # CR 602.2a: the ability is created on the stack.
      def begin_activation!(index, source_id, ability_ref)
        source = object(source_id)
        ability = chars(source).ability(ability_ref)
        # CR 602.2a: activating from a hidden zone reveals the card.
        emit Events::CardRevealed.new(player: name(index), object: source_id, card: source.card) if source.zone == :hand
        obj = create_object(source.card, index, :stack)
        obj.kind = "ability"
        obj.source = source_id
        obj.ability = ability_ref
        state.stack.unshift(obj.id)
        start_casting!(index, obj.id, "ability", source: source_id, ability: ability_ref, cost: ability.mana_cost)
      end

      # `x` stays nil until announced (CR 601.2b); `remaining` stays nil until the total cost is
      # determined and locked in after targets are chosen (CR 601.2f).
      def start_casting!(index, object_id, kind, cost:, origin: nil, source: nil, ability: nil)
        state.frames << { "type" => "cast", "player" => index, "object" => object_id, "kind" => kind,
                          "origin" => origin, "source" => source, "ability" => ability, "targets" => [], "modes" => [],
                          "x" => cost&.x_symbols&.positive? ? nil : 0, "remaining" => nil,
                          "pool" => player(index).mana_pool.transform_keys(&:to_s), "tapped" => [] }
        ask!(nil) # advance! now steps the cast frame
      end

      # The cast/activation in progress (the top frame while a cast decision is pending).
      def casting
        frame = state.frames.last
        frame if frame && frame["type"] == "cast"
      end

      def casting_ability
        ctx = casting
        obj = object(ctx["object"])
        ctx["kind"] == "spell" ? definition(obj).spell_ability : stack_ability(obj)
      end

      # ---- the in-progress steps --------------------------------------------------

      # Steps the cast frame: modes and X (601.2b), targets (601.2c), total cost (601.2f), payment.
      def continue_casting!
        ctx = casting
        ability = casting_ability
        if ability&.modal? && ctx["modes"].size < ability.choose
          ask!("kind" => "choose_mode", "player" => ctx["player"], "choose" => ability.choose,
               "chosen" => ctx["modes"].size)
          return :wait
        end
        return :wait if ask_x!(ctx)

        specs = casting_targets
        if ctx["targets"].size < specs.size
          ask!("kind" => "choose_target", "player" => ctx["player"], "index" => ctx["targets"].size)
          return :wait
        end
        lock_total_cost!(ctx) unless ctx["remaining"]
        if (cost = next_cost_choice(ctx, ability)) then ask_cost_choice!(ctx, ability.costs[cost])
        elsif ctx["remaining"].values.sum.positive?
          ask!("kind" => "pay_cost", "player" => ctx["player"], "remaining" => remaining_text)
          :wait
        else
          finish_casting!
          :done
        end
      end

      def remaining_text
        rem = casting["remaining"]
        cost = Mana::Cost.new(generic: rem["generic"], colored: rem.except("generic").transform_keys(&:to_sym)
                                                                   .reject { |_, n| n.zero? })
        cost.to_s
      end

      def casting_targets = casting_ability&.targets_for(casting["modes"]) || []

      # CR 601.2b: modes still choosable (distinct, with legal targets).
      def mode_options
        ctx = casting
        available_modes(casting_ability, ctx["player"], ctx["object"], ctx["source"]) - ctx["modes"]
      end

      def choose_mode!(index)
        casting["modes"] << index
        ask!(nil)
      end

      # CR 601.2c: targets, in order; a spell or ability can't target itself (CR 115.5).
      def target_candidates
        ctx = casting
        spec = casting_targets[ctx["targets"].size]
        spec.candidates_for(self, ctx["player"], ctx["source"]).reject { it == ctx["object"] || !targetable?(it, ctx["player"]) }
      end

      def choose_target!(ref)
        ctx = casting
        ctx["targets"] << ref
        emit Events::TargetChosen.new(player: name(ctx["player"]), object: ctx["object"], target: ref)
        ask!(nil)
      end

      # Mana types in the pool that can pay part of the remaining cost (CR 601.2h).
      def payable_mana_types
        ctx = casting
        rem = ctx["remaining"]
        player(ctx["player"]).mana_pool.filter_map do |type, n|
          type.to_s if n.positive? && (rem.fetch(type.to_s, 0).positive? || rem["generic"].positive?)
        end
      end

      def pay_mana!(type)
        ctx = casting
        rem = ctx["remaining"]
        player(ctx["player"]).mana_pool[type.to_sym] -= 1
        rem.fetch(type, 0).positive? ? rem[type] -= 1 : rem["generic"] -= 1
        (ctx["spent"] ||= []) << type # what was spent matters later (sunburst, CR 702.44a)
        emit Events::ManaPaid.new(player: name(ctx["player"]), mana: "{#{type}}", object: ctx["object"])
        ask!(nil)
      end

      # Mana sources usable during payment; a {T} ability's own source is excluded.
      def payment_sources
        ctx = casting
        mana_sources(ctx["player"], payment_excluded_source(ctx))
      end

      def tap_for_payment!(id, ability_index)
        ctx = casting
        activate_mana_ability!(ctx["player"], id, ability_index)
        ctx["tapped"] << id
        ask!(nil)
      end

      # CR 601.2h-i / 602.2b: remaining costs are paid, the spell becomes cast.
      def finish_casting!
        ctx = casting
        index = ctx["player"]
        obj = object(ctx["object"])
        obj.targets = ctx["targets"].dup
        obj.modes = ctx["modes"].dup unless ctx["modes"].empty?
        obj.mana_spent = ctx["spent"].dup if ctx["spent"]
        record_cast_choices!(obj, ctx) # cost choices; facing a dilemma (CR 700.17)
        if ctx["kind"] == "trigger"
          emit Events::TriggerPutOnStack.new(player: name(index), object: obj.id, source: ctx["source"], card: obj.card,
                                             ability: ctx["ability"], targets: obj.targets)
          return # placing continues in the put_triggers frame; no priority yet
        elsif ctx["kind"] == "ability"
          pay_ability_costs!(ctx)
          emit Events::AbilityActivated.new(player: name(index), object: obj.id, card: obj.card, source: ctx["source"],
                                            ability: ctx["ability"], targets: obj.targets)
        else
          emit Events::SpellCast.new(player: name(index), object: obj.id, card: obj.card, targets: obj.targets)
        end
        action_taken!(index) # CR 117.3c (the frame is popped by advance!)
      end

      def pay_ability_costs!(ctx)
        source = object(ctx["source"])
        ability = chars(source).ability(ctx["ability"])
        ability.costs.reject(&:mana?).each { it.pay!(self, source) }
        return unless ability.kind == :loyalty

        source.loyalty_turn = state.turn
        cost = ability.loyalty_cost
        cost.negative? ? remove_counters!(source, "loyalty", -cost) : add_counters!(source, "loyalty", cost)
      end

      # Rewinds an unfinished cast or activation.
      def cancel_casting!
        ctx = casting
        index = ctx["player"]
        # A source sacrificed for mana (a Treasure) is gone and isn't brought back yet (CR 733.1 would).
        ctx["tapped"].select { state.objects.key?(it) }.each do |id|
          object(id).tapped = false
          emit Events::Untapped.new(object: id)
        end
        player(index).mana_pool = Mana::TYPES.to_h { |t| [t, ctx["pool"].fetch(t.to_s, 0)] }
        obj = object(ctx["object"])
        state.stack.delete(obj.id)
        state.objects.delete(obj.id)
        restore_to_hand!(obj, ctx["origin"]) if ctx["kind"] == "spell"
        emit Events::CastCancelled.new(player: name(index), object: obj.id, card: obj.card)
        state.frames.pop
        give_priority!(index)
      end

      def restore_to_hand!(obj, origin)
        state.objects[origin["id"]] = GameObject.new(
          id: origin["id"], card: obj.card, owner: obj.owner, controller: obj.owner, zone: :hand, tapped: false,
          controlled_since: nil, kind: "card", counters: {}, damage: 0, source: nil, ability: nil, targets: nil,
          loyalty_turn: nil, deathtouched: false, modes: nil, memory: {}, attached_to: nil
        )
        player(obj.owner).hand.insert(origin["index"], origin["id"])
      end
    end
    include Casting
  end
end
