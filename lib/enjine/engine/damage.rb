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

        data = propose("damage", { "source" => source, "target" => ref, "amount" => amount, "combat" => combat }).data
        dealt = deal_proposed_damage!(source, data, combat, lifelink)
        run_follow_ups!(data) # the rest of a prevention effect (CR 615.5)
        dealt
      end

      # The damage event after replacement and prevention effects (CR 614, 615).
      def deal_proposed_damage!(source, data, combat, lifelink)
        amount = data["amount"]
        return 0 unless amount.positive? # prevented (CR 615)

        ref = data["target"] # redirected (CR 614.9)

        has = %i[deathtouch lifelink wither].to_h { [it, damage_source_keyword?(source, it)] }
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
            mark_creature_damage!(obj, source, has[:wither], amount)
            obj.deathtouched = true if has[:deathtouch] # CR 702.2b
          end
          remove_counters!(obj, "loyalty", amount) if defn.planeswalker? # CR 120.3c
        end
        lifelink!(source, amount) if lifelink && has[:lifelink]
        amount
      end

      # CR 120.3d-e: damage to a creature is marked on it; from a source with wither it's -1/-1 counters
      # put by the source's controller instead (CR 702.80a).
      def mark_creature_damage!(obj, source, wither, amount)
        return obj.damage += amount unless wither

        add_counters!(obj, "-1/-1", amount, by_player: damage_source_controller(source))
      end

      # CR 120.6, 120.4a: damage that would be lethal to the creature `id` from `source`, counting damage already
      # marked on it (1 if the source has deathtouch, CR 702.2c); a planeswalker's is its loyalty (CR 120.10).
      # Nil for a player or an object that is neither.
      def lethal_damage(source, id)
        obj = state.objects[id]
        return nil unless obj && state.battlefield.include?(id)
        return loyalty(obj) if !chars(obj).creature? && chars(obj).planeswalker?
        return nil unless chars(obj).creature?

        lethal = [toughness(obj) - obj.damage, 0].max
        damage_source_keyword?(source, :deathtouch) ? [lethal, 1].min : lethal
      end

      # CR 120.4a, 120.10: the excess damage of `amount` dealt to `id`, given its lethal damage before.
      def excess_damage(lethal, amount) = lethal ? [amount - lethal, 0].max : 0

      # Damage dealt at the same time (combat damage, CR 510.2) is one event for prevention effects
      # that apply once per event (a shield counter, CR 122.1c). Nil outside such a batch.
      attr_reader :damage_batch

      def simultaneous_damage
        @damage_batch = []
        yield
      ensure
        @damage_batch = nil
      end

      # Whether a damage source has `keyword` (deathtouch, lifelink, wither): a card (a permanent or a spell) as it
      # is now; a source no longer in the zone it's expected to be in, as it last existed (CR 702.2e, 702.15c,
      # 702.80b).
      def damage_source_keyword?(source, keyword)
        obj = state.objects[source]
        return obj.kind == "card" && chars(obj).keyword?(keyword) if obj

        lki = last_known(source) || resolving_last_known(source) || resolving_source_lki(source)
        Array(lki&.[]("keywords")).include?(keyword.to_s)
      end

      # The controller of a damage source, or as it last existed (CR 702.15b, 702.80a).
      def damage_source_controller(source)
        state.objects[source]&.controller ||
          (last_known(source) || resolving_last_known(source) || resolving_source_lki(source))&.[]("controller")
      end

      # What the resolving ability remembers of its source, if `source` is that source (CR 608.2h).
      def resolving_source_lki(source)
        frame = state.frames.rfind { it["type"] == "resolve" }
        ability = frame && state.objects[frame["object"]]
        ability.memory&.[]("source_lki") if ability && !source.nil? && ability.source == source
      end

      # CR 702.15b: damage dealt by a source with lifelink makes its controller gain that much life.
      def lifelink!(source, amount)
        controller = damage_source_controller(source) or return
        change_life!(controller, amount)
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
      # A creature fighting itself deals twice its power to itself (701.14c). Returns the excess damage `one` dealt
      # to `other` (CR 120.4a: "if excess damage is dealt to [it] this way"), 0 if they didn't fight.
      def fight!(one, other)
        return 0 unless [one, other].all? { state.battlefield.include?(it) && chars(it).creature? }

        lethal = lethal_damage(one, other)
        return excess_damage(lethal, deal_damage!(one, one, 2 * power(object(one)))) if one == other

        powers = [power(object(one)), power(object(other))]
        dealt = deal_damage!(one, other, powers[0])
        deal_damage!(other, one, powers[1])
        excess_damage(lethal, dealt)
      end
    end

    include Damage
  end
end
