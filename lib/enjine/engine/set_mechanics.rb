# frozen_string_literal: true

module Enjine
  class Engine
    # Engine support for station cards (CR 702.184, 722), Sagas (CR 715, 704.5s), costs that
    # tap another creature (CR 702.184a) and assimilate (CR 701.72). Rule numbers follow the
    # 2026-11-06 Comprehensive Rules (Sagas are CR 714 in the pinned 2026-09-25 text).
    module SetMechanics
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

      # The abilities the object has from its own card: printed ones plus those of applying station symbols.
      def own_ability_instances(obj)
        printed = catalog.fetch(obj.card).ability_instances
        return printed if obj.counters.fetch("charge", 0).zero?

        printed + active_station_symbols(obj).flat_map { catalog.fetch(obj.card).nested_instances(it.ref) }
      end

      # The printed characteristics changed by the object's own station symbols (CR 722.2a-b: abilities,
      # layer 4 "is a creature in addition to its other types", layer 7b base power/toughness) and by
      # assimilation (CR 701.72, 205.1b: an artifact creature whose creature types are replaced by Borg).
      def own_layers(obj, printed, effects)
        symbols = obj.counters.fetch("charge", 0).positive? ? active_station_symbols(obj) : []
        assimilated = !effects.empty? && effects.any? { it["kind"] == "assimilate" && it["affected"].include?(obj.id) }
        added = effects.empty? ? [] : added_subtypes(obj, effects)
        return printed if symbols.empty? && !assimilated && added.empty?

        attrs = printed.to_h
        symbols.each { station_symbol_layers(attrs, it, catalog.fetch(obj.card)) }
        assimilated_layers(attrs) if assimilated
        attrs[:subtypes] = attrs[:subtypes] | added
        Enjine::Characteristics.new(**attrs.transform_values { it.is_a?(Array) ? it.freeze : it })
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

      # ---- Sagas (CR 715) -----------------------------------------------------------------

      # Chapter numbers of a permanent's chapter abilities (CR 715.2).
      def chapter_numbers(id) = chars(id).abilities.filter_map { it.ability.chapter if it.ability.respond_to?(:chapter) }

      # CR 715.3c / 505.4: as the precombat main phase begins, the active player puts a lore counter on
      # each Saga they control with one or more chapter abilities (a turn-based action).
      def add_lore_counters!(index)
        sagas = state.battlefield.select do |id|
          object(id).controller == index && chars(id).subtypes.include?(:saga) && !chapter_numbers(id).empty?
        end
        sagas.each { add_counters!(object(it), "lore", 1) }
      end

      # CR 715.4 / 704.5s: a Saga whose lore counters reach its final chapter number (CR 715.2d) is
      # sacrificed, unless it's the source of a chapter ability that has triggered but not left the stack.
      def saga_complete?(obj)
        c = chars(obj)
        return false unless c.subtypes.include?(:saga)

        chapters = chapter_numbers(obj.id)
        !chapters.empty? && obj.counters.fetch("lore", 0) >= chapters.max && !chapter_pending?(obj)
      end

      def chapter_pending?(obj)
        chapter = ->(card, ref) { catalog.fetch(card).ability(ref).respond_to?(:chapter) }
        state.pending_triggers.any? { it["source"] == obj.id && chapter.call(it["card"], it["ability"]) } ||
          state.stack.any? do |id|
            stacked = object(id)
            stacked.ability? && stacked.source == obj.id && chapter.call(stacked.card, stacked.ability)
          end
      end

      # ---- costs that need a choice (CR 601.2h, 602.2b): "tap another untapped creature you control" ----

      # The index of the next cost of the ability being activated that still needs its choice.
      def next_cost_choice(ctx, ability)
        return nil unless ctx["kind"] == "ability"

        choosing = ability.costs.each_index.select { ability.costs[it].respond_to?(:choice_candidates) }
        made = (ctx["paid"] || []).size
        choosing[made]
      end

      def ask_cost_choice!(ctx, cost)
        ask!("kind" => "choose_cost", "player" => ctx["player"], "cost" => cost.to_s)
        :wait
      end

      def cost_choice_candidates
        ctx = casting
        cost = casting_ability.costs[next_cost_choice(ctx, casting_ability)]
        cost.choice_candidates(self, object(ctx["source"]))
      end

      # Pays the chosen part of the cost now (costs may be paid in any order, CR 601.2h). Cancelling the
      # activation untaps it again (ctx "tapped"). The creature's power is kept for effects that use it.
      def choose_cost!(id)
        ctx = casting
        creature = object(id)
        tap!(creature)
        ctx["tapped"] << id
        (ctx["paid"] ||= []) << { "object" => id, "power" => power(creature) }
        ask!(nil)
      end

      # As a spell or ability becomes cast, activated or put on the stack: it keeps the cost choices
      # (CR 702.184a uses the tapped creature's power), and chosen modes mean its controller faced a
      # dilemma (CR 700.17). Recording it here, not as modes are chosen, keeps a cancelled cast from counting.
      def record_cast_choices!(obj, ctx)
        obj.paid = ctx["paid"].map(&:dup) if ctx["paid"]
        emit Events::DilemmaFaced.new(player: name(ctx["player"]), object: obj.id, modes: obj.modes.dup) if obj.modes
      end

      # ---- assimilate (CR 701.72) -------------------------------------------------------------

      # CR 701.72a: a permanent: gain control of it, put a +1/+1 counter on it, it becomes a Borg artifact creature.
      # CR 701.72b: a permanent card elsewhere: put it onto the battlefield under your control with a +1/+1
      # counter; it's a Borg artifact creature. Returns the assimilated permanent's id (or nil).
      def assimilate!(ref, controller, ctx)
        obj = state.objects[ref] or return nil
        if obj.zone == :battlefield
          gain_control!(obj, controller)
          add_counters!(obj, "+1/+1", 1)
        else
          return nil unless obj.kind == "card" && catalog.fetch(obj.card).permanent? && %i[graveyard exile hand library].include?(obj.zone)

          obj = move!(ref, :battlefield, controller: controller, reason: "assimilate", enters: { "counters" => { "+1/+1" => 1 } })
        end
        # The type change lasts while it stays on the battlefield; ones about objects that left are dropped.
        state.effects.reject! { it["kind"] == "assimilate" && !state.battlefield.include?(it["affected"].first) }
        state.effects << { "kind" => "assimilate", "timestamp" => next_timestamp!, "controller" => ctx.controller,
                           "affected" => [obj.id], "duration" => "permanent" }
        emit Events::EffectStarted.new(kind: "assimilate", affected: [obj.id], details: {})
        obj.id
      end

      # A control change with indefinite duration (CR 613.1b): it becomes a new controller's
      # permanent, newly under their control (CR 302.6), and leaves combat (CR 506.4). The newest
      # control change is remembered, so an older "until end of turn" one doesn't undo it as it ends.
      def gain_control!(obj, controller, timestamp = next_timestamp!)
        obj.memory["control_timestamp"] = timestamp
        return if obj.controller == controller

        leave_combat!(obj.id)
        obj.controller = controller
        obj.controlled_since = state.turn
        emit Events::ControlChanged.new(object: obj.id, controller: name(controller))
      end

      # Layer 4 (CR 613.1d, 205.1b): "becomes a [subtype] in addition to its other types" until end of turn.
      def added_subtypes(obj, effects)
        effects.flat_map { it["kind"] == "add_subtypes" && it["affected"].include?(obj.id) ? it["subtypes"].map(&:to_sym) : [] }
      end
    end
    include SetMechanics
  end
end
