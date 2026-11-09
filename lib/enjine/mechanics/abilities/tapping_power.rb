# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # "This creature saddles Mounts and crews Vehicles as though its power were 2 greater", "... using its
      # toughness rather than its power", "stations permanents using its toughness rather than its power" (CR
      # 702.122a, 702.171a, 702.184c): a static ability of the creature changing the number it counts when it's
      # tapped to pay a crew or saddle cost or to station a permanent. The costs ask TappingPower.of.
      class TappingPower < Primitive
        ACTIONS = %w[crew saddle station].freeze
        USES = %w[power toughness toughness_if_greater].freeze

        primitive :ability, :tapping_power,
                  description: "When this creature is tapped to pay the cost of the abilities in `for` (crew, saddle, " \
                               "station), it counts its `use` (power, default; toughness; toughness_if_greater: its " \
                               "toughness when that's greater than its power) plus `plus`. Several of them add up their " \
                               "`plus`. A `static` can grant it.",
                  rules: %w[702.122a 702.171a 702.184a 702.184c],
                  params: { "for" => "list of #{ACTIONS.join(", ")}", "use" => USES.join(" | "), "plus" => "integer (default 0)" },
                  example: { "tapping_power" => { "for" => %w[crew saddle], "plus" => 2 } }

        attr_reader :actions, :use, :plus

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[for use plus], errors, path)
          actions = Mechanics.fetch_param(params, :for)
          unless actions.is_a?(Array) && !actions.empty? && (actions - ACTIONS).empty?
            errors << "#{path}.for: must be a non-empty list of #{ACTIONS.join(", ")}"
            actions = []
          end
          use = Mechanics.fetch_param(params, :use) || "power"
          errors << "#{path}.use: must be one of #{USES.join(", ")}" unless USES.include?(use)
          plus = params.key?("plus") ? Mechanics.integer_param(params, :plus, errors, path) : 0
          errors << "#{path}: needs `use` or `plus`" if use == "power" && plus.to_i.zero?
          new(actions.map(&:to_sym), use, plus.to_i)
        end

        # The number `creature` counts when tapped for `action` (:crew, :saddle or :station): its power unless an
        # ability of it says otherwise.
        def self.of(engine, creature, action)
          mods = engine.chars(creature).abilities.map(&:ability).select { it.kind == :tapping_power && it.actions.include?(action) }
          power, toughness = engine.power_toughness(creature)
          base = if mods.any? { it.use == "toughness" } then toughness
                 elsif mods.any? { it.use == "toughness_if_greater" } then [power, toughness].max
                 else power
                 end
          base + mods.sum(&:plus)
        end

        def initialize(actions, use, plus)
          super()
          @actions = actions.freeze
          @use = use
          @plus = plus
          freeze
        end

        def kind = :tapping_power
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []

        def to_s
          counted = { "power" => "power", "toughness" => "toughness", "toughness_if_greater" => "toughness if greater" }[use]
          "#{actions.join(", ")} using its #{counted}#{" + #{plus}" unless plus.zero?}"
        end
      end
    end
  end
end
