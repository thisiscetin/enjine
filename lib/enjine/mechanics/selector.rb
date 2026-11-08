# frozen_string_literal: true

module Enjine
  module Mechanics
    # The context an effect runs in.
    # `results` lists, per earlier effect of the same effect list, the objects that effect
    # moved or created (CR 400.7j: "the card exiled this way"); see Selector {"result": n}.
    EffectContext = Struct.new(:controller, :source, :object, :targets, :results)

    # Data form of "who/what does this effect apply to":
    #   {"target": 0}                               the first chosen target
    #   "self"                                      the source permanent
    #   "you"                                       the controller
    #   "each_opponent"                             every opponent
    #   {"each": "creature", "controller": "you"}  every matching object (you | opponent | any)
    #   {"result": 0}                               what effect 0 of this list moved or created (CR 400.7j)
    class Selector
      CONTROLLERS = %w[you opponent any].freeze

      attr_reader :kind, :value, :controller

      def self.build(data, errors, path, targets_count:, results_count: 0)
        case data
        when "self", "you", "each_opponent" then new(data.to_sym)
        when Hash
          data = data.transform_keys(&:to_s)
          return build_result(data, errors, path, results_count) if data.key?("result")

          build_hash(data, errors, path, targets_count)
        else
          errors << "#{path}: must be {\"target\": n}, \"self\", \"you\", \"each_opponent\" or {\"each\": filter}"
          nil
        end
      end

      # {"result": n}: n must name an earlier effect of the same list (a nested list sees its parent's).
      def self.build_result(data, errors, path, results_count)
        Mechanics.check_keys(data, %w[result], errors, path)
        index = data["result"]
        unless index.is_a?(Integer) && index >= 0 && index < results_count
          errors << "#{path}.result: must refer to one of the #{results_count} earlier effects"
        end
        new(:result, index)
      end

      def self.build_hash(data, errors, path, targets_count)
        if data.key?("target")
          index = data["target"]
          unless index.is_a?(Integer) && index >= 0 && index < targets_count
            errors << "#{path}.target: must refer to one of the #{targets_count} declared targets"
          end
          Mechanics.check_keys(data, %w[target], errors, path)
          new(:target, index)
        elsif data.key?("each")
          Mechanics.check_keys(data, %w[each controller], errors, path)
          filter = Mechanics.build_entry(:filter, data["each"], errors, "#{path}.each")
          controller = data.fetch("controller", "any")
          errors << "#{path}.controller: must be one of #{CONTROLLERS.join(", ")}" unless CONTROLLERS.include?(controller)
          new(:each, filter, controller)
        else
          errors << "#{path}: needs \"target\" or \"each\""
          nil
        end
      end

      def initialize(kind, value = nil, controller = nil)
        @kind = kind
        @value = value
        @controller = controller
        freeze
      end

      def to_s
        case kind
        when :target then "target ##{value + 1}"
        when :result then "the object(s) from effect ##{value + 1}"
        when :self then "itself"
        when :you then "you"
        when :each_opponent then "each opponent"
        when :each then "each #{value.primitive_name.tr("_",
                                                        " ")}#{{ "you" => " you control",
                                                                 "opponent" => " an opponent controls" }[controller]}"
        end
      end

      # Resolves to a list of references (object ids / "player:<name>") at resolution time.
      def resolve(engine, ctx)
        case kind
        when :target then [ctx.targets[value]].compact
        when :result then Array(ctx.results&.[](value))
        when :self then engine.state.battlefield.include?(ctx.source) ? [ctx.source] : []
        when :you then [Filters.player_ref(engine, ctx.controller)]
        when :each_opponent
          engine.state.players.each_index.reject { it == ctx.controller }.map { Filters.player_ref(engine, it) }
        when :each then each(engine, ctx)
        end
      end

      private

      def each(engine, ctx)
        value.candidates(engine, ctx.controller).select do |ref|
          index = Filters.player_index(engine, ref)
          owner = index || engine.object(ref).controller
          controller == "any" || (controller == "you") == (owner == ctx.controller)
        end
      end
    end
  end
end
