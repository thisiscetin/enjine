# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # A static ability that modifies other permanents while its source is on the battlefield
      # (CR 604, 611.3, 613): "Creatures you control get +1/+1", "Other Elves you control have
      # reach". Unlike a resolved effect, the set of affected objects is re-evaluated continuously.
      class StaticAbility < Primitive
        primitive :ability, :static,
                  description: "While its source is on the battlefield, every matching permanent gets `pump` and/or " \
                               "the `keywords`. `affects` is {\"each\": filter, \"controller\": you|opponent|any, " \
                               "\"other\": true} (relative to the source's controller), or \"attached\": the " \
                               "permanent the source is attached to (\"equipped/enchanted creature\").",
                  rules: %w[604.1 611.3a 613.1f 613.4c 301.5f 303.4m],
                  params: { "affects" => "{\"each\": filter, \"controller\": ..., \"other\": bool} or \"attached\"",
                            "pump" => "{\"power\": n, \"toughness\": n}", "keywords" => "list of keywords" },
                  example: { "static" => { "affects" => { "each" => "creature", "controller" => "you" },
                                           "pump" => { "power" => 1, "toughness" => 1 } } }

        attr_reader :filter, :controller, :other, :power, :toughness, :keywords

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[affects pump keywords], errors, path)
          affects = Mechanics.fetch_param(params, :affects)
          return build_attached(params, errors, path) if affects == "attached"

          unless affects.is_a?(Hash) && affects["each"]
            errors << "#{path}.affects: must be {\"each\": filter, ...}"
            affects = { "each" => "creature" }
          end
          Mechanics.check_keys(affects, %w[each controller other], errors, "#{path}.affects")
          filter = Mechanics.build_entry(:filter, affects["each"], errors, "#{path}.affects.each")
          live = filter ? filter.live_keys : []
          # CR 613.8: these would make the layer pass depend on its own result.
          errors << "#{path}.affects.each: #{live.join(", ")} can't be used in a static ability yet" unless live.empty?
          pump, keywords = parse_grants(params, errors, path)
          new(filter, affects.fetch("controller", "any"), affects["other"] == true,
              pump.fetch("power", 0), pump.fetch("toughness", 0), keywords)
        end

        # "affects": "attached" — "Equipped creature gets ..." / "Enchanted creature has ...": the
        # permanent the source is attached to, whoever controls it (CR 301.5d, 301.5f, 303.4m).
        def self.build_attached(params, errors, path)
          pump, keywords = parse_grants(params, errors, path)
          new(:attached, "any", false, pump.fetch("power", 0), pump.fetch("toughness", 0), keywords)
        end

        def self.parse_grants(params, errors, path)
          pump = Mechanics.fetch_param(params, :pump) || {}
          keywords = Array(Mechanics.fetch_param(params, :keywords)).map { it.to_s.downcase.tr(" -", "__") }
          keywords.each { errors << "#{path}.keywords: unknown keyword #{it.inspect}" unless Enjine.registry.fetch(:keyword, it) }
          errors << "#{path}: needs pump and/or keywords" if pump.empty? && keywords.empty?
          [pump, keywords.map(&:to_sym)]
        end

        def initialize(filter, controller, other, power, toughness, keywords)
          super()
          @filter = filter
          @controller = controller
          @other = other
          @power = power
          @toughness = toughness
          @keywords = keywords.freeze
          freeze
        end

        def kind = :static
        def attached? = @filter == :attached
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []

        # Matches on printed characteristics and counters (Filters::Facts), so the layer pass never
        # depends on its own result.
        def affects?(object, source, facts)
          return source.attached_to == object.id if attached?
          return false if @other && object.id == source.id
          return false unless @controller == "any" || (@controller == "you") == (object.controller == source.controller)

          @filter.matches_facts?(facts)
        end

        def to_s
          bits = []
          bits << "#{format("%+d", power)}/#{format("%+d", toughness)}" if power.nonzero? || toughness.nonzero?
          bits << keywords.join(", ") unless keywords.empty?
          return "the attached permanent gets #{bits.join(" and ")}" if attached?

          "#{"other " if other}#{filter.respond_to?(:primitive_name) ? filter.primitive_name : filter}s " \
            "#{{ "you" => "you control ", "opponent" => "opponents control " }[controller]}get #{bits.join(" and ")}"
        end
      end
    end

    module Effects
      # "gains flying until end of turn" (CR 611.2, 613.1f): grant keywords to a locked set.
      class Grant < Effect
        primitive :effect, :grant,
                  description: "Each referenced permanent gains the `keywords` until end of turn.",
                  rules: %w[611.2a 611.2c 613.1f 514.2],
                  params: { "keywords" => "list of keywords", "to" => "selector" },
                  example: { "grant" => { "keywords" => ["flying"], "to" => { "target" => 0 } } }

        attr_reader :keywords

        def self.keys = %w[keywords to if]

        def setup(params, errors, path)
          @keywords = Array(Mechanics.fetch_param(params, :keywords)).map { it.to_s.downcase.tr(" -", "__") }
          errors << "#{path}.keywords: needs at least one keyword" if @keywords.empty?
          @keywords.each { errors << "#{path}.keywords: unknown keyword #{it.inspect}" unless Enjine.registry.fetch(:keyword, it) }
        end

        def apply(engine, ctx)
          engine.add_continuous_effect!("grant", ctx, objects(engine, ctx), "keywords" => keywords)
        end

        def to_s = "gains #{keywords.join(", ")} until end of turn → #{to}"
      end
    end
  end
end
