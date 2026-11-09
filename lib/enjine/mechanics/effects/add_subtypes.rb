# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "Until end of turn, they become Warriors in addition to their other types." (CR 613.1d, 205.1b)
      class AddSubtypes < Effect
        primitive :effect, :add_subtypes,
                  description: "Each referenced permanent gets the `subtypes` in addition to its other types until " \
                               "end of turn (layer 4).",
                  rules: %w[613.1d 205.1b 611.2a 611.2c],
                  params: { "subtypes" => "list of lowercase subtypes", "to" => "selector" },
                  example: { "add_subtypes" => { "subtypes" => ["warrior"], "to" => { "target" => 0 } } }

        attr_reader :subtypes

        def self.keys = %w[subtypes to if]

        def setup(params, errors, path)
          @subtypes = Mechanics.list_param(params, :subtypes, errors, path).map(&:to_s)
          ok = !@subtypes.empty? && @subtypes.all? { CardDefinition::SUBTYPE_FORMAT.match?(it) }
          errors << "#{path}.subtypes: must be a non-empty list of lowercase subtypes" unless ok
        end

        def apply(engine, ctx) = engine.add_continuous_effect!("add_subtypes", ctx, objects(engine, ctx), "subtypes" => subtypes)
        def to_s = "becomes #{subtypes.join(" ")} in addition until end of turn → #{to}"
      end
    end
  end
end
