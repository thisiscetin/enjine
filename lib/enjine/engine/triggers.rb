# frozen_string_literal: true

module Enjine
  class Engine
    # Triggered abilities (CR 603): matching events, the pending queue, and putting
    # triggers on the stack before a player receives priority (CR 117.5, 603.3).
    module Triggering
      # The object as it last existed on the battlefield, while its zone-change event is
      # being matched (CR 603.10a). Nil otherwise.
      # A permanent that left earlier in the same simultaneous zone change is remembered too (#simultaneously).
      def last_known(id) = @last_known&.[](id) || @departed_together&.dig(id, "lki")

      # What a permanent looked like as it last existed on the battlefield (CR 603.10a, 608.2h):
      # controller and current characteristics, so "a creature you control dies" checks the
      # types it had then, not its printed ones.
      def last_known_info(obj)
        current = chars(obj)
        { "controller" => obj.controller, "card" => obj.card, "types" => current.types, "subtypes" => current.subtypes,
          "power" => current.power, "toughness" => current.toughness, "counters" => obj.counters.dup,
          "keywords" => current.keywords.map(&:to_s), # deathtouch, lifelink, wither (CR 702.2e, 702.15c, 702.80b)
          "token" => token?(obj), "except" => copy_exceptions(obj), "abilities" => current.abilities }
          .merge(obj.memory.slice(Mechanics::Linked::EXILED)) # the cards exiled with it (CR 607.2a)
      end

      def with_last_known(id, info)
        (@last_known ||= {})[id] = info
        yield
      ensure
        @last_known&.delete(id)
      end

      # Called for every event: queue every triggered ability whose condition matches.
      def watch_triggers!(event)
        return if state.step.nil? # no triggers during the pregame

        record_counter_placement!(event)

        trigger_sources.each do |id, instances|
          obj = state.objects[id] or next
          source = { "id" => id, "card" => obj.card, "controller" => obj.controller }
          instances.each { |inst| queue_trigger(inst, event, source) }
        end
        watch_leaving!(event)
        watch_own_cast!(event) if event.is_a?(Events::SpellCast)
        watch_graveyards!(event)
        watch_delayed!(event) unless state.delayed_triggers.empty?
        watch_speed!(event) # CR 702.179d (Engine::Speed)
      end

      # "For the first time each turn" (trigger counters_placed with first_time_this_turn): every placement of
      # counters on a permanent is counted per kind in its memory, stamped with the turn, whether or not any
      # ability triggers on it, so a later placement is never the first (CR 603.2, 122.6). Entering with
      # counters is a placement (CR 122.6).
      def record_counter_placement!(event)
        kinds = case event
                when Events::CountersChanged then event.to > event.from ? [event.counter] : []
                when Events::ZoneChanged
                  obj = event.to == "battlefield" && state.objects[event.new_id]
                  obj ? obj.counters.select { |_, n| n.positive? }.keys : []
                else []
                end
        return if kinds.empty?

        id = event.is_a?(Events::CountersChanged) ? event.object : event.new_id
        return unless state.objects.key?(id)

        placed = object_memory!(id, "counters_placed")
        (kinds + ["*"]).each { placed[it] = placed.fetch(it, 0) + 1 }
      end

      # How many times counters of `kind` (nil: any kind) were put on `id` this turn.
      def counter_placements_this_turn(id, kind)
        turned_memory(state.objects[id], "counters_placed")&.fetch(kind || "*", 0).to_i
      end

      # CR 603.7: creates a delayed triggered ability. `entry` names the card and the ability ref
      # (see Effects::DelayedTrigger) plus what it remembers ("results", "watched" objects) and, for
      # one with a duration ("this turn"), the turn it lasts for ("turn").
      def create_delayed_trigger!(entry)
        state.delayed_triggers << entry.merge("id" => "d#{next_timestamp!}")
      end

      # CR 603.7b: a delayed triggered ability triggers only once, the next time its event occurs, unless
      # it has a stated duration ("whenever ... this turn"): then it triggers each time until the turn ends.
      def watch_delayed!(event)
        state.delayed_triggers.reject! { it["turn"] && it["turn"] != state.turn } # "this turn" has ended
        fired = []
        state.delayed_triggers.each do |entry|
          trigger = catalog.fetch(entry["card"]).ability(entry["ability"]).trigger
          next unless trigger.watches?(event)

          found = Mechanics::Triggers.occurrences(trigger, self, event, delayed_source(entry))
          found = found.first(1) unless repeats?(entry)
          fired << entry unless found.empty?
          found.each do
            queue_pending_trigger!(delayed_source(entry).merge("ability" => entry["ability"]), event, delayed_memory(entry, it))
          end
        end
        state.delayed_triggers -= fired.reject { repeats?(it) }
      end

      # "Whenever ... this turn" triggers each time; "the next ... this turn" ("once") only the first time.
      def repeats?(entry) = entry["turn"] && !entry["once"]

      def delayed_memory(entry, facts)
        { "results" => entry["results"], "watched" => entry["watched"], "triggering" => facts }.compact
      end

      # CR 603.7d-e: its source and controller are those of the spell or ability that created it.
      def delayed_source(entry)
        { "id" => entry["source"], "card" => entry["card"], "controller" => entry["controller"], "watched" => entry["watched"] }
      end

      # Battlefield permanents with triggered abilities, cached with the layer pass
      # (it changes only on the same events that change characteristics).
      def trigger_sources
        return @trigger_sources if @trigger_sources && @trigger_epoch == @epoch && @trigger_state.equal?(state)

        @trigger_epoch = @epoch
        @trigger_state = state
        @trigger_sources = (state.battlefield + (state.command || [])).filter_map do |id| # emblems too (CR 114.4)
          instances = chars(id).triggered_abilities.select { it.ability.zone == :battlefield }
          [id, instances] unless instances.empty?
        end
      end

      # "When ~ dies" / "leaves": the leaving object's own abilities, as it last existed. Permanents that left
      # earlier in the same simultaneous event look back too (CR 603.10a: an artifact destroyed along with
      # creatures sees them die), see #simultaneously.
      def watch_leaving!(event)
        return unless event.is_a?(Events::ZoneChanged) && event.from == "battlefield"

        lki = last_known(event.old_id) or return
        @departed_together&.each_value { queue_leaving_triggers(it, event) }
        gone = { "id" => event.old_id, "card" => event.card, "controller" => lki["controller"], "lki" => lki }
        queue_leaving_triggers(gone, event)
        @departed_together[event.old_id] = gone if @departed_together
      end

      # The abilities it had as it last existed (CR 603.10a): not those it had lost, but those it was granted.
      def queue_leaving_triggers(gone, event)
        source = gone.slice("id", "card", "controller")
        gone["lki"]["abilities"].each do |inst|
          ability = inst.ability
          queue_trigger(inst, event, source) if ability.kind == :triggered && ability.zone == :battlefield &&
                                                ability.trigger.leaves_battlefield?
        end
      end

      # Zone changes made inside the block happen at once (one effect, or state-based actions, CR 704.3):
      # leaves-the-battlefield abilities of permanents that left look back in time at the others (CR 603.10a).
      def simultaneously
        outer = @departed_together
        @departed_together ||= {}
        yield
      ensure
        @departed_together = outer
      end

      # "When you cast this spell" (CR 601.2i): the spell's own ability, functioning on the stack.
      def watch_own_cast!(event)
        obj = state.objects[event.object] or return
        source = { "id" => obj.id, "card" => obj.card, "controller" => obj.controller }
        chars(obj).triggered_abilities.each do |inst|
          queue_trigger(inst, event, source) if inst.ability.trigger.respond_to?(:own_spell?) && inst.ability.trigger.own_spell?
        end
      end

      # CR 113.6k: triggered abilities that function from a graveyard, controlled by the card's owner.
      def watch_graveyards!(event)
        state.players.each_with_index do |pl, owner|
          pl.graveyard.each do |id|
            instances = graveyard_triggers(object(id).card)
            next if instances.empty?

            source = { "id" => id, "card" => object(id).card, "controller" => owner }
            instances.each { queue_trigger(it, event, source) }
          end
        end
      end

      def graveyard_triggers(card)
        (@graveyard_triggers ||= {})[card] ||= catalog.fetch(card).ability_instances.select do |inst|
          inst.ability.kind == :triggered && inst.ability.zone == :graveyard
        end
      end

      def queue_trigger(inst, event, source)
        ability = inst.ability
        trigger = ability.trigger
        return unless trigger.watches?(event)

        found = Mechanics::Triggers.occurrences(trigger, self, event, source)
        return if found.empty?

        # CR 603.4: an intervening "if" is checked for each trigger event, and may ask about it ("that spell")
        found = found.select { ability.condition_met?(self, source["controller"], source["id"], facts: it) }
        return if found.empty?
        return if once_each_turn_used!(ability, inst.ref, source)

        memory = trigger_memory(source)
        batch = trigger.respond_to?(:batched?) && trigger.batched? ? event_batch : nil
        times = 1 + additional_triggers(event, source)
        card, ref = granted_origin(inst.ref) # a granted ability lives in the granting card's data (CR 613.1f)
        queued = source.merge("ability" => ref || inst.ref, "card" => card || source["card"])
        found.first(limited?(ability) ? 1 : found.size).each do |facts|
          next if batch && batched_pending!(source, queued["ability"], batch)

          facts = facts.merge("amount" => 1) if batch # "that many": the occurrences so far (batched_pending!)
          times.times { queue_pending_trigger!(queued, event, memory.merge("triggering" => facts), batch: batch) }
        end
      end

      # A once-each-turn limit: remembered on the source object, so the same card
      # as a new object (CR 400.7) may trigger again.
      def limited?(ability) = ability.respond_to?(:limit) && !ability.limit.nil?

      def once_each_turn_used!(ability, ref, source)
        return false unless limited?(ability)

        obj = state.objects[source["id"]] or return false
        used = (obj.memory["triggered_turn"] ||= {})
        return true if used[ref] == state.turn

        used[ref] = state.turn
        false
      end

      # CR 603.2d: static abilities such as "if you gaining life causes a triggered ability of a permanent
      # you control to trigger, that ability triggers an additional time". Only abilities of permanents;
      # never delayed or reflexive triggered abilities.
      # Resolved effects do the same for the triggered abilities of the objects they affect
      # (Effects::AdditionalTriggersEffect, "for as long as [its source] remains tapped", CR 611.2b).
      def additional_triggers(event, source)
        return 0 unless state.battlefield.include?(source["id"])

        statics = state.battlefield.sum do |id|
          obj = object(id)
          chars(obj).abilities.count do |inst|
            inst.ability.respond_to?(:additional_trigger?) && inst.ability.additional_trigger?(self, event, obj, source)
          end
        end
        statics + state.effects.count do |effect|
          effect["kind"] == "additional_triggers" && effect["affected"].include?(source["id"]) && while_source_holds?(effect)
        end
      end

      # The event batch an event belongs to, for "one or more" triggers (CR 603.2c): everything one effect
      # of a resolving spell or ability does, or one cast or activation (its costs). Outside those, each
      # event is its own batch.
      def event_batch
        frame = state.frames.last or return "event:#{state.next_id}"
        "#{frame["type"]}:#{frame["object"]}:#{frame["pc"]}"
      end

      # Whether a "one or more" trigger already waits for this batch. If so, this occurrence joins it: its
      # "that many" counts the occurrences in the batch (CR 603.2c).
      def batched_pending!(source, ref, batch)
        waiting = state.pending_triggers.select { it["source"] == source["id"] && it["ability"] == ref && it["batch"] == batch }
        waiting.each do |trigger|
          facts = trigger["memory"]["triggering"]
          facts["amount"] = facts.fetch("amount", 1) + 1
        end
        !waiting.empty?
      end

      # `memory` travels to the ability on the stack (its source's last known status, a delayed
      # trigger's remembered objects, the event facts it may refer to). `event` is nil for a reflexive
      # triggered ability (CR 603.12), which triggers on something done during a resolution.
      def queue_pending_trigger!(source, event, memory, batch: nil)
        state.pending_triggers << { "id" => "t#{next_timestamp!}", "controller" => source["controller"],
                                    "source" => source["id"], "card" => source["card"], "ability" => source["ability"],
                                    "event" => event.to_h, "memory" => memory, "batch" => batch }.compact
        emit Events::AbilityTriggered.new(player: name(source["controller"]), source: source["id"],
                                          card: source["card"], ability: source["ability"])
      end

      # CR 117.5 / 603.3: before a player receives priority, pending triggers go on the stack.
      # Returns true when that process was started (priority is given afterwards).
      def put_triggers_first!(index)
        return false if state.pending_triggers.empty?
        return true if state.frames.any? { it["type"] == "put_triggers" }

        state.frames << { "type" => "put_triggers", "then" => index, "next" => nil }
        ask!(nil)
        true
      end

      # Steps the put_triggers frame: APNAP order (CR 603.3b); a player with several
      # triggers picks which goes on the stack next.
      def step_put_triggers!(frame)
        player_index = turn_order_from_active.find { |i| state.pending_triggers.any? { it["controller"] == i } }
        unless player_index
          give_priority!(frame["then"])
          return :done
        end

        mine = pending_triggers_for(player_index)
        chosen = mine.find { it["id"] == frame["next"] } || (mine.first if mine.size == 1)
        unless chosen
          ask!("kind" => "order_triggers", "player" => player_index, "count" => mine.size)
          return :wait
        end

        frame["next"] = nil
        place_trigger!(chosen)
        :push
      end

      def turn_order_from_active
        Array.new(state.players.size) { |i| (state.active + i) % state.players.size }
      end

      def pending_triggers_for(index) = state.pending_triggers.select { it["controller"] == index }

      def choose_trigger!(id)
        state.frames.rfind { it["type"] == "put_triggers" }["next"] = id
        ask!(nil)
      end

      # CR 107.3m: an enters-the-battlefield trigger uses the X its permanent was cast with.
      def entered_x(trigger)
        event = trigger["event"]
        return nil unless event["type"] == "zone_changed" && event["to"] == "battlefield" &&
                          event["new_id"] == trigger["source"]

        state.objects[trigger["source"]]&.x
      end

      # Creates the triggered ability on the stack and starts choosing its targets.
      # CR 603.3d: a trigger without legal targets is removed.
      def place_trigger!(trigger)
        state.pending_triggers.delete(trigger)
        ability = catalog.fetch(trigger["card"]).ability(trigger["ability"])
        unless ability_targetable?(ability, trigger["controller"], nil, trigger["source"], ref: trigger["ability"])
          emit Events::TriggerRemoved.new(player: name(trigger["controller"]), source: trigger["source"],
                                          card: trigger["card"], reason: "no legal targets")
          return
        end

        obj = create_object(trigger["card"], trigger["controller"], :stack)
        obj.kind = "ability"
        obj.source = trigger["source"]
        obj.ability = trigger["ability"]
        obj.memory = Snapshot.deep_copy(trigger.fetch("memory", {}))
        obj.x = entered_x(trigger)
        state.stack.unshift(obj.id)
        start_casting!(trigger["controller"], obj.id, "trigger", source: trigger["source"], ability: trigger["ability"])
      end
    end
    include Triggering
  end
end
