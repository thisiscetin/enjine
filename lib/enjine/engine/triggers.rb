# frozen_string_literal: true

module Enjine
  class Engine
    # Triggered abilities (CR 603): matching events, the pending queue, and putting
    # triggers on the stack before a player receives priority (CR 117.5, 603.3).
    module Triggering
      # The object as it last existed on the battlefield, while its zone-change event is
      # being matched (CR 603.10a). Nil otherwise.
      def last_known(id) = @last_known&.[](id)

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
        return unless event.is_a?(trigger.event_class) && trigger.match?(self, event, source)

        state.pending_triggers << { "id" => "t#{next_timestamp!}", "controller" => source["controller"],
                                    "source" => source["id"], "card" => source["card"], "ability" => inst.ref,
                                    "event" => event.to_h }
        emit Events::AbilityTriggered.new(player: name(source["controller"]), source: source["id"],
                                          card: source["card"], ability: inst.ref)
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

      # Creates the triggered ability on the stack and starts choosing its targets.
      # CR 603.3d: a trigger without legal targets is removed.
      def place_trigger!(trigger)
        state.pending_triggers.delete(trigger)
        ability = catalog.fetch(trigger["card"]).ability(trigger["ability"])
        unless ability_targetable?(ability, trigger["controller"], nil)
          emit Events::TriggerRemoved.new(player: name(trigger["controller"]), source: trigger["source"],
                                          card: trigger["card"], reason: "no legal targets")
          return
        end

        obj = create_object(trigger["card"], trigger["controller"], :stack)
        obj.kind = "ability"
        obj.source = trigger["source"]
        obj.ability = trigger["ability"]
        state.stack.unshift(obj.id)
        start_casting!(trigger["controller"], obj.id, "trigger", source: trigger["source"], ability: trigger["ability"],
                                                                 cost: nil)
      end
    end
    include Triggering
  end
end
