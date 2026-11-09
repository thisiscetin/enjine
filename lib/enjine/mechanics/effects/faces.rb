# frozen_string_literal: true

require_relative "../triggers/triggers"

module Enjine
  module Mechanics
    module Effects
      # Transform permanents (CR 701.27): turn each referenced double-faced permanent over (see
      # Engine::Faces#transform!).
      class Transform < Effect
        primitive :effect, :transform,
                  description: "Transform each referenced permanent (default: this one): turn it over so its other " \
                               "face is up. It stays the same object, and effects on it keep applying. Nothing " \
                               "happens to a permanent that isn't a double-faced card or token, or whose other face " \
                               "is an instant or sorcery. An ability of the permanent transforms it only if it hasn't " \
                               "transformed since the ability was put on the stack.",
                  rules: %w[701.27a 701.27c 701.27d 701.27e 701.27g 712.15],
                  params: { "to" => "selector (default \"self\")" },
                  example: { "transform" => { "to" => "self" } }

        def self.keys = %w[to if]
        def self.default_to = "self"

        def apply(engine, ctx)
          objects(engine, ctx).each do |id|
            obj = engine.object(id)
            engine.transform!(obj) if engine.transform_still_allowed?(obj, ctx)
          end
        end
      end

      # The prepared designation (CR 723.3a-b).
      class Prepare < Effect
        primitive :effect, :prepare,
                  description: "Each referenced permanent (default: this one) becomes prepared, if it has a prepare " \
                               "spell and isn't prepared already: its controller creates a copy of the prepare spell " \
                               "in exile and may cast that copy while the permanent stays prepared. Casting it " \
                               "unprepares the permanent.",
                  rules: %w[723.3a 723.3c],
                  params: { "to" => "selector (default \"self\")" },
                  example: { "prepare" => { "to" => "self" } }

        def self.keys = %w[to if]
        def self.default_to = "self"

        def apply(engine, ctx) = objects(engine, ctx).each { engine.prepare!(engine.object(it)) }
      end

      # CR 723.3b: "becomes unprepared".
      class Unprepare < Effect
        primitive :effect, :unprepare,
                  description: "Each referenced permanent (default: this one) loses the prepared designation; the " \
                               "copy of its prepare spell in exile ceases to exist.",
                  rules: %w[723.3b 723.3c],
                  params: { "to" => "selector (default \"self\")" },
                  example: { "unprepare" => { "to" => "self" } }

        def self.keys = %w[to if]
        def self.default_to = "self"

        def apply(engine, ctx) = objects(engine, ctx).each { engine.unprepare!(engine.object(it)) }
      end
    end

    module Abilities
      # "This creature enters prepared." (CR 723.3a): a self-replacement effect on its own entering.
      class EntersPrepared < Primitive
        primitive :ability, :enters_prepared,
                  description: "This permanent enters the battlefield prepared (it needs a prepare spell, see " \
                               "`layout: \"prepare\"`).",
                  rules: %w[723.3a 614.1c],
                  example: "enters_prepared"

        INSTANCE = new.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          INSTANCE
        end

        def kind = :enters_prepared
        def mana_ability? = false
        def allowed_types = nil
        def to_s = "enters prepared"
        def try_effects = []

        def validate_definition(defn, errors, path)
          errors << "#{path}: only a card with a prepare spell (layout \"prepare\") enters prepared" unless defn.layout == "prepare"
        end

        def modify_entering(enters) = enters["prepared"] = true
      end
    end

    module Triggers
      # "Whenever this creature transforms into [this face]" (CR 701.27f): a self trigger is an ability of the
      # face it transformed into, so it triggers only on transforming into that face.
      class Transforms < Trigger
        primitive :trigger, :transforms,
                  description: "The subject transforms. For the default subject (this permanent), the ability is on " \
                               "the face that's up afterward, so it means \"whenever this transforms into [this face]\".",
                  rules: %w[701.27f 603.2],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}" },
                  example: { "transforms" => {} }

        def event_class = Events::Transformed

        def match?(engine, event, source)
          obj = engine.state.objects[event.object] or return false
          @subject.match?(engine, event.object, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        def to_s = "whenever #{@subject} transforms"
      end
    end
  end
end
