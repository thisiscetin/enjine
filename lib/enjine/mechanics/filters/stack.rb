# frozen_string_literal: true

module Enjine
  module Mechanics
    module Filters
      # A spell on the stack.
      class Spell < Filter
        primitive :filter, :spell, description: "A spell on the stack.", rules: %w[112.1 115.1], example: "spell"
        def self.zone = :stack
        def self.match_object?(_engine, object, _controller) = object.kind == "card"
      end

      # An activated or triggered ability on the stack (CR 113.1b, 115.1): "counter target activated or
      # triggered ability", "copy target triggered ability you control from a creature source". Mana
      # abilities never use the stack (CR 605.3b), so they can't be targeted.
      class StackAbility < Filter
        KINDS = %w[activated triggered].freeze
        CONTROLLERS = %w[you opponent].freeze

        primitive :filter, :stack_ability,
                  description: "An activated or triggered ability on the stack. `kind`: \"activated\" or \"triggered\" " \
                               "for only one of them; `controller`: you | opponent; `source`: a filter its source " \
                               "matches (e.g. \"creature\", \"artifact\").",
                  rules: %w[113.1b 115.1 605.3b 113.7],
                  params: { "kind" => KINDS.join(" | "), "controller" => CONTROLLERS.join(" | "), "source" => "filter" },
                  example: { "stack_ability" => { "controller" => "you", "source" => "creature" } }

        def self.zone = :stack
        def self.match_object?(_engine, object, _controller) = object.ability?

        def self.build(params, errors, path, **)
          return self if params.empty?

          Mechanics.check_keys(params, %w[kind controller source], errors, path)
          kind, controller, source = params.values_at("kind", "controller", "source")
          errors << "#{path}.kind: must be one of #{KINDS.join(", ")}" unless kind.nil? || KINDS.include?(kind)
          unless controller.nil? || CONTROLLERS.include?(controller)
            errors << "#{path}.controller: must be one of #{CONTROLLERS.join(", ")}"
          end
          source &&= Mechanics.build_entry(:filter, source, errors, "#{path}.source")
          Narrowed.new(kind, controller, source)
        end

        # Only activated (loyalty included) or only triggered abilities, of a controller, from a kind of source.
        class Narrowed
          def initialize(kind, controller, source)
            @kind = kind
            @controller = controller
            @source = source
            freeze
          end

          def primitive_name = "stack_ability"

          def to_s
            whose = { "you" => " you control", "opponent" => " an opponent controls" }[@controller]
            "#{@kind || "activated or triggered"} ability#{whose}#{" from a source: #{Triggers.filter_words(@source)}" if @source}"
          end

          def candidates(engine, controller) = StackAbility.candidates(engine, controller).select { narrow?(engine, it, controller) }

          def candidates_for(engine, controller, _source, **) = candidates(engine, controller)

          def match?(engine, ref, controller) = StackAbility.match?(engine, ref, controller) && narrow?(engine, ref, controller)

          def match_for?(engine, ref, controller, _source, **) = match?(engine, ref, controller)

          def matches_types?(_types) = false
          def matches_facts?(_facts) = false
          def live_keys = []
          def uses_chosen? = false

          private

          def narrow?(engine, ref, controller)
            obj = engine.object(ref)
            return false if @kind && (engine.stack_ability(obj).kind == :triggered) != (@kind == "triggered")
            return false if @controller && (@controller == "you") != (obj.controller == controller)

            @source.nil? || source_ok?(engine, obj)
          end

          # CR 113.7: the source of an ability is the object that created it; one that has left the
          # battlefield is matched as it last existed (its card's characteristics).
          def source_ok?(engine, obj)
            source = engine.state.objects[obj.source]
            return @source.match_for?(engine, source.id, obj.controller, nil) if source&.zone == :battlefield

            card = source&.card || obj.card
            defn = engine.catalog.fetch(card)
            @source.matches_facts?(Facts.new(chars: defn.printed_characteristics, counters: {}, token: defn.token?))
          end
        end
      end
    end
  end
end
