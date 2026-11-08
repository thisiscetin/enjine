# frozen_string_literal: true

module Enjine
  module Mechanics
    # Target filters (CR 115) and "each" selectors. A filter lists candidate
    # references in a deterministic order: players (seat order), then battlefield
    # order, then stack order (top first). References are object ids or "player:<name>".
    module Filters
      PLAYER_PREFIX = "player:"

      def self.player_ref(engine, index) = "#{PLAYER_PREFIX}#{engine.name(index)}"

      def self.player_index(engine, ref)
        return nil unless ref.is_a?(String) && ref.start_with?(PLAYER_PREFIX)

        engine.names.index(ref.delete_prefix(PLAYER_PREFIX))
      end

      # Base filter: subclasses define players? and match_object?.
      class Filter < Primitive
        def self.players?(_engine, _index, _controller) = false
        def self.match_object?(_engine, _object, _controller) = false
        def self.zone = :battlefield

        def self.candidates(engine, controller)
          players = engine.state.players.each_index.select { players?(engine, it, controller) }
                          .map { Filters.player_ref(engine, it) }
          objects = engine.state.public_send(zone).select { |id| match_object?(engine, engine.object(id), controller) }
          players + objects
        end

        def self.match?(engine, ref, controller)
          index = Filters.player_index(engine, ref)
          return players?(engine, index, controller) if index
          return false unless engine.state.objects.key?(ref)

          obj = engine.object(ref)
          obj.zone == zone && match_object?(engine, obj, controller)
        end

        RESTRICTIONS = %w[controller other not any_of attacking blocking tapped].freeze

        # A bare filter is the class itself; parameters wrap it in a Restricted filter, e.g.
        # {"creature": {"controller": "you"}}, {"creature": {"other": true}},
        # {"permanent": {"not": ["land"]}}, {"permanent": {"any_of": ["artifact", "creature"]}},
        # {"creature": {"attacking": true}}.
        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, RESTRICTIONS, errors, path)
          return self if params.empty?

          Restricted.build(self, params.transform_keys(&:to_s), errors, path)
        end

        def self.candidates_for(engine, controller, _source) = candidates(engine, controller)
        def self.match_for?(engine, ref, controller, _source) = match?(engine, ref, controller)

        def self.type?(engine, object, type) = object.kind == "card" && engine.chars(object).type?(type)

        # For trigger subjects: whether an object with these card types matches.
        def self.matches_types?(types) = respond_to?(:card_types) ? types.intersect?(card_types) : true
      end

      # A filter narrowed by restrictions (see Filter.build).
      class Restricted
        TYPES = %w[artifact creature enchantment land planeswalker instant sorcery].freeze

        attr_reader :base

        def self.build(base, params, errors, path)
          controller = params["controller"]
          errors << "#{path}.controller: must be you or opponent" if controller && !%w[you opponent].include?(controller)
          %w[not any_of].each do |key|
            list = params[key]
            next if list.nil? || (list.is_a?(Array) && (list - TYPES).empty?)

            errors << "#{path}.#{key}: must be a list of card types (#{TYPES.join(", ")})"
          end
          %w[other attacking blocking tapped].each do |key|
            errors << "#{path}.#{key}: must be true or false" unless params[key].nil? || [true, false].include?(params[key])
          end
          new(base, params)
        end

        def initialize(base, params)
          @base = base
          @controller = params["controller"]
          @other = params["other"] == true
          @not = Array(params["not"]).map(&:to_sym)
          @any_of = Array(params["any_of"]).map(&:to_sym)
          @attacking = params["attacking"]
          @blocking = params["blocking"]
          @tapped = params["tapped"]
          @params = params
          freeze
        end

        def primitive_name = base.primitive_name

        def candidates(engine, controller) = candidates_for(engine, controller, nil)

        def candidates_for(engine, controller, source)
          base.candidates(engine, controller).select { allowed?(engine, it, controller, source) }
        end

        def match?(engine, ref, controller) = match_for?(engine, ref, controller, nil)

        def match_for?(engine, ref, controller, source)
          base.match?(engine, ref, controller) && allowed?(engine, ref, controller, source)
        end

        # For trigger subjects: card types only.
        def matches_types?(types)
          base.matches_types?(types) && !types.intersect?(@not) && (@any_of.empty? || types.intersect?(@any_of))
        end

        def to_s
          words = []
          words << "another" if @other
          words << "attacking" if @attacking
          words << "non#{@not.join("/non")}" unless @not.empty?
          words << (@any_of.empty? ? base.primitive_name.tr("_", " ") : @any_of.join(" or "))
          words << { "you" => "you control", "opponent" => "an opponent controls" }[@controller]
          words.compact.join(" ")
        end

        private

        def allowed?(engine, ref, controller, source)
          return false if @other && ref == source

          index = Filters.player_index(engine, ref)
          owner = index || engine.state.objects[ref]&.controller
          return false if @controller && (@controller == "you") != (owner == controller)
          return true if index

          object_allowed?(engine, ref)
        end

        def object_allowed?(engine, ref)
          types = engine.chars(ref).types
          return false if types.intersect?(@not)
          return false unless @any_of.empty? || types.intersect?(@any_of)
          return false if !@attacking.nil? && engine.attackers.key?(ref) != @attacking
          return false if !@blocking.nil? && engine.state.blockers.key?(ref) != @blocking
          return false if !@tapped.nil? && engine.object(ref).tapped != @tapped

          true
        end
      end

      # A creature on the battlefield.
      class Creature < Filter
        primitive :filter, :creature, description: "A creature on the battlefield.", rules: %w[115.1], example: "creature"
        def self.match_object?(engine, object, _controller) = type?(engine, object, :creature)
        def self.card_types = [:creature]
      end

      # A planeswalker on the battlefield.
      class Planeswalker < Filter
        primitive :filter, :planeswalker, description: "A planeswalker on the battlefield.", rules: %w[115.1],
                                          example: "planeswalker"
        def self.match_object?(engine, object, _controller) = type?(engine, object, :planeswalker)
        def self.card_types = [:planeswalker]
      end

      # A creature or planeswalker on the battlefield.
      class CreatureOrPlaneswalker < Filter
        primitive :filter, :creature_or_planeswalker, description: "A creature or planeswalker on the battlefield.",
                                                      rules: %w[115.1], example: "creature_or_planeswalker"
        def self.match_object?(engine, object, _controller)
          type?(engine, object, :creature) || type?(engine, object, :planeswalker)
        end
      end

      # A land on the battlefield.
      class Land < Filter
        primitive :filter, :land, description: "A land on the battlefield.", rules: %w[115.1], example: "land"
        def self.match_object?(engine, object, _controller) = type?(engine, object, :land)
        def self.card_types = [:land]
      end

      # An artifact on the battlefield.
      class Artifact < Filter
        primitive :filter, :artifact, description: "An artifact on the battlefield.", rules: %w[115.1], example: "artifact"
        def self.match_object?(engine, object, _controller) = type?(engine, object, :artifact)
        def self.card_types = [:artifact]
      end

      # Any permanent.
      class Permanent < Filter
        primitive :filter, :permanent, description: "Any permanent on the battlefield.", rules: %w[110.1],
                                       example: "permanent"
        def self.match_object?(_engine, _object, _controller) = true
      end

      # A player.
      class Player < Filter
        primitive :filter, :player, description: "A player.", rules: %w[115.1], example: "player"
        def self.players?(_engine, index, _controller) = !index.nil?
      end

      # An opponent of the controller.
      class Opponent < Filter
        primitive :filter, :opponent, description: "An opponent of the ability's controller.", rules: %w[102.2],
                                      example: "opponent"
        def self.players?(_engine, index, controller) = !index.nil? && index != controller
      end

      # "Any target": a creature, player or planeswalker (CR 115.4).
      class AnyTarget < Filter
        primitive :filter, :any_target, description: "A creature, player or planeswalker (battles: later).",
                                        rules: %w[115.4], example: "any_target"
        def self.players?(_engine, index, _controller) = !index.nil?
        def self.match_object?(engine, object, controller) = CreatureOrPlaneswalker.match_object?(engine, object, controller)
      end

      # A spell on the stack.
      class Spell < Filter
        primitive :filter, :spell, description: "A spell on the stack.", rules: %w[112.1 115.1], example: "spell"
        def self.zone = :stack
        def self.match_object?(_engine, object, _controller) = object.kind == "card"
      end
    end
  end
end
