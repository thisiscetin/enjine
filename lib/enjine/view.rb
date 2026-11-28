# frozen_string_literal: true

module Enjine
  # Builds what a viewer may see of a game. A viewer is a player name or :observer.
  #
  # A player sees public zones, their own hand, and counts of hidden zones.
  # The observer sees everything, including both hands and library order.
  module View
    module_function

    # `options`: something callable returning the pending decision's legal options when the caller already has them
    # (Game#view_for passes its memoized decision's), so a view doesn't generate them all again; computed here otherwise.
    # Called only for a view that shows the options.
    def build(engine, viewer, options: nil)
      state = engine.state
      observer = viewer == :observer
      {
        "viewer" => observer ? "observer" : viewer,
        "turn" => state.turn,
        "active" => state.active && engine.name(state.active),
        "step" => state.step&.to_s,
        "phase" => state.step && Steps.fetch(state.step).phase.to_s,
        "priority" => state.priority && engine.name(state.priority),
        "players" => state.players.map { |pl| player_view(engine, pl, observer || pl.name == viewer, observer) },
        "battlefield" => state.battlefield.map { board_view(engine, it, viewer) },
        "stack" => state.stack.map { board_view(engine, it, viewer) },
        "exile" => state.exile.map { exiled_view(engine, it, viewer) },
        "phased_out" => state.phased_out.map { board_view(engine, it, viewer) },
        "command" => state.command.map { command_view(engine, it) },
        "pending" => pending_view(engine, viewer, options),
        "result" => state.result&.dup,
        "effects" => state.effects.map { it.except("controller").merge("controller" => engine.name(it["controller"])) },
        "delayed_triggers" => state.delayed_triggers.map { delayed_view(engine, it) }
      }
    end

    # What is in the command zone, all public: emblems (CR 114) and commanders (CR 903.6).
    def command_view(engine, id)
      engine.object(id).kind == "emblem" ? emblem_view(engine, engine.object(id)) : object_view(engine, id)
    end

    # An emblem in the command zone (CR 114): public, with its owner and abilities.
    def emblem_view(engine, obj)
      { "id" => obj.id, "kind" => "emblem", "owner" => engine.name(obj.owner),
        "abilities" => engine.chars(obj).abilities.map { it.ability.to_s } }
    end

    # A delayed triggered ability waiting for its event (CR 603.7): public, like the spell that made it.
    def delayed_view(engine, entry)
      defn = engine.catalog.fetch(entry["card"])
      { "controller" => engine.name(entry["controller"]), "card" => defn.name, "ability" => defn.ability(entry["ability"]).to_s }
    end

    # How a mana kept apart in the pool may be spent and how long it stays (CR 106.6, 702.189a).
    def pool_entry_text(entry)
      parts = [entry["spend_only"] && Mechanics::SpendOnly.from_data(entry["spend_only"]).to_s,
               entry["until"] && "you don't lose this mana until end of combat"]
      parts.compact.join("; ")
    end

    def player_view(engine, player, sees_hand, sees_library)
      view = {
        "name" => player.name, "life" => player.life, "poison" => player.poison,
        "mana_pool" => player.mana_pool.reject { |_, n| n.zero? }.transform_keys(&:to_s),
        "restricted_mana" => player.restricted_mana.map { it.merge("text" => View.pool_entry_text(it)) },
        "lands_played" => player.lands_played, "mulligans" => player.mulligans,
        "hand_count" => player.hand.size, "library_count" => player.library.size, "outside_count" => player.outside.size,
        "graveyard" => player.graveyard.map { object_view(engine, it) }
      }
      view.merge!(public_extras(player))
      view.merge!(commander_view(engine, engine.state.players.index(player)))
      view["hand"] = player.hand.map { object_view(engine, it) } if sees_hand
      view["outside"] = outside_view(engine, player) if sees_hand # CR 400.11a: only its owner knows their sideboard
      view["library"] = player.library.map { object_view(engine, it) } if sees_library
      view["library_top"] = object_view(engine, player.library.first) if sees_hand && looks_at_top?(engine, player)
      view
    end

    # Public player state present only when there is some: speed (CR 702.179), designations (CR 702.195b), player
    # counters other than poison (CR 122.1) and the artifact sources of pool mana (Engine::ManaSources#add_mana!).
    def public_extras(player)
      { "speed" => player.speed, "designations" => player.designations&.dup, "counters" => player.counters&.dup,
        "pool_sources" => Snapshot.deep_copy(player.pool_sources) }.reject { |_, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
    end

    # A Commander game's public facts about a player (CR 903): their commander, what it would cost to cast from
    # the command zone (CR 903.8) and the combat damage each commander has dealt them (CR 903.10a).
    def commander_view(engine, index)
      card = engine.state.commanders[index]
      return {} unless card

      damage = engine.player(index).commander_damage || {}
      { "commander" => engine.catalog.fetch(card).name, "commander_tax" => engine.commander_tax(index),
        "commander_damage" => damage.to_h { |id, n| [engine.catalog.fetch(id).name, n] } }
    end

    # The cards a player owns outside the game (CR 400.11a): not objects, so no ids (CR 400.11).
    def outside_view(engine, player)
      player.outside.map do |card|
        defn = engine.catalog.fetch(card)
        { "card" => card, "name" => defn.name, "type_line" => defn.type_line, "mana_cost" => defn.mana_cost_text }.compact
      end
    end

    # CR 401.5: an effect letting a player look at the top card of their library shows it to that player only.
    def looks_at_top?(engine, player)
      !player.library.empty? && engine.may_look_at_top?(engine.state.players.index(player))
    end

    # CR 406.3: a card exiled face down shows only that it's face down, except to an observer and to the
    # players who may look at it.
    def exiled_view(engine, id, viewer)
      obj = engine.object(id)
      return object_view(engine, id) unless engine.face_down?(obj)

      hidden = { "id" => id, "face_down" => true, "owner" => engine.name(obj.owner) }
      looks = viewer == :observer || ((index = engine.names.index(viewer)) && engine.may_look?(obj, index))
      looks ? object_view(engine, id).merge(hidden) : hidden
    end

    # A spell or permanent. A face-down one (CR 708) shows its face-down characteristics to everyone; only its
    # controller (CR 708.5) and an observer also see which card it is.
    def board_view(engine, id, viewer)
      view = object_view(engine, id)
      obj = engine.object(id)
      return view unless !obj.ability? && engine.face_down_object?(obj)

      view["face_down"] = true
      index = engine.names.index(viewer)
      return view unless viewer == :observer || (index && engine.sees_face_down?(obj, index))

      card = obj.memory["face_down_card"]
      view.merge("face_down_card" => card, "face_down_name" => engine.catalog.fetch(card).name)
    end

    def object_view(engine, id)
      obj = engine.object(id)
      defn = engine.definition(obj)
      return ability_view(engine, obj, defn) if obj.ability?

      view = { "id" => id, "card" => obj.card, "name" => defn.name, "type_line" => defn.type_line,
               "owner" => engine.name(obj.owner) }
      view["mana_cost"] = defn.mana_cost_text if defn.mana_cost
      view["keywords"] = defn.keywords.map(&:name) unless defn.keywords.empty?
      view["rules_text"] = defn.rules_text if defn.rules_text
      case obj.zone
      when :battlefield then permanent_view(engine, obj, defn, view)
      when :stack then view.merge!("controller" => engine.name(obj.controller), "targets" => (obj.targets || []).flatten)
      when :phased_out # public: still on the battlefield, treated as though it doesn't exist (CR 702.26b)
        view.merge!("controller" => engine.name(obj.controller), "tapped" => obj.tapped, "phased_out" => true)
        view["attached_to"] = obj.attached_to if obj.attached_to
      end
      view
    end

    # A planeswalker's loyalty; a battle's defense and protector (CR 306.5b, 310.4c, 310.9).
    def loyalty_and_defense(engine, obj, defn, view)
      view["loyalty"] = engine.loyalty(obj) if defn.planeswalker?
      return unless defn.type?(:battle)

      view["defense"] = obj.counters.fetch("defense", 0)
      view["protector"] = engine.name(engine.protector(obj)) if engine.protector(obj)
    end

    def permanent_view(engine, obj, defn, view)
      view["controller"] = engine.name(obj.controller)
      view["tapped"] = obj.tapped
      view["name"] = engine.chars(obj).name # "named Humble Merchant" (CR 612.8)
      keywords = engine.chars(obj).keywords # printed plus granted (CR 613.1f), minus removed
      keywords.empty? ? view.delete("keywords") : view["keywords"] = keywords.map(&:to_s)
      if engine.chars(obj).creature? # e.g. a Spacecraft with enough charge counters (CR 722.2b)
        power, toughness = engine.power_toughness(obj)
        view.merge!("power" => power, "toughness" => toughness, "damage" => obj.damage,
                    "summoning_sick" => engine.summoning_sick_for_tap?(obj))
      end
      loyalty_and_defense(engine, obj, defn, view)
      view["counters"] = obj.counters.reject { |_, n| n.zero? } unless obj.counters.values.all?(&:zero?)
      view["attached_to"] = obj.attached_to if obj.attached_to
      designations_view(engine, obj, view)
      if (attack = engine.attackers[obj.id])
        view["attacking"] = attack["target"]
      end
      view["blocking"] = engine.state.blockers[obj.id] if engine.state.blockers.key?(obj.id)
    end

    # A permanent's status: transformed, prepared, its designations (solved, CR 720.3b; harnessed, CR 701.64b) and a
    # Room's unlocked doors (CR 709.5c).
    def designations_view(engine, obj, view)
      view["transformed"] = true if engine.transformed?(obj) # CR 701.27h
      view["prepared"] = true if engine.prepared?(obj) # CR 723.3a
      marks = engine.permanent_designations(obj)
      view["designations"] = marks unless marks.empty?
      view["unlocked"] = engine.unlocked_doors(obj) if engine.room?(obj)
    end

    def ability_view(engine, obj, defn)
      ability = defn.ability(obj.ability)
      { "id" => obj.id, "card" => obj.card, "name" => "#{defn.name} ability", "kind" => "ability",
        "ability" => obj.ability, "loyalty_cost" => ability.loyalty_cost, "source" => obj.source,
        "controller" => engine.name(obj.controller), "targets" => (obj.targets || []).flatten }.compact
    end

    def pending_view(engine, viewer, options = nil)
      pending = engine.state.pending
      return nil unless pending

      decider = engine.name(pending["player"])
      view = pending.merge("player" => decider)
      return view.except("choices") unless viewer == :observer || viewer == decider # e.g. the cards a search sees

      view["options"] = (options ? options.call : engine.options).map { it.transform_keys(&:to_s) }
      view
    end
  end
end
