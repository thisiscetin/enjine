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
        "exile" => state.exile.map { object_view(engine, it) },
        "pending" => pending_view(engine, viewer),
        "result" => state.result&.dup,
        "effects" => state.effects.map { it.except("controller").merge("controller" => engine.name(it["controller"])) }
      }
    end

    def player_view(engine, player, sees_hand, sees_library)
      view = {
        "name" => player.name, "life" => player.life, "poison" => player.poison,
        "mana_pool" => player.mana_pool.reject { |_, n| n.zero? }.transform_keys(&:to_s),
        "lands_played" => player.lands_played, "mulligans" => player.mulligans,
        "hand_count" => player.hand.size, "library_count" => player.library.size,
        "graveyard" => player.graveyard.map { object_view(engine, it) }
      }
      view["hand"] = player.hand.map { object_view(engine, it) } if sees_hand
      view["library"] = player.library.map { object_view(engine, it) } if sees_library
      view
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
      view["options"] = engine.options.map { it.transform_keys(&:to_s) } if viewer == :observer || viewer == decider
      view
    end
  end
end
