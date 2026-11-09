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

      # What is known about an object without computing its current characteristics: its printed
      # (or last known) characteristics, its counters and whether it is a token.
      Facts = Data.define(:chars, :counters, :token)

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

        # A bare filter is the class itself; parameters wrap it in a Restricted filter (see Restricted).
        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, Restricted::KEYS, errors, path)
          return self if params.empty?

          Restricted.build(self, params.transform_keys(&:to_s), errors, path)
        end

        def self.candidates_for(engine, controller, _source, **) = candidates(engine, controller)

        def self.match_for?(engine, ref, controller, _source, **) = match?(engine, ref, controller)

        def self.type?(engine, object, type) = object.kind == "card" && engine.chars(object).type?(type)

        # Whether an object with these card types matches.
        def self.matches_types?(types) = respond_to?(:card_types) ? types.intersect?(card_types) : true

        # For the layer pass, entering replacements and trigger subjects that left the battlefield:
        # a match on characteristics and counters only (Facts), never on current power/toughness.
        def self.matches_facts?(facts) = matches_types?(facts.chars.types)
        def self.live_keys = []
      end

      # A filter narrowed by restrictions (CR 115.1, 109.2), e.g.
      #   {"creature": {"controller": "you"}}            {"creature": {"other": true}}
      #   {"permanent": {"not": ["land"]}}               {"permanent": {"any_of": ["artifact", "creature"]}}
      #   {"creature": {"attacking": true}}              {"creature": {"power": {"at_least": 4}}}
      #   {"permanent": {"mana_value": {"at_most": 3}}}  {"creature": {"subtypes": ["human"]}}
      #   {"creature": {"supertypes": ["legendary"]}}    {"creature": {"not_supertypes": ["legendary"]}}
      #   {"creature": {"token": false}}                 {"permanent": {"counters": true}} / {"counters": "+1/+1"}
      #   {"creature": {"modified": true}}               {"spell": {"not": ["creature"]}}
      #   {"creature": {"attached_subtypes": ["communicator"]}}  with a Communicator attached to it (CR 301.5, 303.4)
      #   {"creature": {"transformed": true}}            back face up (CR 701.27h); {"prepared": true} (CR 723.3a)
      class Restricted
        TYPES = %w[artifact creature enchantment land planeswalker instant sorcery].freeze
        BOOLEANS = %w[other attacking blocking tapped token modified transformed prepared].freeze
        RANGES = %w[power toughness mana_value].freeze
        TYPE_LISTS = %w[not any_of types].freeze
        NAME_LISTS = %w[subtypes not_subtypes supertypes not_supertypes attached_subtypes].freeze
        KEYS = (%w[controller counters colors] + BOOLEANS + RANGES + TYPE_LISTS + NAME_LISTS).freeze
        # Keys that need current characteristics or combat/tapped status: not usable in the layer pass.
        LIVE = %w[power toughness attacking blocking tapped attached_subtypes transformed prepared].freeze

        attr_reader :base

        def self.build(base, params, errors, path)
          controller = params["controller"]
          errors << "#{path}.controller: must be you or opponent" if controller && !%w[you opponent].include?(controller)
          validate_lists(params, errors, path)
          BOOLEANS.each do |key|
            errors << "#{path}.#{key}: must be true or false" unless params[key].nil? || [true, false].include?(params[key])
          end
          ranges = build_ranges(params, errors, path)
          counters = params["counters"]
          unless counters.nil? || [true, false].include?(counters) || Counters.valid?(counters)
            errors << "#{path}.counters: must be true, false or a counter name"
          end
          colors = params["colors"]
          unless colors.nil? || (colors.is_a?(Array) && !colors.empty? && colors.all? { Mana::COLORS.include?(it.to_s.to_sym) })
            errors << "#{path}.colors: must be a non-empty list of W, U, B, R, G (any of them)"
          end
          new(base, params, ranges)
        end

        def self.validate_lists(params, errors, path)
          TYPE_LISTS.each do |key|
            list = params[key]
            next if list.nil? || (list.is_a?(Array) && (list - TYPES).empty?)

            errors << "#{path}.#{key}: must be a list of card types (#{TYPES.join(", ")})"
          end
          NAME_LISTS.each do |key|
            list = params[key]
            next if list.nil?

            supertypes = key.end_with?("supertypes")
            ok = list.is_a?(Array) && !list.empty? &&
                 list.all? { supertypes ? Enjine.registry.fetch(:supertype, it) : CardDefinition::SUBTYPE_FORMAT.match?(it.to_s) }
            errors << "#{path}.#{key}: must be a non-empty list of #{supertypes ? "supertypes" : "lowercase subtypes"}" unless ok
          end
        end

        BOUNDS = %w[at_least at_most equal].freeze

        # {"at_least": n}, {"at_most": n} and/or {"equal": n}; each bound is an integer or a computed
        # amount ("mana value equal to the number of charge counters on it", CR 202.3, 608.2h). Returns
        # the bounds as Amounts.
        def self.validate_range(range, errors, path)
          unless range.is_a?(Hash) && !range.empty? && (range.keys - BOUNDS).empty?
            errors << "#{path}: must be {\"at_least\": n}, {\"at_most\": n} and/or {\"equal\": n} (n: an amount)"
            return {}
          end
          range.to_h { |key, n| [key, Amount.build(n, errors, "#{path}.#{key}", targets_count: 0, min: -1_000)] }
        end

        def self.build_ranges(params, errors, path)
          RANGES.filter_map { |key| [key, validate_range(params[key], errors, "#{path}.#{key}")] if params.key?(key) }.to_h
        end

        def initialize(base, params, ranges = {})
          @base = base
          @controller = params["controller"]
          @other = params["other"] == true
          @params = params
          @lists = (TYPE_LISTS + NAME_LISTS).to_h { [it, Array(params[it]).map(&:to_sym)] }
          @ranges = ranges.freeze
          @computed = ranges.values.any? { |range| range.values.any? { !it.is_a?(Amount::Fixed) } }
          freeze
        end

        def primitive_name = base.primitive_name

        # A computed bound depends on the game, so (like power) it isn't usable in the layer pass.
        def live_keys = LIVE.select { @params.key?(it) } + (@computed ? ["computed_range"] : [])

        def candidates(engine, controller) = candidates_for(engine, controller, nil)

        # `ctx`: the resolving spell's or ability's EffectContext, for computed range bounds (a source that
        # left the battlefield counts as it last existed, CR 608.2h).
        def candidates_for(engine, controller, source, ctx: nil)
          bounds = resolved_ranges(engine, controller, source, ctx)
          base.candidates(engine, controller).select { allowed?(engine, it, controller, source, bounds) }
        end

        def match?(engine, ref, controller) = match_for?(engine, ref, controller, nil)

        def match_for?(engine, ref, controller, source, ctx: nil)
          base.match?(engine, ref, controller) &&
            allowed?(engine, ref, controller, source, resolved_ranges(engine, controller, source, ctx))
        end

        # Card types only.
        def matches_types?(types)
          base.matches_types?(types) && !types.intersect?(@lists["not"]) &&
            (@lists["any_of"].empty? || types.intersect?(@lists["any_of"])) && (@lists["types"] - types).empty?
        end

        def matches_facts?(facts) = base.matches_facts?(facts) && characteristics_ok?(facts)

        def to_s
          words = []
          words << "another" if @other
          words << "attacking" if @params["attacking"]
          words << (@params["token"] ? "token" : "nontoken") unless @params["token"].nil?
          words.concat(status_words)
          words.concat(@lists["supertypes"]).concat(@lists["not_supertypes"].map { "non#{it}" })
          words << "non#{@lists["not"].join("/non")}" unless @lists["not"].empty?
          words.concat(@lists["types"] + @lists["subtypes"]).concat(@lists["not_subtypes"].map { "non-#{it}" })
          words << (@lists["any_of"].empty? ? base.primitive_name.tr("_", " ") : @lists["any_of"].join(" or "))
          words << { "you" => "you control", "opponent" => "an opponent controls" }[@controller]
          words.concat(@ranges.map { |key, range| "with #{key.tr("_", " ")} #{range_words(range)}" })
          words << "with a #{@lists["attached_subtypes"].join(" or ")} attached" unless @lists["attached_subtypes"].empty?
          words << counter_words
          words.compact.join(" ")
        end

        RANGE_WORDS = { "at_least" => "%s or greater", "at_most" => "%s or less", "equal" => "equal to %s" }.freeze
        private_constant :RANGE_WORDS

        private

        # "modified"; "transformed" / "untransformed", "prepared" / "unprepared" (CR 701.27h, 723.3a).
        def status_words
          words = @params["modified"] ? ["modified"] : []
          words + %w[transformed prepared].reject { @params[it].nil? }.map { @params[it] ? it : "un#{it}" }
        end

        def range_words(range) = range.map { |k, n| format(RANGE_WORDS.fetch(k), n) }.join(" and ")

        def counter_words
          case @params["counters"]
          when true then "with a counter on it"
          when false then "with no counters on it"
          when String then "with a #{@params["counters"]} counter on it"
          end
        end

        # The range bounds as numbers, computed once per query. Without a resolving context (a target
        # being chosen) the filter's source stands for "it".
        def resolved_ranges(engine, controller, source, ctx)
          return @ranges.transform_values { |range| range.transform_values(&:n) } unless @computed

          ctx ||= EffectContext.new(controller, source, source, [], [])
          @ranges.transform_values { |range| range.transform_values { it.value(engine, ctx) } }
        end

        def allowed?(engine, ref, controller, source, bounds)
          return false if @other && ref == source

          index = Filters.player_index(engine, ref)
          owner = index || engine.state.objects[ref]&.controller
          return false if @controller && (@controller == "you") != (owner == controller)
          return true if index

          object_allowed?(engine, ref, bounds)
        end

        def object_allowed?(engine, ref, bounds)
          obj = engine.object(ref)
          current = engine.chars(ref)
          facts = Facts.new(chars: current, counters: obj.counters, token: engine.token?(obj))
          return false unless characteristics_ok?(facts) && status_ok?(engine, obj)
          return false if @params["modified"] == true && !modified?(engine, obj)
          return false unless attached_ok?(engine, obj)

          bounds.all? { |key, range| in_range?(stat(engine, obj, current, key), range) }
        end

        # Types, subtypes, supertypes, token-ness, counters and printed mana value (CR 109.3, 122, 202.3).
        def characteristics_ok?(facts)
          c = facts.chars
          return false unless matches_types?(c.types) && (@lists["subtypes"].empty? || c.subtypes.intersect?(@lists["subtypes"]))
          return false if c.subtypes.intersect?(@lists["not_subtypes"]) || c.supertypes.intersect?(@lists["not_supertypes"])
          return false unless (@lists["supertypes"] - c.supertypes).empty?
          return false if @params["colors"] && !c.colors.intersect?(@params["colors"].map(&:to_sym)) # CR 105.2
          return false if !@params["token"].nil? && facts.token != @params["token"]
          return false if @params["modified"] == false && Counters.any?(facts.counters)

          counters_ok?(facts.counters)
        end

        def counters_ok?(counters)
          case (wanted = @params["counters"])
          when nil then true
          when true, false then Counters.any?(counters) == wanted
          else counters.fetch(wanted, 0).positive?
          end
        end

        def status_ok?(engine, obj)
          return false if !@params["attacking"].nil? && engine.attackers.key?(obj.id) != @params["attacking"]
          return false if !@params["blocking"].nil? && engine.state.blockers.key?(obj.id) != @params["blocking"]
          return false if !@params["transformed"].nil? && engine.transformed?(obj) != @params["transformed"] # CR 701.27h
          return false if !@params["prepared"].nil? && engine.prepared?(obj) != @params["prepared"] # CR 723.3a

          @params["tapped"].nil? || obj.tapped == @params["tapped"]
        end

        # "With a [subtype] attached to it": an Aura, Equipment or other permanent attached to it has one.
        def attached_ok?(engine, obj)
          wanted = @lists["attached_subtypes"]
          wanted.empty? || engine.attachments_of(obj.id).any? { engine.chars(it).subtypes.intersect?(wanted) }
        end

        # CR 700.9: a permanent is modified if it has counters, is equipped, or is enchanted by an Aura
        # its controller controls (Engine#modifying_attachment?, CR 301.5, 303.4).
        def modified?(engine, obj)
          Counters.any?(obj.counters) || engine.modifying_attachment?(obj)
        end

        # Current power/toughness (CR 208.3) and mana value (CR 202.3; 0 without a mana cost, 202.3a).
        def stat(engine, obj, current, key)
          case key
          when "power" then engine.power(obj)
          when "toughness" then engine.toughness(obj)
          else current.mana_cost&.mana_value.to_i
          end
        end

        def in_range?(value, range)
          (range["at_least"].nil? || value >= range["at_least"]) && (range["at_most"].nil? || value <= range["at_most"]) &&
            (range["equal"].nil? || value == range["equal"])
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
