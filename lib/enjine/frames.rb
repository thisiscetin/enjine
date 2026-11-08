# frozen_string_literal: true

module Enjine
  # In-progress processes, kept on a serializable stack (state.frames, innermost last).
  #
  # Anything that may need to stop and ask a player something in the middle of the
  # rules (casting, resolving a spell, assigning combat damage, ...) is a frame:
  # plain JSON data plus a registered frame class. Engine#advance! steps the top
  # frame until it is done or waiting for a decision, so a game can be exported at
  # any point, including halfway through resolving an effect list.
  #
  # A frame class implements:
  #   .step(engine, frame) -> :done (pop it), :wait (state.pending is set), or :push (stepped child next)
  #   .decisions           -> decision kinds that may be pending while it is on top
  #   .validate(frame, data, errors) -> snapshot consistency checks
  module Frames
    KINDS = {} # rubocop:disable Style/MutableConstant -- extension registry

    def self.register(type, klass)
      KINDS[type] = klass
    end

    def self.fetch(type) = KINDS.fetch(type) { raise ArgumentError, "unknown frame type #{type.inspect}" }

    # Base frame.
    class Base
      def self.decisions = []
      def self.validate(_frame, _data, _errors) = nil
    end

    # Casting a spell or activating an ability (CR 601.2, 602.2).
    class Cast < Base
      def self.step(engine, _frame) = engine.continue_casting!
      def self.decisions = %w[choose_target pay_cost]

      def self.validate(frame, data, errors)
        errors << "frames: cast object #{frame["object"]} is not on the stack" unless data["stack"].include?(frame["object"])
      end
    end
    register("cast", Cast)

    # Resolving the top object of the stack, one effect at a time (CR 608).
    class Resolve < Base
      def self.step(engine, frame) = engine.step_resolution!(frame)

      def self.validate(frame, data, errors)
        errors << "frames: resolving object #{frame["object"]} is not on the stack" unless data["stack"].include?(frame["object"])
      end
    end
    register("resolve", Resolve)

    # Assigning and dealing combat damage (CR 510).
    class CombatDamage < Base
      def self.step(engine, frame) = engine.step_combat_damage!(frame)
      def self.decisions = %w[assign_damage]
    end
    register("combat_damage", CombatDamage)
  end
end
