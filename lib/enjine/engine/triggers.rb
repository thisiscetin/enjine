# frozen_string_literal: true

module Enjine
  class Engine
    # Triggered abilities (CR 603): matching events, the pending queue, and putting
    # triggers on the stack before a player receives priority (CR 117.5, 603.3).
    module Triggering
      # The object as it last existed on the battlefield, while its zone-change event is
      # being matched (CR 603.10a). Nil otherwise.
      def last_known(id) = @last_known&.[](id)

      # What a permanent looked like as it last existed on the battlefield (CR 603.10a, 608.2h):
      # controller and current characteristics, so "a creature you control dies" checks the
      # types it had then, not its printed ones.
      def last_known_info(obj)
        current = chars(obj)
        { "controller" => obj.controller, "card" => obj.card, "types" => current.types,
          "power" => current.power, "toughness" => current.toughness, "counters" => obj.counters.dup }
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

        trigger_sources.each do |id, instances|
          obj = state.objects[id] or next
          source = { "id" => id, "card" => obj.card, "controller" => obj.controller }
          instances.each { |inst| queue_trigger(inst, event, source) }
        end
        watch_leaving!(event)
        watch_delayed!(event) unless state.delayed_triggers.empty?
      end

      # CR 603.7: creates a delayed triggered ability. `entry` names the card and the ability ref
      # (see Effects::DelayedTrigger) plus what it remembers ("results").
      def create_delayed_trigger!(entry)
        state.delayed_triggers << entry.merge("id" => "d#{next_timestamp!}")
      end

      # CR 603.7b: a delayed triggered ability triggers only once, the next time its event occurs.
      def watch_delayed!(event)
        fired, state.delayed_triggers = state.delayed_triggers.partition do |entry|
          trigger = catalog.fetch(entry["card"]).ability(entry["ability"]).trigger
          event.is_a?(trigger.event_class) && trigger.match?(self, event, delayed_source(entry))
        end
        fired.each do |entry|
          source = delayed_source(entry).merge("ability" => entry["ability"])
          queue_pending_trigger!(source, event, { "results" => entry["results"] })
        end
      end

      # CR 603.7d-e: its source and controller are those of the spell or ability that created it.
      def delayed_source(entry)
        { "id" => entry["source"], "card" => entry["card"], "controller" => entry["controller"] }
      end

      # Battlefield permanents with triggered abilities, cached with the layer pass
      # (it changes only on the same events that change characteristics).
      def trigger_sources
        return @trigger_sources if @trigger_sources && @trigger_epoch == @epoch && @trigger_state.equal?(state)

        @trigger_epoch = @epoch
        @trigger_state = state
        @trigger_sources = state.battlefield.filter_map do |id|
          instances = chars(id).triggered_abilities
          [id, instances] unless instances.empty?
        end
      end

      # "When ~ dies" / "leaves": the leaving object's own abilities, as it last existed.
      def watch_leaving!(event)
        return unless event.is_a?(Events::ZoneChanged) && event.from == "battlefield"

        lki = last_known(event.old_id) or return
        defn = catalog.fetch(event.card)
        return unless defn.triggered?

        source = { "id" => event.old_id, "card" => event.card, "controller" => lki["controller"] }
        defn.ability_instances.each do |inst|
          queue_trigger(inst, event, source) if inst.ability.kind == :triggered && inst.ability.trigger.leaves_battlefield?
        end
      end

      def queue_trigger(inst, event, source)
        trigger = inst.ability.trigger
        return unless trigger.watches?(event) && trigger.match?(self, event, source)
        return unless inst.ability.condition_met?(self, source["controller"], source["id"]) # CR 603.4

        memory = state.objects[source["id"]]&.memory&.[]("cast") ? { "source_cast" => true } : {}
        card, ref = granted_origin(inst.ref) # a granted ability lives in the granting card's data (CR 613.1f)
        queue_pending_trigger!(source.merge("ability" => ref || inst.ref, "card" => card || source["card"]), event, memory)
      end

      # `memory` travels to the ability on the stack (its source's last known status, a delayed
      # trigger's remembered objects).
      def queue_pending_trigger!(source, event, memory)
        state.pending_triggers << { "id" => "t#{next_timestamp!}", "controller" => source["controller"],
                                    "source" => source["id"], "card" => source["card"], "ability" => source["ability"],
                                    "event" => event.to_h, "memory" => memory }
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
        start_casting!(trigger["controller"], obj.id, "trigger", source: trigger["source"], ability: trigger["ability"],
                                                                 cost: nil)
      end
    end
    include Triggering
  end
end
