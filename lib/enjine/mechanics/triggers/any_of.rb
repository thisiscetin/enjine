# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # "Whenever ~ enters or attacks": one ability with several trigger events. It triggers once
      # per event that matches any of them (CR 603.2c).
      class AnyOf < Trigger
        primitive :trigger, :any_of,
                  description: "Triggers when any of the listed trigger conditions is met.",
                  rules: %w[603.2 603.2c],
                  params: { "(list)" => "two or more trigger conditions" },
                  example: { "any_of" => [{ "enters" => {} }, { "attacks" => {} }] }

        attr_reader :parts

        def self.scalar_params? = true

        def self.build(params, errors, path, **)
          unless params.is_a?(Array) && params.size >= 2
            errors << "#{path}: must be a list of at least two trigger conditions"
            params = []
          end
          parts = params.each_with_index.filter_map { |entry, i| Mechanics.build_entry(:trigger, entry, errors, "#{path}[#{i}]") }
          new(parts)
        end

        def initialize(parts) # rubocop:disable Lint/MissingSuper -- no subject or params of its own
          @parts = parts.freeze
          freeze
        end

        def watches?(event) = parts.any? { it.watches?(event) }
        def leaves_battlefield? = parts.any?(&:leaves_battlefield?)
        def match?(engine, event, source) = parts.any? { it.watches?(event) && it.match?(engine, event, source) }

        def to_s
          parts.map(&:to_s).each_with_index.map { |text, i| i.zero? ? text : text.sub(/\A(When|Whenever) /, "") }.join(" or ")
        end
      end
    end
  end
end
