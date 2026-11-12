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
    # Per player (PlayerState#turn_log, reset as each turn begins and kept as #last_turn_log for the turn after;
    # #game_log for the whole game):
    #   "spells"   card ids of spells the player cast       "life_gained" / "life_lost"  totals
    #   "spells_from"  the zone each of those spells was cast from (CR 601.2a), in the same order
    #   "lands_played" [card id, zone it was played from] of the lands the player played (CR 305.1)
    #   "entered"  [card id, types, subtypes] of permanents that entered under their control
    #   "died"     [card id, types] of their permanents put into a graveyard from the battlefield
    #   "left"     [card id, types, subtypes] of their permanents that left the battlefield (CR 400.7)
    #   "sacrificed" [card id, types, subtypes] of the permanents they sacrificed (CR 701.21a)
    #   "attackers" [card id, types, subtypes] of the creatures they attacked with (CR 508.1)
    #   "exiled"   [card id, types] of their cards put into exile, from anywhere (as it last existed)
    #   "returned" permanents returned to their hand from the battlefield
    #   "drawn" / "discarded"  how many cards they drew (CR 121.2) / discarded (CR 701.9a)
    #   "dilemmas" dilemmas they faced (CR 700.17)
    #   "noncombat_damage"  noncombat damage dealt to them (CR 120.2b)
    #   "coin_flips"  coins they flipped (CR 705)
    # The game log also counts the turns each player has begun ("turns").
    # Per object (GameObject#memory, stamped with the turn): "attacked" and "resolved" counts.
    module TurnHistory
      def record_history!(event)
        case event
        when Events::TurnBegan
          turn_logs_rolled!
          bump!(game_log(names.index(event.active)), "turns", 1) # "your third turn of the game"
        when Events::SpellCast then cast_recorded!(event)
        when Events::LifeChanged then life_recorded!(event)
        when Events::ZoneChanged
          zone_change_recorded!(event)
          discard_recorded!(event) # mayhem (Engine::AltCasting)
        when Events::DilemmaFaced then bump!(log_of(event.player), "dilemmas", 1)
        when Events::AttackerDeclared then attack_recorded!(event)
        when Events::AttacksDeclared # the attacking creatures' total power, per combat (Triggers::PlayerAttacks)
          (log_of(event.player)["attack_powers"] ||= []) << event.attackers.sum { power(object(it)) }
        when Events::Resolved then resolution_recorded!(event)
        when Events::DamageDealt then damage_recorded!(event)
        when Events::CoinFlipped then bump!(log_of(event.player), "coin_flips", 1) # CR 705.3 (Abilities::FirstFlipsWin)
        end
      end

      # This turn's log of the player at `index`.
      def turn_log(index) = player(index).turn_log ||= {}

      # The previous turn's log of the player at `index` ("last turn", CR 500.1: whoever's turn it was).
      def last_turn_log(index) = player(index).last_turn_log ||= {}

      # This game's log of the player at `index`.
      def game_log(index) = player(index).game_log ||= {}

      # How many times this turn the ability `ref` of `source` has finished resolving (CR 608.2).
      def times_resolved(source, ref)
        memory = turned_memory(state.objects[source], "resolved")
        memory ? memory.fetch(ref, 0) : 0
      end

      # Whether the permanent attacked this turn (CR 508.1).
      def attacked_this_turn?(id) = attacks_this_turn(id).positive?

      # How many times the permanent was declared as an attacker this turn ("for the first time each turn").
      def attacks_this_turn(id) = turned_memory(state.objects[id], "attacked")&.fetch("count", 0).to_i

      # An attack undone before the declaration was legal (CR 508.1c) never happened.
      def attack_withdrawn!(id)
        obj = state.objects[id]
        bump!(object_memory!(id, "attacked"), "count", -1)
        log = turn_log(obj.controller)["attackers"]
        log&.delete_at(log.rindex { it.first == obj.card } || log.size)
      end

      # Whether the permanent entered the battlefield this turn (memory "entered", stamped as it enters).
      def entered_this_turn?(obj) = obj.memory["entered"] == state.turn

      # CR 608.2h: a permanent leaving the battlefield is remembered as it last existed by the abilities it
      # is the source of (on the stack, being activated or waiting to be put on the stack: "source_lki" in
      # their memory) and by the spell or ability resolving now ("its controller" of a destroyed target).
      def remember_last_known!(id, lki)
        info = last_known_memory(lki)
        state.stack.each do |sid|
          obj = object(sid)
          obj.memory["source_lki"] = info.dup if obj.ability? && obj.source == id
        end
        state.pending_triggers.each { (it["memory"] ||= {})["source_lki"] = info.dup if it["source"] == id }
        resolving = state.frames.rfind { it["type"] == "resolve" && it["ctx"] }
        (resolving["ctx"]["lki"] ||= {})[id] = info if resolving
      end

      # A spell leaving the stack while a spell or ability resolves ("counter target spell. If the amount of mana
      # spent to cast that spell was less than its mana value, ..."): the resolving one remembers it as it last
      # existed on the stack (CR 608.2h): its controller, mana spent (CR 601.2h) and mana value, X included (CR 202.3e).
      def remember_spell!(obj)
        resolving = state.frames.rfind { it["type"] == "resolve" && it["ctx"] } or return
        (resolving["ctx"]["lki"] ||= {})[obj.id] = { "controller" => obj.controller, "card" => obj.card,
                                                     "mana_spent" => obj.mana_spent&.dup, "mana_from" => obj.memory["mana_from"],
                                                     "mana_value" => Mechanics::Amount.mana_value(self, obj) }
      end

      # The part of last known information an ability keeps in its memory ("source_lki"): plain data.
      def last_known_memory(lki)
        info = { "controller" => lki["controller"], "power" => lki["power"], "toughness" => lki["toughness"],
                 "mana_value" => lki["mana_value"], "counters" => lki["counters"].dup, "card" => lki["card"],
                 "keywords" => lki["keywords"].dup }
        info["except"] = lki["except"] if lki["except"] # what a copy of it copies (CR 707.2, Engine::Copies)
        info.merge(lki.slice(Mechanics::Linked::EXILED).transform_values(&:dup)) # CR 607.2a (Linked.exiled_with)
      end

      # What the resolving spell or ability remembers about an object that left the battlefield during it.
      def resolving_last_known(id) = state.frames.rfind { it["type"] == "resolve" && it["ctx"] }&.dig("ctx", "lki", id)

      # A permanent that left the battlefield while a spell or ability resolves becomes a new object (CR 400.7);
      # the resolving one links the new object to the permanent it was, so "the sacrificed creature's power"
      # ({"power": {"result": n}}) is read as the permanent last existed (CR 608.2h).
      def remember_departed!(new_id, old_id)
        resolving = state.frames.rfind { it["type"] == "resolve" && it["ctx"] } or return
        (resolving["ctx"]["departed"] ||= {})[new_id] = old_id
      end

      # The last known information of the permanent a new object was, if it left the battlefield during the
      # resolving spell or ability.
      def departed_last_known(new_id)
        ctx = state.frames.rfind { it["type"] == "resolve" && it["ctx"] }&.fetch("ctx") or return nil
        (old_id = ctx.dig("departed", new_id)) && ctx.dig("lki", old_id)
      end

      # CR 702.171b: a permanent becomes saddled until the end of the turn; leaving the battlefield ends it (the
      # card is a new object, CR 400.7), and it isn't copiable (it lives on the object, not its characteristics).
      def saddle!(id) = object_memory!(id, "saddled")
      def saddled?(obj) = obj.zone == :battlefield && !turned_memory(obj, "saddled").nil?

      private

      def log_of(player_name) = turn_log(names.index(player_name))

      def turn_logs_rolled!
        state.players.each do |pl|
          pl.last_turn_log = pl.turn_log || {}
          pl.turn_log = {}
        end
      end

      def bump!(log, key, amount) = log[key] = log.fetch(key, 0) + amount

      def cast_recorded!(event)
        index = names.index(event.player)
        (turn_log(index)["spells"] ||= []) << event.card
        (turn_log(index)["spells_from"] ||= []) << ((spell = state.objects[event.object]) ? cast_origin(spell) : "hand")
        bump!(game_log(index), "spells", 1)
      end

      def life_recorded!(event)
        log = log_of(event.player)
        bump!(log, "life_gained", event.gain) if event.gain.positive? # CR 119.9
        bump!(log, "life_lost", event.loss) if event.loss.positive?
      end

      # CR 700.4: "dies" is battlefield to graveyard; the types are those it last had (CR 603.10a).
      # Who it counts for: a permanent's controller as it last existed, or a card's owner.
      def zone_change_recorded!(event)
        entered_recorded!(event) if event.to == "battlefield"
        land_play_recorded!(event) if event.reason == "play_land"
        lki = event.from == "battlefield" ? last_known(event.old_id) : nil
        departed_recorded!(event, lki) if lki
        log = lki ? turn_log(lki["controller"]) : log_of(event.owner)
        case event.reason
        when "draw" then bump!(log_of(event.owner), "drawn", 1)
        when "discard" then bump!(log_of(event.owner), "discarded", 1)
        end
        (log["exiled"] ||= []) << [event.card, (lki ? lki["types"] : printed_types(event.card)).map(&:to_s)] if event.to == "exile"
      end

      def entered_recorded!(event)
        obj = state.objects[event.new_id] or return
        (turn_log(obj.controller)["entered"] ||= []) << history_entry(event.card, chars(obj))
      end

      # CR 305.1: the player who plays a land controls it as it enters.
      def land_play_recorded!(event)
        index = state.objects[event.new_id]&.controller || names.index(event.owner)
        (turn_log(index)["lands_played"] ||= []) << [event.card, event.from]
      end

      def departed_recorded!(event, lki)
        log = turn_log(lki["controller"])
        left = [event.card, lki["types"].map(&:to_s), lki.fetch("subtypes", []).map(&:to_s)]
        (log["left"] ||= []) << left
        (log["died"] ||= []) << left.first(2) if event.to == "graveyard"
        (log["sacrificed"] ||= []) << left if event.reason == "sacrifice"
        bump!(log_of(event.owner), "returned", 1) if event.to == "hand"
      end

      # CR 508.1: "you attacked this turn" / "attacked with a Spacecraft"; the attacker remembers it attacked.
      def attack_recorded!(event)
        obj = state.objects[event.object] or return
        bump!(object_memory!(event.object, "attacked"), "count", 1)
        (turn_log(obj.controller)["attackers"] ||= []) << history_entry(obj.card, chars(obj))
      end

      def history_entry(card, current) = [card, current.types.map(&:to_s), current.subtypes.map(&:to_s)]
      def printed_types(card) = catalog.fetch(card).types

      def damage_recorded!(event)
        index = Mechanics::Filters.player_index(self, event.target)
        bump!(turn_log(index), "noncombat_damage", event.amount) if index && !event.combat
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

      # What a triggered ability remembers of its source: whether it was cast (CR 400.7d) and kicked (CR 702.33d),
      # how it was cast, the mana spent to cast it (CR 601.2h) and, for a source that just left the battlefield
      # ("when this leaves, put its counters on ..."), how it last existed (CR 603.10a, 608.2h).
      def trigger_memory(source)
        obj = state.objects[source["id"]]
        source_memory = obj&.memory || {}
        memory = source_memory["cast"] ? { "source_cast" => true } : {}
        memory["kicked"] = true if source_memory["kicked"] # CR 702.33d: a kicked permanent's "if it was kicked"
        memory.merge!(source_memory.slice("cast_from", "cast_with", "kicked_with")) # "if its evoke cost was paid" (Engine::AltCasting)
        memory["source_mana_spent"] = obj.mana_spent.dup if obj&.mana_spent
        memory["source_mana_from"] = Snapshot.deep_copy(source_memory["mana_from"]) if source_memory["mana_from"]
        lki = last_known(source["id"])
        memory["source_lki"] = last_known_memory(lki) if lki
        memory
      end
    end
    include TurnHistory
  end
end
