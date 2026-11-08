# frozen_string_literal: true

module Enjine
  class Engine
    # Damage, life, counters and permanent state-based actions.
    module Damage
      # CR 120.3: results of damage depend on what receives it.
      def deal_damage!(source, ref, amount)
        return unless amount.positive?

        index = Mechanics::Filters.player_index(self, ref)
        if index
          emit Events::DamageDealt.new(source: source, target: ref, amount: amount)
          change_life!(index, -amount) # CR 120.3a
          return
        end
        return unless state.battlefield.include?(ref)

        obj = object(ref)
        defn = definition(obj)
        emit Events::DamageDealt.new(source: source, target: ref, amount: amount)
        obj.damage += amount if defn.creature? # CR 120.3e
        remove_counters!(obj, "loyalty", amount) if defn.planeswalker? # CR 120.3c
      end

      def change_life!(index, delta)
        return if delta.zero?

        pl = player(index)
        before = pl.life
        pl.life += delta
        emit Events::LifeChanged.new(player: pl.name, from: before, to: pl.life)
      end

      def add_counters!(object, kind, amount)
        return unless amount.positive?

        before = object.counters.fetch(kind, 0)
        object.counters[kind] = before + amount
        emit Events::CountersChanged.new(object: object.id, counter: kind, from: before, to: before + amount)
      end

      def remove_counters!(object, kind, amount)
        before = object.counters.fetch(kind, 0)
        after = [before - amount, 0].max
        return if after == before

        object.counters[kind] = after
        emit Events::CountersChanged.new(object: object.id, counter: kind, from: before, to: after)
      end

      # CR 704.5f, 704.5g, 704.5i. All applicable actions happen simultaneously (CR 704.3).
      # Returns true when anything happened, so the check repeats.
      def check_permanent_state_based_actions!
        doomed = nil
        state.battlefield.each do |id|
          obj = object(id)
          defn = definition(obj)
          reason = if defn.creature? then creature_sba(obj)
                   elsif defn.planeswalker? && loyalty(obj) <= 0 then "sba_loyalty"
                   end
          (doomed ||= []) << [id, reason] if reason
        end
        return false unless doomed

        doomed.each { |id, reason| move!(id, :graveyard, reason: reason) }
        true
      end

      def creature_sba(obj)
        toughness = toughness(obj)
        if toughness <= 0 then "sba_toughness"
        elsif obj.damage.positive? && obj.damage >= toughness then "sba_lethal_damage"
        end
      end
    end
    include Damage
  end
end
