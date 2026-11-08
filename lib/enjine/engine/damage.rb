# frozen_string_literal: true

module Enjine
  class Engine
    # Damage, life, counters and permanent state-based actions.
    module Damage
      # CR 120.3: results of damage depend on what receives it.
      def deal_damage!(source, ref, amount)
        return unless amount.positive?

        amount = propose("damage", { "source" => source, "target" => ref, "amount" => amount }).data["amount"]
        return unless amount.positive? # prevention (CR 615) will reduce it here

        source_chars = damage_source_chars(source)
        index = Mechanics::Filters.player_index(self, ref)
        if index
          emit Events::DamageDealt.new(source: source, target: ref, amount: amount)
          change_life!(index, -amount) # CR 120.3a
        else
          return unless state.battlefield.include?(ref)

          obj = object(ref)
          defn = chars(obj)
          emit Events::DamageDealt.new(source: source, target: ref, amount: amount)
          if defn.creature?
            obj.damage += amount # CR 120.3e
            obj.deathtouched = true if source_chars&.keyword?(:deathtouch) # CR 702.2b
          end
          remove_counters!(obj, "loyalty", amount) if defn.planeswalker? # CR 120.3c
        end
        lifelink!(source, amount) if source_chars&.keyword?(:lifelink)
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

        delta = propose("life", { "player" => index, "delta" => delta }).data["delta"]
        return if delta.zero?

        pl = player(index)
        before = pl.life
        pl.life += delta
        emit Events::LifeChanged.new(player: pl.name, from: before, to: pl.life)
      end

      def add_counters!(object, kind, amount)
        return unless amount.positive?

        amount = propose("counters", { "object" => object.id, "counter" => kind, "amount" => amount }).data["amount"]
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
        ceased = remove_tokens_outside_battlefield! # CR 704.5d
        doomed = nil
        state.battlefield.each do |id|
          obj = object(id)
          defn = chars(obj)
          reason = if defn.creature? then creature_sba(obj)
                   elsif defn.planeswalker? && loyalty(obj) <= 0 then "sba_loyalty"
                   end
          (doomed ||= []) << [id, reason] if reason
        end
        return ceased unless doomed

        doomed.each { |id, reason| move!(id, :graveyard, reason: reason) }
        true
      end

      # CR 704.5d / 111.7: a token in a zone other than the battlefield ceases to exist.
      def remove_tokens_outside_battlefield!
        gone = state.objects.values.select { it.zone != :battlefield && it.zone != :stack && catalog.fetch(it.card).token? }
        gone.each do |obj|
          state.zone_list(obj.zone, obj.owner).delete(obj.id)
          state.objects.delete(obj.id)
          emit Events::TokenCeased.new(object: obj.id, card: obj.card, zone: obj.zone.to_s)
        end
        !gone.empty?
      end

      # CR 704.5j: the legend rule needs a choice, so it runs as a frame before priority.
      def legend_rule_first!(index)
        return false if state.frames.any? { it["type"] == "legend_rule" }

        conflict = legend_conflicts.first or return false
        state.frames << { "type" => "legend_rule", "then" => index, "player" => conflict[0], "name" => conflict[1] }
        ask!(nil)
        true
      end

      # [[controller, card name, [ids]]] for every legend-rule violation.
      def legend_conflicts
        groups = state.battlefield.group_by do |id|
          c = chars(id)
          c.legendary? ? [object(id).controller, c.name] : nil
        end
        groups.filter_map { |key, ids| [key[0], key[1], ids] if key && ids.size > 1 }
      end

      def legend_candidates(frame)
        legend_conflicts.find { |player, name, _| player == frame["player"] && name == frame["name"] }&.last || []
      end

      def step_legend_rule!(frame)
        candidates = legend_candidates(frame)
        if candidates.size > 1 && !frame["keep"]
          ask!("kind" => "legend_rule", "player" => frame["player"], "name" => frame["name"])
          return :wait
        end
        (candidates - [frame["keep"]]).each { move!(it, :graveyard, reason: "sba_legend_rule") }
        give_priority!(frame["then"]) # state-based actions are checked again (CR 704.3)
        :done
      end

      def keep_legend!(id)
        state.frames.rfind { it["type"] == "legend_rule" }["keep"] = id
        ask!(nil)
      end

      def creature_sba(obj)
        toughness = toughness(obj)
        return "sba_toughness" if toughness <= 0 # CR 704.5f (indestructible doesn't help)
        return nil if chars(obj).keyword?(:indestructible) # CR 702.12b

        if obj.damage.positive? && obj.damage >= toughness then "sba_lethal_damage" # CR 704.5g
        elsif obj.deathtouched && obj.damage.positive? then "sba_deathtouch" # CR 704.5h
        end
      end
    end
    include Damage
  end
end
