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
      def power(object) = power_toughness(object)[0]
      def toughness(object) = power_toughness(object)[1]
      def loyalty(object) = object.counters.fetch("loyalty", 0)

      def power_toughness(object)
        defn = definition(object)
        pt = [defn.power.to_i, defn.toughness.to_i] # printed values (7a CDAs: none yet)
        # 7b: setting effects — none yet.
        state.effects.each do |effect| # 7c: modifying effects, in timestamp order
          next unless effect["kind"] == "pump" && effect["affected"].include?(object.id)

          pt = [pt[0] + effect["power"], pt[1] + effect["toughness"]]
        end
        net = object.counters.fetch("+1/+1", 0) - object.counters.fetch("-1/-1", 0) # 7c: counters (CR 613.4c)
        # 7d: switching effects — none yet.
        [pt[0] + net, pt[1] + net]
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
        state.battlefield.each { object(it).damage = 0 }
        ending = state.effects.count { it["duration"] == "end_of_turn" }
        return if ending.zero?

        state.effects.reject! { it["duration"] == "end_of_turn" }
        emit Events::EffectsEnded.new(count: ending)
      end
    end
    include Characteristics
  end
end
