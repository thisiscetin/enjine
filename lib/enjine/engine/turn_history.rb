# frozen_string_literal: true

module Enjine
  class Engine
    # What happened this turn and this game, for effects and conditions that look back ("if a
    # creature died this turn", life a player lost this turn, how many times an ability resolved this
    # turn).
    #
    # Everything is recorded in one place, from the events the engine already emits, before
    # triggered abilities look at the event (so an intervening "if" sees it). A cast that is
    # cancelled never emits SpellCast, so it never counts (CR 601.2i: a spell becomes cast only
    # once casting is complete).
    #
    # Per player (PlayerState#turn_log, reset as each turn begins; #game_log for the whole game):
    #   "spells"   card ids of spells the player cast       "life_gained" / "life_lost"  totals
    #   "entered"  [card id, types, subtypes] of permanents that entered under their control
    #   "died"     [card id, types] of their permanents put into a graveyard from the battlefield
    #   "returned" permanents returned to their hand from the battlefield
    #   "dilemmas" dilemmas they faced (CR 700.17)
    # Per object (GameObject#memory, stamped with the turn): "attacked" and "resolved" counts.
    module TurnHistory
      def record_history!(event)
        case event
        when Events::TurnBegan then state.players.each { it.turn_log = {} }
        when Events::SpellCast then cast_recorded!(event)
        when Events::LifeChanged then life_recorded!(event)
        when Events::ZoneChanged
          zone_change_recorded!(event)
          discard_recorded!(event) # mayhem (Engine::AltCasting)
        when Events::DilemmaFaced then bump!(log_of(event.player), "dilemmas", 1)
        when Events::AttackerDeclared then object_memory!(event.object, "attacked")["count"] = 1
        when Events::Resolved then resolution_recorded!(event)
        end
      end

      # This turn's log of the player at `index`.
      def turn_log(index) = player(index).turn_log ||= {}

      # This game's log of the player at `index`.
      def game_log(index) = player(index).game_log ||= {}

      # How many times this turn the ability `ref` of `source` has finished resolving (CR 608.2).
      def times_resolved(source, ref)
        memory = turned_memory(state.objects[source], "resolved")
        memory ? memory.fetch(ref, 0) : 0
      end

      # Whether the permanent attacked this turn (CR 508.1).
      def attacked_this_turn?(id) = !turned_memory(state.objects[id], "attacked").nil?

      # CR 608.2h: a permanent leaving the battlefield is remembered as it last existed by the abilities it
      # is the source of (on the stack, being activated or waiting to be put on the stack: "source_lki" in
      # their memory) and by the spell or ability resolving now ("its controller" of a destroyed target).
      def remember_last_known!(id, lki)
        info = { "controller" => lki["controller"], "power" => lki["power"], "toughness" => lki["toughness"],
                 "counters" => lki["counters"].dup, "card" => lki["card"] }
        info["except"] = lki["except"] if lki["except"] # what a copy of it copies (CR 707.2, Engine::Copies)
        state.stack.each do |sid|
          obj = object(sid)
          obj.memory["source_lki"] = info.dup if obj.ability? && obj.source == id
        end
        state.pending_triggers.each { (it["memory"] ||= {})["source_lki"] = info.dup if it["source"] == id }
        resolving = state.frames.rfind { it["type"] == "resolve" && it["ctx"] }
        (resolving["ctx"]["lki"] ||= {})[id] = info if resolving
      end

      # What the resolving spell or ability remembers about an object that left the battlefield during it.
      def resolving_last_known(id) = state.frames.rfind { it["type"] == "resolve" && it["ctx"] }&.dig("ctx", "lki", id)

      private

      def log_of(player_name) = turn_log(names.index(player_name))

      def bump!(log, key, amount) = log[key] = log.fetch(key, 0) + amount

      def cast_recorded!(event)
        index = names.index(event.player)
        (turn_log(index)["spells"] ||= []) << event.card
        bump!(game_log(index), "spells", 1)
      end

      def life_recorded!(event)
        log = log_of(event.player)
        bump!(log, "life_gained", event.gain) if event.gain.positive? # CR 119.9
        bump!(log, "life_lost", event.loss) if event.loss.positive?
      end

      # CR 700.4: "dies" is battlefield to graveyard; the types are those it last had (CR 603.10a).
      def zone_change_recorded!(event)
        if event.to == "battlefield"
          obj = state.objects[event.new_id] or return
          c = chars(obj)
          (turn_log(obj.controller)["entered"] ||= []) << [event.card, c.types.map(&:to_s), c.subtypes.map(&:to_s)]
        elsif event.from == "battlefield"
          lki = last_known(event.old_id) or return
          if event.to == "graveyard"
            (turn_log(lki["controller"])["died"] ||= []) << [event.card, lki["types"].map(&:to_s)]
          elsif event.to == "hand"
            bump!(log_of(event.owner), "returned", 1)
          end
        end
      end

      def resolution_recorded!(event)
        obj = state.objects[event.object]
        return unless obj&.ability? && state.objects.key?(obj.source)

        memory = object_memory!(obj.source, "resolved")
        memory[obj.ability] = memory.fetch(obj.ability, 0) + 1
      end

      # A memory entry of the object that holds only this turn's data.
      def object_memory!(id, key)
        memory = state.objects.fetch(id).memory
        entry = memory[key]
        entry = memory[key] = { "turn" => state.turn } unless entry.is_a?(Hash) && entry["turn"] == state.turn
        entry
      end

      def turned_memory(obj, key)
        entry = obj&.memory&.[](key)
        entry if entry.is_a?(Hash) && entry["turn"] == state.turn
      end
    end
    include TurnHistory
  end
end
