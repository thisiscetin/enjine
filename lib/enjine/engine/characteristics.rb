# frozen_string_literal: true

module Enjine
  class Engine
    # Characteristics after continuous effects (CR 613).
    #
    # Power/toughness are computed through the layer-7 pipeline: 7a characteristic-
    # defining abilities, 7b setting effects, 7c modifications (effects and counters),
    # 7d switching. Stages without implemented mechanics are explicit no-ops, so new
    # mechanics slot into their layer without touching callers.
    module Characteristics
      # The object's current characteristics. Off the battlefield: as printed. On the
      # battlefield: the result of a whole-board layer pass, cached until state changes.
      def chars(object)
        object = self.object(object) if object.is_a?(String)
        base = definition(object).printed_characteristics
        return base unless object.zone == :battlefield

        board_characteristics.fetch(object.id, base)
      end

      def power(object) = chars(object).power.to_i
      def toughness(object) = chars(object).toughness.to_i
      def power_toughness(object) = chars(object).then { [it.power.to_i, it.toughness.to_i] }
      def loyalty(object) = object.counters.fetch("loyalty", 0)

      # Events after which characteristics may differ; any other event (taps, mana, priority)
      # keeps the cached layer pass. Replacing the whole state (import, fork, rollback) is
      # detected separately by identity.
      LAYER_EVENTS = [Events::ZoneChanged, Events::CountersChanged, Events::EffectStarted,
                      Events::EffectsEnded].freeze

      def touch! = @epoch = @epoch.to_i + 1

      def board_characteristics
        return @board if @board && @board_epoch == @epoch && @board_state.equal?(state)

        @board_epoch = @epoch
        @board_state = state
        @board = apply_layers
      end

      # CR 613.1. Layers 1-6 have no effects yet; layer 7 applies setting (7b, none yet),
      # then modifying effects and counters (7c, CR 613.4c), then switching (7d, none yet).
      # Only modified objects get an entry; the rest use their printed characteristics.
      def apply_layers
        modified = {}
        effects = state.effects
        state.battlefield.each do |id|
          obj = object(id)
          next if effects.empty? && obj.counters.empty?

          delta_p = delta_t = obj.counters.fetch("+1/+1", 0) - obj.counters.fetch("-1/-1", 0)
          effects.each do |effect|
            next unless effect["kind"] == "pump" && effect["affected"].include?(id)

            delta_p += effect["power"]
            delta_t += effect["toughness"]
          end
          next if delta_p.zero? && delta_t.zero?

          base = definition(obj).printed_characteristics
          modified[id] = base.with(power: base.power.to_i + delta_p, toughness: base.toughness.to_i + delta_t)
        end
        modified
      end

      # Starts a continuous effect from a resolving spell or ability (CR 611.2).
      # The affected set is locked in now (CR 611.2c).
      def add_continuous_effect!(kind, ctx, affected, details)
        effect = { "kind" => kind, "timestamp" => next_timestamp!, "controller" => ctx.controller,
                   "affected" => affected, "duration" => "end_of_turn" }.merge(details)
        state.effects << effect
        emit Events::EffectStarted.new(kind: kind, affected: affected, details: details)
      end

      def next_timestamp!
        state.next_id.tap { state.next_id += 1 }
      end

      # CR 514.2: damage wears off and "until end of turn" effects end.
      def cleanup_turn!
        state.battlefield.each do |id|
          object(id).damage = 0
          object(id).deathtouched = false
        end
        ending = state.effects.count { it["duration"] == "end_of_turn" }
        return if ending.zero?

        state.effects.reject! { it["duration"] == "end_of_turn" }
        emit Events::EffectsEnded.new(count: ending)
      end
    end
    include Characteristics
  end
end
