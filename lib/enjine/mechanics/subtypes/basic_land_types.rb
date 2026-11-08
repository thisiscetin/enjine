# frozen_string_literal: true

module Enjine
  module Mechanics
    module Subtypes
      # Shared behavior of the five basic land types (CR 305.6): each grants an
      # intrinsic "{T}: Add <color>." ability.
      class BasicLandType < Primitive
        class << self
          attr_reader :color

          def define(name, color)
            klass = Class.new(self)
            klass.instance_variable_set(:@color, color)
            Subtypes.const_set(name.capitalize, klass)
            klass.primitive :subtype, name,
                            description: "Basic land type. A land with this subtype has \"{T}: Add {#{color}}.\"",
                            rules: %w[305.6 205.3i],
                            example: { "types" => ["land"], "subtypes" => [name.to_s] }
            klass
          end

          def applies_to = [:land]

          def intrinsic_abilities
            @intrinsic_abilities ||= [Abilities::ManaAbility.new([Costs::Tap::INSTANCE].freeze, [color].freeze)].freeze
          end
        end
      end

      { plains: :W, island: :U, swamp: :B, mountain: :R, forest: :G }.each do |name, color|
        BasicLandType.define(name, color)
      end
    end
  end
end
