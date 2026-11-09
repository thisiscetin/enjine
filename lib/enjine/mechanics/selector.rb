# frozen_string_literal: true

module Enjine
  module Mechanics
    # The context an effect runs in.
    # `results` lists, per earlier effect of the same effect list, the objects that effect
    # moved or created (CR 400.7j: "the card exiled this way"); see Selector {"result": n}.
    # `amounts`: per earlier effect, how much it changed (life an earlier effect took); see Amount {"this_way": n}.
    # `memory`: stands in for the resolving ability's memory while a trigger condition is checked (CR 603.4).
    EffectContext = Struct.new(:controller, :source, :object, :targets, :results, :amounts, :memory)

    # Data form of "who/what does this effect apply to":
    #   {"target": 0}                               the first chosen target
    #   "self"                                      the source permanent, or the source card while it's still in
    #                                               the graveyard, hand or exile ("return this card from your
    #                                               graveyard", CR 113.6m; it's a new object once it moves, CR 400.7)
    #   "you"                                       the controller
    #   "each_opponent"                             every opponent
    #   "attached"                                  what the source is attached to ("enchanted creature", CR 303.4m)
    #   {"each": "creature", "controller": "you"}  every matching object (you | opponent | any)
    #   {"result": 0}                               what effect 0 of this list moved or created (CR 400.7j)
    #   {"controller_of": selector}                 the controller of each referenced object ("its controller");
    #                                               one that has left the battlefield as it last existed (CR 608.2h)
    #   {"triggering": "object" | "player"}        what the trigger event was about ("that creature",
    #                                               "that player", CR 603.2); see Triggers.event_facts
    #   "watched"                                   what a delayed triggered ability watches (CR 603.7c)
    #   "exiled_with"                               cards in exile exiled with the source (linked abilities, CR 607.2a)
    #   "gift_recipient"                            the opponent chosen for the spell's gift (CR 702.174a)
    class Selector
      CONTROLLERS = %w[you opponent any].freeze
      TRIGGERING = %w[object player].freeze
      # Where "self" finds its source (CR 113.6m); a source that changed zones is a new object (CR 400.7).
      SELF_ZONES = %i[battlefield graveyard exile hand].freeze

      attr_reader :kind, :value, :controller

      def self.build(data, errors, path, targets_count:, results_count: 0)
        case data
        when "self", "you", "each_opponent", "attached", "watched", "exiled_with", "gift_recipient" then new(data.to_sym)
        when Hash
          data = data.transform_keys(&:to_s)
          return build_result(data, errors, path, results_count) if data.key?("result")
          return build_controller_of(data, errors, path, targets_count, results_count) if data.key?("controller_of")
          return build_triggering(data, errors, path) if data.key?("triggering")

          build_hash(data, errors, path, targets_count)
        else
          errors << "#{path}: must be {\"target\": n}, \"self\", \"you\", \"each_opponent\", \"attached\" or {\"each\": filter}"
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

      def self.build_controller_of(data, errors, path, targets_count, results_count)
        Mechanics.check_keys(data, %w[controller_of], errors, path)
        inner = build(data["controller_of"], errors, "#{path}.controller_of", targets_count: targets_count,
                                                                              results_count: results_count)
        new(:controller_of, inner)
      end

      def self.build_triggering(data, errors, path)
        Mechanics.check_keys(data, %w[triggering], errors, path)
        errors << "#{path}.triggering: must be one of #{TRIGGERING.join(", ")}" unless TRIGGERING.include?(data["triggering"])
        new(:triggering, data["triggering"])
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
        when :controller_of then "the controller of #{value}"
        when :self then "itself"
        when :attached then "the attached permanent"
        when :triggering then "the triggering #{value}"
        when :watched then "the watched object(s)"
        when :you then "you"
        when :each_opponent then "each opponent"
        when :exiled_with then "the cards exiled with it"
        when :gift_recipient then "the chosen opponent"
        when :each then "each #{value.primitive_name.tr("_",
                                                        " ")}#{{ "you" => " you control",
                                                                 "opponent" => " an opponent controls" }[controller]}"
        end
      end

      # Resolves to a list of references (object ids / "player:<name>") at resolution time.
      def resolve(engine, ctx)
        case kind
        when :target then Array(ctx.targets[value]).compact # a counted target's slot holds a list (CR 601.2c)
        when :result then Array(ctx.results&.[](value))
        when :self then SELF_ZONES.include?(engine.state.objects[ctx.source]&.zone) ? [ctx.source] : []
        when :attached then attached(engine, ctx)
        when :triggering then triggering(engine, ctx)
        when :watched then Array(Selector.memory(engine, ctx)["watched"])
        when :you then [Filters.player_ref(engine, ctx.controller)]
        when :each_opponent
          engine.state.players.each_index.reject { it == ctx.controller }.map { Filters.player_ref(engine, it) }
        when :each then each(engine, ctx)
        when :controller_of then controllers(engine, ctx)
        when :exiled_with then Linked.exiled_with(engine, ctx.source, ctx)
        when :gift_recipient # the spell, or the permanent it became (CR 702.174b)
          Array(Selector.memory(engine, ctx)["gift"] || engine.state.objects[ctx.source]&.memory&.[]("gift"))
        end
      end

      # What the resolving triggered ability remembers (the event facts, watched objects).
      def self.memory(engine, ctx) = ctx.memory || engine.state.objects[ctx.object]&.memory || {}

      private

      def controllers(engine, ctx)
        Array(value&.resolve(engine, ctx)).filter_map do |ref|
          obj = engine.state.objects[ref]
          controller = if obj && %i[battlefield
                                    stack].include?(obj.zone)
                         obj.controller
                       else
                         engine.resolving_last_known(ref)&.fetch("controller") ||
                           engine.state.objects[ctx.object]&.memory&.dig(Linked::LKI, ref) || obj&.controller
                       end
          controller && Filters.player_ref(engine, controller)
        end.uniq
      end

      def triggering(engine, ctx)
        found = Selector.memory(engine, ctx).fetch("triggering", {})[value]
        return [] if found.nil?

        value == "player" ? [Filters.player_ref(engine, found)] : [found]
      end

      # CR 301.5f / 303.4m: "equipped/enchanted creature" is whatever the source is attached to now.
      def attached(engine, ctx)
        to = engine.state.objects[ctx.source]&.attached_to
        to && engine.state.battlefield.include?(to) ? [to] : []
      end

      def each(engine, ctx)
        value.candidates_for(engine, ctx.controller, ctx.source, ctx: ctx).select do |ref|
          index = Filters.player_index(engine, ref)
          owner = index || engine.object(ref).controller
          controller == "any" || (controller == "you") == (owner == ctx.controller)
        end
      end
    end
  end
end
