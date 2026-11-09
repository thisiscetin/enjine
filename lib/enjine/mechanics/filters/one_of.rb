# frozen_string_literal: true

module Enjine
  module Mechanics
    module Filters
      # Matches what any of its filters matches: "a land, or a creature with power 6 or more" is
      # [{"land": {}}, {"creature": {"power": {"at_least": 6}}}] (a union of restricted filters, CR 115.1).
      class OneOf < Filter
        primitive :filter, :one_of,
                  description: "Anything at least one of the listed filters matches (each may have restrictions).",
                  rules: %w[115.1 109.2],
                  params: { "(list)" => "two or more filters" },
                  example: { "one_of" => [{ "permanent" => { "any_of" => %w[artifact enchantment] } },
                                          { "creature" => { "power" => { "at_least" => 4 } } }] }

        def self.scalar_params? = true

        def self.build(params, errors, path, **)
          unless params.is_a?(Array) && params.size >= 2
            errors << "#{path}: must be a list of at least two filters"
            return self
          end
          new(params.each_with_index.filter_map { |f, i| Mechanics.build_entry(:filter, f, errors, "#{path}[#{i}]") })
        end

        attr_reader :filters

        def initialize(filters)
          super()
          @filters = filters.freeze
          freeze
        end

        def primitive_name = "one_of"
        def live_keys = filters.flat_map(&:live_keys).uniq
        def uses_chosen? = filters.any?(&:uses_chosen?)
        def to_s = filters.map { it.is_a?(Class) ? it.primitive_name.tr("_", " ") : it.to_s }.join(" or ")
        def candidates(engine, controller) = candidates_for(engine, controller, nil)

        def candidates_for(engine, controller, source, ctx: nil)
          filters.flat_map { it.candidates_for(engine, controller, source, ctx: ctx) }.uniq
        end

        def match?(engine, ref, controller) = match_for?(engine, ref, controller, nil)

        def match_for?(engine, ref, controller, source, ctx: nil)
          filters.any? { it.match_for?(engine, ref, controller, source, ctx: ctx) }
        end

        def matches_types?(types) = filters.any? { it.matches_types?(types) }
        def matches_facts?(facts) = filters.any? { it.matches_facts?(facts) }
      end
    end
  end
end
