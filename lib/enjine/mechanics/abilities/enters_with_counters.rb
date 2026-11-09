# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # Entering with counters: a permanent's own counters as it enters, or extra counters a permanent
      # on the battlefield gives to matching permanents as they enter. Replacement effects that modify
      # how a permanent enters (CR 614.1c, 614.12); counters given as it enters count as counters put
      # on it (CR 122.6).
      class EntersWithCounters < Primitive
        primitive :ability, :enters_with_counters,
                  description: "Without `affects`: this permanent enters with the `counters` on it; a count may be an " \
                               "amount computed as it enters (e.g. the mana spent to cast it, CR 601.2h). With `affects` " \
                               "({\"each\": filter, \"controller\": you|opponent|any, \"other\": true}, relative to " \
                               "this permanent's controller): while this permanent is on the battlefield, each " \
                               "matching permanent enters with the `counters` in addition to any others.",
                  rules: %w[614.1c 614.12 122.6 122.6a],
                  params: { "counters" => "{counter name: n} (n >= 1; without `affects`, n may be an amount)",
                            "affects" => "optional {\"each\": filter, \"controller\": ..., \"other\": bool}" },
                  example: { "enters_with_counters" => { "counters" => { "+1/+1" => 1 },
                                                         "affects" => { "each" => "creature", "controller" => "you",
                                                                        "other" => true } } }

        attr_reader :counters, :filter, :controller, :amounts

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[counters affects], errors, path)
          affects = Mechanics.fetch_param(params, :affects)
          counters = read_counters(Mechanics.fetch_param(params, :counters), errors, "#{path}.counters", amounts: affects.nil?)
          counters, amounts = counters.partition { |_, n| n.is_a?(Integer) }.map(&:to_h)
          return new(counters, nil, nil, amounts) if affects.nil?

          unless affects.is_a?(Hash) && affects["each"]
            errors << "#{path}.affects: must be {\"each\": filter, ...}"
            return new(counters, nil, nil)
          end
          Mechanics.check_keys(affects, %w[each controller other], errors, "#{path}.affects")
          filter = Mechanics.build_entry(:filter, affects["each"], errors, "#{path}.affects.each")
          live = filter ? filter.live_keys : []
          errors << "#{path}.affects.each: #{live.join(", ")} can't be used for an entering permanent" unless live.empty?
          controller = affects.fetch("controller", "any")
          errors << "#{path}.affects.controller: must be one of you, opponent, any" unless %w[you opponent any].include?(controller)
          new(counters, filter, controller)
        end

        # `amounts`: a count may be an amount (Amount), computed as the permanent enters.
        def self.read_counters(raw, errors, path, amounts: false)
          unless raw.is_a?(Hash) && !raw.empty?
            errors << "#{path}: must be a non-empty object {counter name: n}"
            return {}
          end
          raw.to_h do |name, n|
            name = Counters.normalize(name)
            message = Counters.error(name)
            errors << "#{path}.#{name}: #{message}" if message
            next [name, Amount.build(n, errors, "#{path}.#{name}", targets_count: 0)] if amounts && !n.is_a?(Integer)

            errors << "#{path}.#{name}: must be an integer >= 1" unless n.is_a?(Integer) && n >= 1
            [name, n]
          end
        end

        def initialize(counters, filter, controller, amounts = {})
          super()
          @counters = counters.freeze
          @amounts = amounts.freeze
          @filter = filter
          @controller = controller
          freeze
        end

        def kind = :enters_with_counters
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []

        def to_s
          list = (counters.map { |name, n| "#{n} #{name} counter#{"s" if n > 1}" } +
                  amounts.map { |name, n| "#{name} counters equal to #{n}" }).join(" and ")
          return "enters with #{list}" unless filter

          whose = { "you" => " you control", "opponent" => " your opponents control" }[controller]
          label = filter.is_a?(Class) ? filter.primitive_name.tr("_", " ") : filter.to_s
          "#{label}s#{whose} enter with an additional #{list}"
        end

        # The entering permanent's own replacement effect (called by Replacements for it alone).
        def modify_entering(enters) = filter ? nil : add!(enters)

        # Counts computed as it enters, from the entering object (a resolving spell: what was spent on it).
        def modify_entering_for(engine, controller, object_id, enters)
          ctx = EffectContext.new(controller, object_id, object_id, [])
          amounts.each do |name, amount|
            n = amount.value(engine, ctx)
            enters["counters"][name] = enters["counters"].fetch(name, 0) + n if n.positive?
          end
        end

        # A permanent on the battlefield modifying another one as it enters.
        def affects_entering?(source, entering_controller, facts)
          return false unless filter
          return false unless controller == "any" || (controller == "you") == (entering_controller == source.controller)

          filter.matches_facts?(facts)
        end

        def modify_other_entering(enters) = add!(enters)

        private

        def add!(enters)
          counters.each { |name, n| enters["counters"][name] = enters["counters"].fetch(name, 0) + n }
        end
      end
    end
  end
end
