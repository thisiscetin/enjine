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
      def self.decisions = %w[choose_kicker choose_mode choose_x choose_target_count choose_target distribute choose_cost pay_cost]

      def self.validate(frame, data, errors)
        errors << "frames: cast object #{frame["object"]} is not on the stack" unless data["stack"].include?(frame["object"])
      end
    end
    register("cast", Cast)

    # Resolving the top object of the stack, one effect at a time (CR 608).
    class Resolve < Base
      def self.step(engine, frame) = engine.step_resolution!(frame)
      def self.decisions = %w[effect_choice enter_choice]

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

    # Putting pending triggered abilities on the stack (CR 603.3), then giving priority.
    class PutTriggers < Base
      def self.step(engine, frame) = engine.step_put_triggers!(frame)
      def self.decisions = %w[order_triggers]
    end
    register("put_triggers", PutTriggers)

    # The legend rule's choice (CR 704.5j).
    class LegendRule < Base
      def self.step(engine, frame) = engine.step_legend_rule!(frame)
      def self.decisions = %w[legend_rule]
    end
    register("legend_rule", LegendRule)

    # Playing a land that asks an "as this enters" choice first (CR 614.12).
    class PlayLand < Base
      def self.step(engine, frame) = Actions::PlayLand.step(engine, frame)
      def self.decisions = %w[enter_choice]
    end
    register("play_land", PlayLand)
  end
end
