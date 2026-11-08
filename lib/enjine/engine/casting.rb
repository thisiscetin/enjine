# frozen_string_literal: true

module Enjine
  class Engine
    # Casting spells (CR 601) and activating abilities (CR 602), one atomic decision
    # at a time: announce -> choose targets -> pay mana (tapping sources manually)
    # -> cast. Until every cost is paid the whole process can be cancelled and is
    # rewound (CR 733, "Handling Illegal Actions"). The in-progress context lives in
    # state.casting so a game can be exported mid-cast.
    module Casting
      # ---- what can be started ---------------------------------------------------

      def castable?(index, id)
        obj = object(id)
        defn = definition(obj)
        return false unless defn.castable?
        return false unless defn.instant_speed? || sorcery_timing?(index)

        targets_available?(defn.spell_ability&.targets || [], index, id) && affordable?(index, defn.mana_cost, nil)
      end

      def activatable?(index, id, ability_index)
        obj = object(id)
        ability = definition(obj).abilities[ability_index]
        return false unless %i[activated loyalty].include?(ability.kind)
        return false if ability.sorcery_speed? && !sorcery_timing?(index)
        return false unless ability.costs.reject(&:mana?).all? { it.payable?(self, obj) }

        if (ability.kind == :loyalty) && (obj.loyalty_turn == state.turn || (loyalty(obj) + ability.loyalty_cost).negative?)
          # CR 606.3: once per turn. CR 118.3: a cost can't remove more counters than there are.
          return false
        end

        targets_available?(ability.targets, index, nil) && affordable?(index, ability.mana_cost, needs_tap?(ability) ? id : nil)
      end

      def targets_available?(specs, index, exclude)
        specs.all? { |spec| spec.candidates(self, index).any? { it != exclude } }
      end

      # A legality bound, not a solver: mana in pool plus untapped mana sources must
      # at least cover the mana value.
      def affordable?(index, cost, excluded_source)
        return true if cost.nil? || cost.mana_value.zero?

        available = player(index).mana_pool.values.sum
        list = all_mana_sources(index)
        available += excluded_source ? list.count { it[0] != excluded_source } : list.size
        available >= cost.mana_value
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

          defn = definition(obj)
          defn.mana_ability_indices.each { |i| out << [id, i] if defn.abilities[i].activatable?(self, obj) }
        end
        out
      end

      # CR 605.3: pay the ability's costs and add its mana immediately. Shared by priority and payment.
      def activate_mana_ability!(index, id, ability_index)
        obj = object(id)
        ability = definition(obj).abilities.fetch(ability_index)
        ability.costs.each { |cost| cost.pay!(self, obj) }
        add_mana!(index, ability.produce, id)
      end

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
      def begin_activation!(index, source_id, ability_index)
        source = object(source_id)
        ability = definition(source).abilities[ability_index]
        obj = create_object(source.card, index, :stack)
        obj.kind = "ability"
        obj.source = source_id
        obj.ability = ability_index
        state.stack.unshift(obj.id)
        start_casting!(index, obj.id, "ability", source: source_id, ability: ability_index, cost: ability.mana_cost)
      end

      def start_casting!(index, object_id, kind, cost:, origin: nil, source: nil, ability: nil)
        remaining = { "generic" => cost&.generic.to_i }
        cost&.colored&.each { |color, n| remaining[color.to_s] = n }
        state.casting = { "player" => index, "object" => object_id, "kind" => kind, "origin" => origin,
                          "source" => source, "ability" => ability, "targets" => [], "remaining" => remaining,
                          "pool" => player(index).mana_pool.transform_keys(&:to_s), "tapped" => [] }
        continue_casting!
      end

      def casting_ability
        ctx = state.casting
        obj = object(ctx["object"])
        ctx["kind"] == "spell" ? definition(obj).spell_ability : definition(obj).abilities[ctx["ability"]]
      end

      # ---- the in-progress steps --------------------------------------------------

      def continue_casting!
        ctx = state.casting
        specs = casting_ability&.targets || []
        if ctx["targets"].size < specs.size
          ask!("kind" => "choose_target", "player" => ctx["player"], "index" => ctx["targets"].size)
        elsif ctx["remaining"].values.sum.positive?
          ask!("kind" => "pay_cost", "player" => ctx["player"], "remaining" => remaining_text)
        else
          finish_casting!
        end
      end

      def remaining_text
        rem = state.casting["remaining"]
        cost = Mana::Cost.new(generic: rem["generic"], colored: rem.except("generic").transform_keys(&:to_sym)
                                                                   .reject { |_, n| n.zero? })
        cost.to_s
      end

      # CR 601.2c: targets, in order; a spell or ability can't target itself (CR 115.5).
      def target_candidates
        ctx = state.casting
        spec = casting_ability.targets[ctx["targets"].size]
        spec.candidates(self, ctx["player"]).reject { it == ctx["object"] }
      end

      def choose_target!(ref)
        ctx = state.casting
        ctx["targets"] << ref
        emit Events::TargetChosen.new(player: name(ctx["player"]), object: ctx["object"], target: ref)
        continue_casting!
      end

      # Mana types in the pool that can pay part of the remaining cost (CR 601.2h).
      def payable_mana_types
        ctx = state.casting
        rem = ctx["remaining"]
        player(ctx["player"]).mana_pool.filter_map do |type, n|
          type.to_s if n.positive? && (rem.fetch(type.to_s, 0).positive? || rem["generic"].positive?)
        end
      end

      def pay_mana!(type)
        ctx = state.casting
        rem = ctx["remaining"]
        player(ctx["player"]).mana_pool[type.to_sym] -= 1
        rem.fetch(type, 0).positive? ? rem[type] -= 1 : rem["generic"] -= 1
        emit Events::ManaPaid.new(player: name(ctx["player"]), mana: "{#{type}}", object: ctx["object"])
        continue_casting!
      end

      # Mana sources usable during payment; a {T} ability's own source is excluded.
      def payment_sources
        ctx = state.casting
        excluded = ctx["kind"] == "ability" && needs_tap?(casting_ability) ? ctx["source"] : nil
        mana_sources(ctx["player"], excluded)
      end

      def tap_for_payment!(id, ability_index)
        ctx = state.casting
        activate_mana_ability!(ctx["player"], id, ability_index)
        ctx["tapped"] << id
        continue_casting!
      end

      # CR 601.2h-i / 602.2b: remaining costs are paid, the spell becomes cast.
      def finish_casting!
        ctx = state.casting
        index = ctx["player"]
        obj = object(ctx["object"])
        obj.targets = ctx["targets"].dup
        if ctx["kind"] == "ability"
          pay_ability_costs!(ctx)
          emit Events::AbilityActivated.new(player: name(index), object: obj.id, card: obj.card, source: ctx["source"],
                                            ability: ctx["ability"], targets: obj.targets)
        else
          emit Events::SpellCast.new(player: name(index), object: obj.id, card: obj.card, targets: obj.targets)
        end
        state.casting = nil
        action_taken!(index) # CR 117.3c
      end

      def pay_ability_costs!(ctx)
        source = object(ctx["source"])
        ability = definition(source).abilities[ctx["ability"]]
        ability.costs.reject(&:mana?).each { it.pay!(self, source) }
        return unless ability.kind == :loyalty

        source.loyalty_turn = state.turn
        cost = ability.loyalty_cost
        cost.negative? ? remove_counters!(source, "loyalty", -cost) : add_counters!(source, "loyalty", cost)
      end

      # Rewinds an unfinished cast or activation.
      def cancel_casting!
        ctx = state.casting
        index = ctx["player"]
        ctx["tapped"].each do |id|
          object(id).tapped = false
          emit Events::Untapped.new(object: id)
        end
        player(index).mana_pool = Mana::TYPES.to_h { |t| [t, ctx["pool"].fetch(t.to_s, 0)] }
        obj = object(ctx["object"])
        state.stack.delete(obj.id)
        state.objects.delete(obj.id)
        restore_to_hand!(obj, ctx["origin"]) if ctx["kind"] == "spell"
        emit Events::CastCancelled.new(player: name(index), object: obj.id, card: obj.card)
        state.casting = nil
        give_priority!(index)
      end

      def restore_to_hand!(obj, origin)
        state.objects[origin["id"]] = GameObject.new(
          id: origin["id"], card: obj.card, owner: obj.owner, controller: obj.owner, zone: :hand, tapped: false,
          controlled_since: nil, kind: "card", counters: {}, damage: 0, source: nil, ability: nil, targets: nil,
          loyalty_turn: nil
        )
        player(obj.owner).hand.insert(origin["index"], origin["id"])
      end
    end
    include Casting
  end
end
