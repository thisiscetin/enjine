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
        statics = static_sources
        effects = state.effects
        return modified if statics.empty? && effects.empty? && state.battlefield.none? { !object(it).counters.empty? }

        state.battlefield.each do |id|
          result = layered(object(id), statics, effects)
          modified[id] = result if result
        end
        modified
      end

      # One object's characteristics after layers 6 and 7c (nil when unchanged). Each layer applies
      # in timestamp order (CR 613.7); static abilities come before resolved effects.
      def layered(obj, statics, effects)
        defn = definition(obj)
        base = defn.printed_characteristics
        keywords = base.keywords | Mechanics::Counters.keywords(obj.counters) # CR 122.1b (layer 6)
        delta = Mechanics::Counters.power_toughness(obj.counters) # CR 122.1a (layer 7c)
        facts = Mechanics::Filters::Facts.new(chars: base, counters: obj.counters, token: defn.token?)
        statics.each do |source, ability|
          next unless ability.affects?(obj, source, facts)

          keywords |= ability.keywords
          delta = [delta[0] + ability.power, delta[1] + ability.toughness]
        end
        effects.each do |effect|
          next unless effect["affected"].include?(obj.id)

          keywords |= effect["keywords"].map(&:to_sym) if effect["kind"] == "grant"
          delta = [delta[0] + effect["power"], delta[1] + effect["toughness"]] if effect["kind"] == "pump"
        end
        return nil if delta == [0, 0] && keywords == base.keywords

        base.with(power: base.power && (base.power + delta[0]), toughness: base.toughness && (base.toughness + delta[1]),
                  keywords: keywords.freeze)
      end

      # [[source object, StaticAbility], ...] for permanents on the battlefield (printed abilities:
      # an ability granting static abilities would need layer dependencies, CR 613.8).
      def static_sources
        state.battlefield.flat_map do |id|
          obj = object(id)
          definition(obj).ability_instances.filter_map { [obj, it.ability] if it.ability.kind == :static }
        end
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
