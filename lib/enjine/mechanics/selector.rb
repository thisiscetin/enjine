# frozen_string_literal: true

module Enjine
  module Mechanics
    # The context an effect runs in.
    EffectContext = Struct.new(:controller, :source, :object, :targets)

    # Data form of "who/what does this effect apply to":
    #   {"target": 0}                               the first chosen target
    #   "self"                                      the source permanent
    #   "you"                                       the controller
    #   "each_opponent"                             every opponent
    #   {"each": "creature", "controller": "you"}  every matching object (you | opponent | any)
    class Selector
      CONTROLLERS = %w[you opponent any].freeze

      attr_reader :kind, :value, :controller

      def self.build(data, errors, path, targets_count:)
        case data
        when "self", "you", "each_opponent" then new(data.to_sym)
        when Hash then build_hash(data.transform_keys(&:to_s), errors, path, targets_count)
        else
          errors << "#{path}: must be {\"target\": n}, \"self\", \"you\", \"each_opponent\" or {\"each\": filter}"
          nil
        end
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
