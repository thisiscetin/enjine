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
        "result" => state.result&.dup
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
      view = { "id" => id, "card" => obj.card, "name" => defn.name, "type_line" => defn.type_line,
               "owner" => engine.name(obj.owner) }
      view["mana_cost"] = defn.mana_cost.to_s if defn.mana_cost
      if obj.zone == :battlefield
        view["controller"] = engine.name(obj.controller)
        view["tapped"] = obj.tapped
      end
      view
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
