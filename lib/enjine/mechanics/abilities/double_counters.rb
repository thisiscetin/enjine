# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # Counter doubling: a replacement effect (CR 614.1a) of a permanent on the battlefield that
      # doubles the number of counters its controller puts on matching permanents. Counters a
      # permanent enters with are counters put on it (CR 122.6), by its controller unless an effect
      # says otherwise (CR 122.6a).
      class DoubleCounters < Primitive
        primitive :ability, :double_counters,
                  description: "While this permanent is on the battlefield, if its controller would put one or more " \
                               "counters (only `counter`, if given) on a permanent matching `affects` " \
                               "({\"each\": filter, \"controller\": you|opponent|any}, relative to this permanent's " \
                               "controller), the number put is doubled. This includes counters a " \
                               "permanent enters with.",
                  rules: %w[614.1a 122.6 122.6a 616.1],
                  params: { "affects" => "{\"each\": filter, \"controller\": ...}", "counter" => "optional counter name" },
                  example: { "double_counters" => { "affects" => { "each" => "creature", "controller" => "you" } } }

        attr_reader :filter, :controller, :counter

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[affects counter], errors, path)
          affects = Mechanics.fetch_param(params, :affects)
          unless affects.is_a?(Hash) && affects["each"]
            errors << "#{path}.affects: must be {\"each\": filter, ...}"
            affects = { "each" => "permanent" }
          end
          Mechanics.check_keys(affects, %w[each controller], errors, "#{path}.affects")
          filter = Mechanics.build_entry(:filter, affects["each"], errors, "#{path}.affects.each")
          live = filter ? filter.live_keys : []
          errors << "#{path}.affects.each: #{live.join(", ")} can't be used here yet" unless live.empty?
          controller = affects.fetch("controller", "any")
          errors << "#{path}.affects.controller: must be one of you, opponent, any" unless %w[you opponent any].include?(controller)
          counter = Mechanics.fetch_param(params, :counter)
          counter = Counters.normalize(counter) if counter
          message = counter && Counters.error(counter)
          errors << "#{path}.counter: #{message}" if message
          new(filter, controller, counter)
        end

        def initialize(filter, controller, counter)
          super()
          @filter = filter
          @controller = controller
          @counter = counter
          freeze
        end

        def kind = :double_counters
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []

        def to_s
          label = filter.is_a?(Class) ? filter.primitive_name.tr("_", " ") : filter.to_s
          whose = { "you" => " you control", "opponent" => " an opponent controls" }[controller]
          "you put twice as many #{counter || "counters"} on each #{label}#{whose}"
        end

        # Whether `putter` putting `kind` counters on a permanent (controlled by `owner_controller`,
        # described by `facts`) is doubled by this ability of `source`.
        def doubles?(source, putter, owner_controller, kind, facts)
          return false unless putter == source.controller && (counter.nil? || counter == kind)
          return false unless controller == "any" || (controller == "you") == (owner_controller == source.controller)

          filter.matches_facts?(facts)
        end
      end
    end
  end
end
