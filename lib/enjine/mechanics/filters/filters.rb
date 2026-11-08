# frozen_string_literal: true

module Enjine
  module Mechanics
    # Target filters (CR 115) and "each" selectors. A filter lists candidate
    # references in a deterministic order: players (seat order), then battlefield
    # order, then stack order (top first). References are object ids or "player:<name>".
    module Filters
      PLAYER_PREFIX = "player:"

      def self.player_ref(engine, index) = "#{PLAYER_PREFIX}#{engine.name(index)}"

      def self.player_index(engine, ref)
        return nil unless ref.is_a?(String) && ref.start_with?(PLAYER_PREFIX)

        engine.names.index(ref.delete_prefix(PLAYER_PREFIX))
      end

      # Base filter: subclasses define players? and match_object?.
      class Filter < Primitive
        def self.players?(_engine, _index, _controller) = false
        def self.match_object?(_engine, _object, _controller) = false
        def self.zone = :battlefield

        def self.candidates(engine, controller)
          players = engine.state.players.each_index.select { players?(engine, it, controller) }
                          .map { Filters.player_ref(engine, it) }
          objects = engine.state.public_send(zone).select { |id| match_object?(engine, engine.object(id), controller) }
          players + objects
        end

        def self.match?(engine, ref, controller)
          index = Filters.player_index(engine, ref)
          return players?(engine, index, controller) if index
          return false unless engine.state.objects.key?(ref)

          obj = engine.object(ref)
          obj.zone == zone && match_object?(engine, obj, controller)
        end

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          self
        end

        def self.type?(engine, object, type) = object.kind == "card" && engine.chars(object).type?(type)
      end

      # A creature on the battlefield.
      class Creature < Filter
        primitive :filter, :creature, description: "A creature on the battlefield.", rules: %w[115.1], example: "creature"
        def self.match_object?(engine, object, _controller) = type?(engine, object, :creature)
      end

      # A planeswalker on the battlefield.
      class Planeswalker < Filter
        primitive :filter, :planeswalker, description: "A planeswalker on the battlefield.", rules: %w[115.1],
                                          example: "planeswalker"
        def self.match_object?(engine, object, _controller) = type?(engine, object, :planeswalker)
      end

      # A creature or planeswalker on the battlefield.
      class CreatureOrPlaneswalker < Filter
        primitive :filter, :creature_or_planeswalker, description: "A creature or planeswalker on the battlefield.",
                                                      rules: %w[115.1], example: "creature_or_planeswalker"
        def self.match_object?(engine, object, _controller)
          type?(engine, object, :creature) || type?(engine, object, :planeswalker)
        end
      end

      # Any permanent.
      class Permanent < Filter
        primitive :filter, :permanent, description: "Any permanent on the battlefield.", rules: %w[110.1],
                                       example: "permanent"
        def self.match_object?(_engine, _object, _controller) = true
      end

      # A player.
      class Player < Filter
        primitive :filter, :player, description: "A player.", rules: %w[115.1], example: "player"
        def self.players?(_engine, index, _controller) = !index.nil?
      end

      # An opponent of the controller.
      class Opponent < Filter
        primitive :filter, :opponent, description: "An opponent of the ability's controller.", rules: %w[102.2],
                                      example: "opponent"
        def self.players?(_engine, index, controller) = !index.nil? && index != controller
      end

      # "Any target": a creature, player or planeswalker (CR 115.4).
      class AnyTarget < Filter
        primitive :filter, :any_target, description: "A creature, player or planeswalker (battles: later).",
                                        rules: %w[115.4], example: "any_target"
        def self.players?(_engine, index, _controller) = !index.nil?
        def self.match_object?(engine, object, controller) = CreatureOrPlaneswalker.match_object?(engine, object, controller)
      end

      # A spell on the stack.
      class Spell < Filter
        primitive :filter, :spell, description: "A spell on the stack.", rules: %w[112.1 115.1], example: "spell"
        def self.zone = :stack
        def self.match_object?(_engine, object, _controller) = object.kind == "card"
      end
    end
  end
end
