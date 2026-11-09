# frozen_string_literal: true

module Enjine
  class Engine
    # Characteristics after continuous effects (CR 613).
    #
    # The layer pass runs over the whole battlefield in three stages, each finished for every
    # object before the next starts, so an effect in a later layer sees the earlier layers' result:
    #   layers 1-4  the object's own changes (station symbols, assimilate) and type-changing effects
    #   layers 5-6  keywords and granted abilities
    #   layer 7     7a characteristic-defining abilities, 7b setting effects, 7c modifications (effects,
    #               counters, static pumps), 7d switching (none yet)
    # While the pass runs, `chars` answers from the stages done so far, so a static ability counting
    # "artifact creatures you control" sees types after layer 4 without recursing (CR 613.8 guards keep
    # statics from reading power, toughness or combat status).
    module Characteristics
      # The object's current characteristics. Off the battlefield: as printed (with a characteristic-
      # defining power/toughness, CR 604.3). On the battlefield: the result of a whole-board layer pass,
      # cached until state changes.
      def chars(object)
        object = self.object(object) if object.is_a?(String)
        defn = definition(object)
        base = copy_base(object) # layer 1 (CR 613.2a-c): its copiable values
        return board_characteristics.fetch(object.id, base) if object.zone == :battlefield

        defined_pt_copied?(object) ? defined_power_toughness(object, base, defn) : base
      end

      def power(object) = chars(object).power.to_i
      def toughness(object) = chars(object).toughness.to_i
      def power_toughness(object) = chars(object).then { [it.power.to_i, it.toughness.to_i] }
      def loyalty(object) = object.counters.fetch("loyalty", 0)

      # Events after which characteristics may differ; any other event (taps, mana, priority)
      # keeps the cached layer pass. Replacing the whole state (import, fork, rollback) is
      # detected separately by identity. While a static ability has a condition or a computed bonus, or a
      # permanent has a characteristic-defining power/toughness, any event may change the result, so every
      # event drops the cache (`@volatile`, see Engine#emit).
      LAYER_EVENTS = [Events::ZoneChanged, Events::CountersChanged, Events::EffectStarted,
                      Events::EffectsEnded, Events::Attached, Events::Unattached, Events::ControlChanged].freeze

      def touch! = @epoch = @epoch.to_i + 1
      def volatile_layers? = @volatile

      def board_characteristics
        return @layering if @layering # mid-pass: the layers applied so far
        return @board if @board && @board_epoch == @epoch && @board_state.equal?(state)

        @board_epoch = @epoch
        @board_state = state
        @board = apply_layers
      end

      # CR 613.1, 613.4. Only modified objects get an entry; the rest use their printed characteristics.
      def apply_layers
        statics = static_sources
        effects = state.effects
        @volatile = statics.any? { |_, ability| ability.condition || ability.computed? } || defined_on_battlefield?
        return {} if statics.empty? && effects.empty? && !@volatile && state.battlefield.none? { !object(it).counters.empty? }

        @layering = {}
        ids = state.battlefield
        active = statics.select { |source, ability| ability.active?(self, source) }
        ids.each { @layering[it] = type_layers(object(it), active, effects) }
        active = statics.select { |source, ability| ability.active?(self, source) }
        ids.each { @layering[it] = ability_layers(object(it), @layering[it], active, effects) }
        active = statics.select { |source, ability| ability.active?(self, source) }
        bonuses = active.to_h { |source, ability| [[source.id, ability], ability.bonus(self, source)] }
        ids.each { @layering[it] = power_toughness_layers(object(it), @layering[it], active, bonuses, effects) }
        @layering.reject { |id, c| c.equal?(definition(object(id)).printed_characteristics) }
      ensure
        @layering = nil
      end

      def defined_on_battlefield? = state.battlefield.any? { definition(object(it)).defined_pt? }

      def facts(obj, current) = Mechanics::Filters::Facts.new(chars: current, counters: obj.counters, token: token?(obj))

      # ---- layer 1 (CR 613.2a-c, 707.2) ---------------------------------------------------------

      # The object's copiable values (CR 707.2): the printed characteristics of its card, which is the
      # copied card while a copy effect applies (see Engine::Copies), with the exceptions of the copy effect
      # (CR 707.9a-b: "except it isn't legendary", "except it has menace"). Then the characteristic-defining
      # changeling (CR 702.73a, all zones) and abilities a card outside the battlefield gained (CR 113.6b).
      def copy_base(obj)
        defn = definition(obj)
        except = copy_exceptions(obj)
        base = if except && !except.empty?
                 Mechanics::Keywords::Changeling.apply(Copies.apply_exceptions(defn.printed_characteristics, except))
               elsif defn.keywords.include?(:changeling)
                 (@changeling_printed ||= {})[defn.id] ||= Mechanics::Keywords::Changeling.apply(defn.printed_characteristics)
               else
                 defn.printed_characteristics
               end
        return base if state.effects.none? { it["kind"] == "card_ability" }

        granted = card_granted_abilities(obj)
        granted.empty? ? base : base.with(abilities: (base.abilities + granted).freeze)
      end

      # CR 604.3, 707.9d: a characteristic-defining power/toughness, unless a copy exception sets them.
      def defined_pt_copied?(obj)
        except = copy_exceptions(obj)
        definition(obj).defined_pt? && !(except&.key?("power") || except&.key?("toughness"))
      end

      # Layers 1-4: the object's own changes (Engine::SetMechanics#own_layers), then effects that set its
      # creature types (CR 205.1a, 613.1d), statics before resolved effects, each in timestamp order.
      def type_layers(obj, statics, effects)
        base = own_layers(obj, copy_base(obj), effects)
        types = nil
        statics.each do |source, ability|
          types = ability.creature_types if ability.creature_types && ability.affects?(obj, source, facts(obj, base))
        end
        effects.each { types = it["types"].map(&:to_sym) if it["kind"] == "creature_types" && it["affected"].include?(obj.id) }
        return base unless types

        base.with(subtypes: ((base.subtypes & SetMechanics::NON_CREATURE_SUBTYPES) | types).freeze)
      end

      # Layer 6 (CR 613.1f): keyword counters (CR 122.1b), keywords and abilities from static abilities,
      # keywords gained until end of turn. A granted ability is referenced "granted:<card>:<ref>" (the
      # granting card's data holds it, see #granted_origin).
      def ability_layers(obj, base, statics, effects)
        keywords = base.keywords | Mechanics::Counters.keywords(obj.counters)
        abilities = base.abilities
        statics.each do |source, ability|
          next unless (!ability.keywords.empty? || !ability.granted.empty?) && ability.affects?(obj, source, facts(obj, base))

          keywords |= ability.keywords
          abilities += granted_instances(source, ability) unless ability.granted.empty?
        end
        effects.each { keywords |= it["keywords"].map(&:to_sym) if it["kind"] == "grant" && it["affected"].include?(obj.id) }
        return base if keywords == base.keywords && abilities.equal?(base.abilities)

        base.with(keywords: keywords.freeze, abilities: abilities.freeze)
      end

      # Layer 7 (CR 613.4): 7a defined power/toughness, 7b setting effects, 7c counters, static bonuses
      # and pumps (CR 613.4c). Objects without power and toughness are unchanged.
      def power_toughness_layers(obj, base, statics, bonuses, effects)
        defn = definition(obj)
        base = defined_power_toughness(obj, base, defn) if base.creature? && defined_pt_copied?(obj)
        return base if base.power.nil?

        power = base.power
        toughness = base.toughness
        effects.each do |effect|
          if effect["kind"] == "base_power_toughness" && effect["affected"].include?(obj.id)
            power, toughness = effect.values_at("power",
                                                "toughness")
          end
        end
        delta = Mechanics::Counters.power_toughness(obj.counters)
        statics.each do |source, ability|
          next unless ability.pump? && ability.affects?(obj, source, facts(obj, base))

          bonus = bonuses.fetch([source.id, ability])
          delta = [delta[0] + bonus[0], delta[1] + bonus[1]]
        end
        effects.each do
          delta = [delta[0] + it["power"], delta[1] + it["toughness"]] if it["kind"] == "pump" && it["affected"].include?(obj.id)
        end
        power += delta[0]
        toughness += delta[1]
        return base if power == base.power && toughness == base.toughness

        base.with(power: power, toughness: toughness)
      end

      # CR 604.3, 613.4a: power/toughness from a characteristic-defining ability, in every zone.
      def defined_power_toughness(obj, base, defn)
        ctx = Mechanics::EffectContext.new(obj.controller, obj.id, obj.id, [], [])
        base.with(power: defn.power_amount ? defn.power_amount.value(self, ctx) : base.power,
                  toughness: defn.toughness_amount ? defn.toughness_amount.value(self, ctx) : base.toughness)
      end

      def granted_instances(source, ability)
        defn = definition(source)
        ref = own_ability_instances(source).find { it.ability.equal?(ability) }&.ref or return []
        defn.nested_instances(ref).map { AbilityInstance.new(ref: "granted:#{defn.id}:#{it.ref}", ability: it.ability) }
      end

      # For a granted ability's reference: [granting card id, its ref in that card], else nil.
      def granted_origin(ref)
        return nil unless ref.start_with?("granted:")

        ref.delete_prefix("granted:").split(":", 2)
      end

      # [[source object, StaticAbility], ...] for permanents on the battlefield (printed abilities:
      # an ability granting static abilities would need layer dependencies, CR 613.8).
      def static_sources
        state.battlefield.flat_map do |id|
          obj = object(id)
          own_ability_instances(obj).filter_map { [obj, it.ability] if it.ability.kind == :static }
        end
      end

      # Starts a continuous effect from a resolving spell or ability (CR 611.2).
      # The affected set is locked in now (CR 611.2c). An indefinite effect ("permanent") on objects that
      # have all left the battlefield no longer does anything and is dropped. `details` may set "duration".
      def add_continuous_effect!(kind, ctx, affected, details)
        state.effects.reject! { it["duration"] == "permanent" && it["affected"].none? { state.battlefield.include?(it) } }
        details = details.dup
        duration = details.delete("duration") || "end_of_turn"
        effect = { "kind" => kind, "timestamp" => next_timestamp!, "controller" => ctx.controller,
                   "affected" => affected, "duration" => duration }.merge(details)
        state.effects << effect
        emit Events::EffectStarted.new(kind: kind, affected: affected, details: details)
      end

      def next_timestamp!
        state.next_id.tap { state.next_id += 1 }
      end

      # CR 514.2: damage wears off and "until end of turn" effects end.
      def cleanup_turn!
        expire_permissions! # Engine::Permissions
        end_copy_effects! # Engine::Copies
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
