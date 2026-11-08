# frozen_string_literal: true

module Enjine
  module Mechanics
    module Filters
      # An activated or triggered ability on the stack (CR 113.1b, 115.1): "counter target activated or
      # triggered ability". Mana abilities never use the stack (CR 605.3b), so they can't be targeted.
      class StackAbility < Filter
        KINDS = %w[activated triggered].freeze

        primitive :filter, :stack_ability,
                  description: "An activated or triggered ability on the stack (`kind`: \"activated\" or " \
                               "\"triggered\" for only one of them).",
                  rules: %w[113.1b 115.1 605.3b],
                  params: { "kind" => KINDS.join(" | ") },
                  example: "stack_ability"

        def self.zone = :stack
        def self.match_object?(_engine, object, _controller) = object.ability?

        def self.build(params, errors, path, **)
          return self if params.empty?

          Mechanics.check_keys(params, %w[kind], errors, path)
          kind = params["kind"]
          errors << "#{path}.kind: must be one of #{KINDS.join(", ")}" unless KINDS.include?(kind)
          Kind.new(kind)
        end

        # Only activated (loyalty included) or only triggered abilities.
        class Kind
          def initialize(kind)
            @kind = kind
            freeze
          end

          def primitive_name = "stack_ability"
          def to_s = "#{@kind} ability"
          def candidates(engine, controller) = StackAbility.candidates(engine, controller).select { kind?(engine, it) }
          def candidates_for(engine, controller, _source) = candidates(engine, controller)
          def match?(engine, ref, controller) = StackAbility.match?(engine, ref, controller) && kind?(engine, ref)
          def match_for?(engine, ref, controller, _source) = match?(engine, ref, controller)
          def matches_types?(_types) = false
          def matches_facts?(_facts) = false
          def live_keys = []

          private

          def kind?(engine, ref)
            ability = engine.stack_ability(engine.object(ref))
            (ability.kind == :triggered) == (@kind == "triggered")
          end
        end
      end
    end
  end
end
