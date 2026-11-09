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
        return Enjine::Characteristics::FACE_DOWN if face_down?(object) && @face_up != object.id # CR 406.3a

        defn = definition(object)
        base = copy_base(object) # layer 1 (CR 613.2a-c): its copiable values
        return board_characteristics.fetch(object.id, base) if object.zone == :battlefield

        base = defined_power_toughness(object, base, defn) if defined_pt_copied?(object)
        with_max_speed(object, base) # CR 702.178b: e.g. an ability that works from the graveyard (Engine::Speed)
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
                      Events::EffectsEnded, Events::Attached, Events::Unattached, Events::ControlChanged,
                      Events::PhasedOut, Events::PhasedIn, Events::SpeedChanged,
                      Events::Transformed, Events::ClassLevelChanged].freeze

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
        return {} if statics.empty? && effects.empty? && !@volatile && printed_board?

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

      # Without effects, every permanent is as printed: none has counters or is a noncreature with printed
      # power and toughness (an uncrewed Vehicle has none, CR 208.3).
      # A max speed ability applying changes it too (Engine::Speed).
      def printed_board?
        speedy = state.players.each_index.any? { max_speed?(it) }
        state.battlefield.none? do |id|
          obj = object(id)
          !obj.counters.empty? || printed_noncreature_pt?(obj) || (speedy && !active_max_speed(obj, obj.controller).empty?) ||
            obj.memory.key?("class_level") # CR 717.2a
        end
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

      # Layers 1-4: the object's own changes and resolved effects that add types (#own_layers),
      # then static abilities that add card types ("this Vehicle is an artifact creature", CR 205.1b), then effects
      # that set its creature types (CR 205.1a, 613.1d), statics before resolved effects, each in timestamp order.
      # A noncreature permanent has no power or toughness, even a Vehicle with them printed (CR 208.3, 301.7a).
      def type_layers(obj, statics, effects)
        base = own_layers(obj, copy_base(obj), effects)
        types = nil
        added = []
        subtypes = []
        statics.each do |source, ability|
          next unless (ability.creature_types || !ability.card_types.empty? || !ability.subtypes.empty?) &&
                      ability.affects?(obj, source, facts(obj, base))

          types = ability.creature_types if ability.creature_types
          added |= ability.card_types
          subtypes |= ability.subtypes
        end
        effects.each { types = it["types"].map(&:to_sym) if it["kind"] == "creature_types" && it["affected"].include?(obj.id) }
        base = with_added_types(base, added) unless added.empty?
        base = base.with(subtypes: ((base.subtypes & Characteristics::NON_CREATURE_SUBTYPES) | types).freeze) if types
        base = base.with(subtypes: (base.subtypes | subtypes).freeze) unless (subtypes - base.subtypes).empty?
        base.creature? || base.power.nil? ? base : base.with(power: nil, toughness: nil)
      end

      # Card types added "in addition to its other types" (CR 205.1b). A permanent that becomes a creature has
      # its printed power and toughness (CR 301.7b), or 0/0 without any, until a layer 7 effect changes them.
      def with_added_types(base, added)
        return base if (added - base.types).empty?

        base = base.with(types: (base.types | added).freeze)
        base.creature? && base.power.nil? ? base.with(power: 0, toughness: 0) : base
      end

      def printed_noncreature_pt?(obj) = definition(obj).then { !it.creature? && !it.power.nil? }

      # Layer 5 (CR 613.1e): effects that set colors. Layer 6 (CR 613.1f): keyword counters (CR 122.1b),
      # keywords and abilities from static abilities,
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
        effects.each do |effect|
          next unless effect["affected"].include?(obj.id)

          keywords |= effect["keywords"].map(&:to_sym) if effect["kind"] == "grant"
          base = base.with(colors: Mana::COLORS & effect["colors"].map(&:to_sym)) if effect["kind"] == "colors" # layer 5
          abilities += effect_granted_instances(effect) if effect["kind"] == "abilities" # e.g. Effects::Become
        end
        return base if keywords == base.keywords && abilities.equal?(base.abilities)

        abilities += (keywords - base.keywords).flat_map { CardDefinition.keyword_instances(it) } # e.g. gains prowess
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

      # Abilities a resolved effect grants (layer 6, CR 613.1f): the effect's card holds them under its ref.
      def effect_granted_instances(effect)
        catalog.fetch(effect["card"]).effect_granted(effect["ref"]).map do |inst|
          AbilityInstance.new(ref: "granted:#{effect["card"]}:#{inst.ref}", ability: inst.ability)
        end
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
        state.effects.reject! do |effect| # a phased-out permanent is still there (CR 702.26d, 702.26f)
          effect["duration"] == "permanent" && effect["affected"].none? { state.battlefield.include?(it) || state.phased_out.include?(it) }
        end
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
      # Subtypes that aren't creature types (CR 205.3g-i). "Becomes a Borg artifact creature"
      # replaces creature types only (CR 205.1b).
      NON_CREATURE_SUBTYPES = %i[
        attraction blood bobblehead book clue communicator contraption equipment food fortification gold heartwood
        incubator infinity junk lander map mutagen powerstone spacecraft stone treasure vehicle vibranium
        aura background cartouche case class curse plan role room rune saga shard shrine
        cave desert forest gate island lair locus mine mountain plains planet power_plant sphere swamp tower town urzas
      ].freeze

      # ---- layers 4 and 7b from the object's own state ------------------------------------

      # Station symbols that apply: "as long as this permanent has N or more charge counters" (CR 722.2a).
      def active_station_symbols(obj)
        charge = obj.counters.fetch("charge", 0)
        defn = catalog.fetch(obj.card)
        defn.ability_instances.select { it.ability.kind == :station_symbol && charge >= it.ability.threshold }
      end

      # The abilities the object has from its own card: printed ones plus those of applying station symbols
      # and max speed abilities (Engine::Speed).
      def own_ability_instances(obj)
        printed = catalog.fetch(obj.card).ability_instances
        symbols = active_max_speed(obj, obj.controller) + active_class_levels(obj) # CR 717.2a (Engine::ClassLevels)
        symbols += active_station_symbols(obj) if obj.counters.fetch("charge", 0).positive?
        return printed if symbols.empty?

        printed + symbols.flat_map { catalog.fetch(obj.card).nested_instances(it.ref) }
      end

      # The printed characteristics changed by the object's own station symbols (CR 722.2a-b: abilities,
      # layer 4 "is a creature in addition to its other types", layer 7b base power/toughness) and by
      # assimilation (CR 701.72, 205.1b: an artifact creature whose creature types are replaced by Borg).
      def own_layers(obj, printed, effects)
        symbols = obj.counters.fetch("charge", 0).positive? ? active_station_symbols(obj) : []
        # same shape: keywords and nested abilities (CR 702.178a, 717.2a)
        symbols += active_max_speed(obj, obj.controller) + active_class_levels(obj)
        assimilated = !effects.empty? && effects.any? { it["kind"] == "assimilate" && it["affected"].include?(obj.id) }
        added = effects.empty? ? [] : added_subtypes(obj, effects)
        becomes = effects.empty? ? [] : effects.select { it["kind"] == "add_types" && it["affected"].include?(obj.id) }
        return printed if symbols.empty? && !assimilated && added.empty? && becomes.empty?

        attrs = printed.to_h
        symbols.each { station_symbol_layers(attrs, it, catalog.fetch(obj.card)) }
        assimilated_layers(attrs) if assimilated
        attrs[:subtypes] = attrs[:subtypes] | added
        becomes.each { added_type_layers(attrs, it) }
        Enjine::Characteristics.new(**attrs.transform_values { it.is_a?(Array) ? it.freeze : it })
      end

      # "Becomes an artifact creature", "becomes a legendary Spider Hero in addition to its other types" (CR 205.1b):
      # card types, supertypes and subtypes are added, none lost. Power/toughness: see Characteristics#with_added_types.
      def added_type_layers(attrs, effect)
        attrs[:types] = attrs[:types] | effect["types"].map(&:to_sym)
        attrs[:supertypes] = attrs[:supertypes] | effect["supertypes"].map(&:to_sym)
        attrs[:subtypes] = attrs[:subtypes] | effect["subtypes"].map(&:to_sym)
        return unless attrs[:types].include?(:creature) && attrs[:power].nil?

        attrs[:power] = 0
        attrs[:toughness] = 0
      end

      def station_symbol_layers(attrs, inst, defn)
        symbol = inst.ability
        attrs[:abilities] = attrs[:abilities] + defn.nested_instances(inst.ref)
        attrs[:keywords] = attrs[:keywords] | symbol.keywords
        return unless symbol.power

        attrs[:types] = attrs[:types] | [:creature] # CR 722.2b
        attrs[:power] = symbol.power
        attrs[:toughness] = symbol.toughness
      end

      def assimilated_layers(attrs)
        attrs[:types] = attrs[:types] | %i[artifact creature]
        attrs[:subtypes] = (attrs[:subtypes] & NON_CREATURE_SUBTYPES) | [:borg]
        attrs[:power] ||= 0 # a card without printed P/T that becomes a creature is 0/0 before counters
        attrs[:toughness] ||= 0
      end

      # Layer 4 (CR 613.1d, 205.1b): "becomes a [subtype] in addition to its other types" until end of turn.
      def added_subtypes(obj, effects)
        effects.flat_map { it["kind"] == "add_subtypes" && it["affected"].include?(obj.id) ? it["subtypes"].map(&:to_sym) : [] }
      end
    end

    include Characteristics
  end
end
