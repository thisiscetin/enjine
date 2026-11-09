# frozen_string_literal: true

module Enjine
  # Builds what a viewer may see of a game. A viewer is a player name or :observer.
  #
  # A player sees public zones, their own hand, and counts of hidden zones.
  # The observer sees everything, including both hands and library order.
  module View
    module_function

    def build(engine, viewer)
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
        "battlefield" => state.battlefield.map { object_view(engine, it) },
        "stack" => state.stack.map { object_view(engine, it) },
        "exile" => state.exile.map { exiled_view(engine, it, viewer) },
        "phased_out" => state.phased_out.map { object_view(engine, it) },
        "pending" => pending_view(engine, viewer),
        "result" => state.result&.dup,
        "effects" => state.effects.map { it.except("controller").merge("controller" => engine.name(it["controller"])) },
        "delayed_triggers" => state.delayed_triggers.map { delayed_view(engine, it) }
      }
    end

    # A delayed triggered ability waiting for its event (CR 603.7): public, like the spell that made it.
    def delayed_view(engine, entry)
      defn = engine.catalog.fetch(entry["card"])
      { "controller" => engine.name(entry["controller"]), "card" => defn.name, "ability" => defn.ability(entry["ability"]).to_s }
    end

    def player_view(engine, player, sees_hand, sees_library)
      view = {
        "name" => player.name, "life" => player.life, "poison" => player.poison,
        "mana_pool" => player.mana_pool.reject { |_, n| n.zero? }.transform_keys(&:to_s),
        "restricted_mana" => player.restricted_mana.map { it.merge("text" => Mechanics::SpendOnly.from_data(it["spend_only"]).to_s) },
        "lands_played" => player.lands_played, "mulligans" => player.mulligans,
        "hand_count" => player.hand.size, "library_count" => player.library.size, "outside_count" => player.outside.size,
        "graveyard" => player.graveyard.map { object_view(engine, it) }
      }
      view["hand"] = player.hand.map { object_view(engine, it) } if sees_hand
      view["outside"] = outside_view(engine, player) if sees_hand # CR 400.11a: only its owner knows their sideboard
      view["library"] = player.library.map { object_view(engine, it) } if sees_library
      view["library_top"] = object_view(engine, player.library.first) if sees_hand && looks_at_top?(engine, player)
      view
    end

    # The cards a player owns outside the game (CR 400.11a): not objects, so no ids (CR 400.11).
    def outside_view(engine, player)
      player.outside.map do |card|
        defn = engine.catalog.fetch(card)
        { "card" => card, "name" => defn.name, "type_line" => defn.type_line, "mana_cost" => defn.mana_cost&.to_s }.compact
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
      looks = viewer == :observer || obj.memory.fetch("may_look", []).map { engine.name(it) }.include?(viewer)
      looks ? object_view(engine, id).merge(hidden) : hidden
    end

    def object_view(engine, id)
      obj = engine.object(id)
      defn = engine.definition(obj)
      return ability_view(engine, obj, defn) if obj.ability?

      view = { "id" => id, "card" => obj.card, "name" => defn.name, "type_line" => defn.type_line,
               "owner" => engine.name(obj.owner) }
      view["mana_cost"] = defn.mana_cost.to_s if defn.mana_cost
      view["keywords"] = defn.keywords.map(&:to_s) unless defn.keywords.empty?
      view["rules_text"] = defn.rules_text if defn.rules_text
      case obj.zone
      when :battlefield then permanent_view(engine, obj, defn, view)
      when :stack then view.merge!("controller" => engine.name(obj.controller), "targets" => obj.targets || [])
      when :phased_out # public: still on the battlefield, treated as though it doesn't exist (CR 702.26b)
        view.merge!("controller" => engine.name(obj.controller), "tapped" => obj.tapped, "phased_out" => true)
        view["attached_to"] = obj.attached_to if obj.attached_to
      end
      view
    end

    def permanent_view(engine, obj, defn, view)
      view["controller"] = engine.name(obj.controller)
      view["tapped"] = obj.tapped
      if engine.chars(obj).creature? # e.g. a Spacecraft with enough charge counters (CR 722.2b)
        power, toughness = engine.power_toughness(obj)
        view.merge!("power" => power, "toughness" => toughness, "damage" => obj.damage,
                    "summoning_sick" => engine.summoning_sick_for_tap?(obj))
      end
      view["loyalty"] = engine.loyalty(obj) if defn.planeswalker?
      view["counters"] = obj.counters.reject { |_, n| n.zero? } unless obj.counters.values.all?(&:zero?)
      view["attached_to"] = obj.attached_to if obj.attached_to
      if (attack = engine.attackers[obj.id])
        view["attacking"] = attack["target"]
      end
      view["blocking"] = engine.state.blockers[obj.id] if engine.state.blockers.key?(obj.id)
    end

    def ability_view(engine, obj, defn)
      ability = defn.ability(obj.ability)
      { "id" => obj.id, "card" => obj.card, "name" => "#{defn.name} ability", "kind" => "ability",
        "ability" => obj.ability, "loyalty_cost" => ability.loyalty_cost, "source" => obj.source,
        "controller" => engine.name(obj.controller), "targets" => obj.targets || [] }.compact
    end

    def pending_view(engine, viewer)
      pending = engine.state.pending
      return nil unless pending

      decider = engine.name(pending["player"])
      view = pending.merge("player" => decider)
      return view.except("choices") unless viewer == :observer || viewer == decider # e.g. the cards a search sees

      view["options"] = engine.options.map { it.transform_keys(&:to_s) }
      view
    end
  end
end
