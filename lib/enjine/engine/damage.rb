# frozen_string_literal: true

module Enjine
  class Engine
    # Damage, life and counters (CR 120, 119, 122), and fighting (CR 701.14).
    module Damage
      # CR 120.3: results of damage depend on what receives it. `combat`: combat damage (CR 510.2).
      # Returns the damage dealt. With `lifelink: false` the caller applies lifelink itself
      # (simultaneous combat damage: one life gain event per source, CR 120.3f, 119.9).
      def deal_damage!(source, ref, amount, combat: false, lifelink: true)
        return 0 unless amount.positive?

        data = { "source" => source, "target" => ref, "amount" => amount, "combat" => combat }
        data["unpreventable"] = true if unpreventable?(combat) # CR 615.12 (Engine::Rules)
        amount = propose("damage", data).data["amount"]
        return 0 unless amount.positive? # prevention (CR 615) will reduce it here

        source_chars = damage_source_chars(source)
        index = Mechanics::Filters.player_index(self, ref)
        if index
          emit Events::DamageDealt.new(source: source, target: ref, amount: amount, combat: combat)
          change_life!(index, -amount) # CR 120.3a
        else
          return 0 unless state.battlefield.include?(ref)

          obj = object(ref)
          defn = chars(obj)
          emit Events::DamageDealt.new(source: source, target: ref, amount: amount, combat: combat)
          if defn.creature?
            obj.damage += amount # CR 120.3e
            obj.deathtouched = true if source_chars&.keyword?(:deathtouch) # CR 702.2b
          end
          remove_counters!(obj, "loyalty", amount) if defn.planeswalker? # CR 120.3c
        end
        lifelink!(source, amount) if lifelink && source_chars&.keyword?(:lifelink)
        amount
      end

      # Damage dealt at the same time (combat damage, CR 510.2) is one event for prevention effects
      # that apply once per event (a shield counter, CR 122.1c). Nil outside such a batch.
      attr_reader :damage_batch

      def simultaneous_damage
        @damage_batch = []
        yield
      ensure
        @damage_batch = nil
      end

      # Characteristics of a damage source: a permanent, or the spell/ability on the stack.
      def damage_source_chars(source)
        obj = state.objects[source]
        obj && obj.kind == "card" ? chars(obj) : nil
      end

      # CR 702.15b: damage dealt by a source with lifelink makes its controller gain that much life.
      def lifelink!(source, amount)
        obj = state.objects[source] or return
        change_life!(obj.controller, amount)
      end

      def change_life!(index, delta)
        return if delta.zero?
        return if delta.positive? && player_rule?(index, "cant_gain_life") # CR 119.7: not even replaced

        delta = propose("life", { "player" => index, "delta" => delta }).data["delta"]
        return if delta.zero?

        pl = player(index)
        before = pl.life
        pl.life += delta
        emit Events::LifeChanged.new(player: pl.name, from: before, to: pl.life)
      end

      # `by_player`: the player putting the counters (CR 122.6a; default the permanent's controller).
      def add_counters!(object, kind, amount, by_player: nil)
        return unless amount.positive?

        data = { "object" => object.id, "counter" => kind, "amount" => amount, "player" => by_player || object.controller }
        amount = propose("counters", data).data["amount"]
        return unless amount.positive?

        before = object.counters.fetch(kind, 0)
        object.counters[kind] = before + amount
        # CR 613.7c: keyword counters of this kind get the new counter's timestamp (Engine::Characteristics#ability_layers).
        # The next timestamp isn't taken: an effect created later gets this number too and sorts after it.
        (object.memory["counter_timestamps"] ||= {})[kind] = state.next_id if Mechanics::Counters.keyword?(kind)
        emit Events::CountersChanged.new(object: object.id, counter: kind, from: before, to: before + amount)
      end

      # Counters on a player (CR 122.1): poison (ten or more lose the game, CR 122.1f, 704.5c), experience, rad, ...
      def player_counters(index)
        pl = player(index)
        (pl.counters || {}).merge(pl.poison.positive? ? { "poison" => pl.poison } : {})
      end

      def add_player_counters!(index, kind, amount)
        return unless amount.positive?

        pl = player(index)
        before = player_counters(index).fetch(kind, 0)
        kind == "poison" ? pl.poison += amount : (pl.counters ||= {})[kind] = before + amount
        emit Events::PlayerCountersChanged.new(player: pl.name, counter: kind, from: before, to: before + amount)
      end

      def remove_counters!(object, kind, amount)
        before = object.counters.fetch(kind, 0)
        after = [before - amount, 0].max
        return if after == before

        object.counters[kind] = after
        emit Events::CountersChanged.new(object: object.id, counter: kind, from: before, to: after)
      end

      # ---- damage and counters --------------------------------------------------------------

      # All damage marked on a permanent is removed ("healed", CR 120.6, 514.2).
      def remove_damage!(obj)
        obj.damage = 0
        obj.deathtouched = false
      end

      def remove_all_counters!(obj, kind = nil)
        (kind ? [kind] : obj.counters.keys).each { remove_counters!(obj, it, obj.counters.fetch(it, 0)) }
      end

      # CR 701.14a-d: each creature deals damage equal to its power to the other, at the same time; not
      # combat damage. Neither deals damage unless both are still creatures on the battlefield (701.14b).
      # A creature fighting itself deals twice its power to itself (701.14c).
      def fight!(one, other)
        return unless [one, other].all? { state.battlefield.include?(it) && chars(it).creature? }
        return deal_damage!(one, one, 2 * power(object(one))) if one == other

        powers = [power(object(one)), power(object(other))]
        deal_damage!(one, other, powers[0])
        deal_damage!(other, one, powers[1])
      end
    end

    include Damage
  end
end
