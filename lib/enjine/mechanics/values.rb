# frozen_string_literal: true

module Enjine
  module Mechanics
    # A number an effect uses, computed when the effect resolves (CR 608.2h):
    #   3                                             a fixed number
    #   {"count": {"each": "creature", "controller": "you"}}   how many objects/players match
    #   {"power": "self"} / {"power": {"target": 0}}   a creature's power
    #   {"toughness": ...}                             a creature's toughness
    #   {"hand_size": "you"}                           cards in a player's hand
    #   {"life": "you"}                                a player's life total
    class Amount
      KINDS = %w[count power toughness hand_size life].freeze

      def self.build(data, errors, path, targets_count:, min: 0)
        return Fixed.new(data) if data.is_a?(Integer) && data >= min

        unless data.is_a?(Hash) && data.size == 1 && KINDS.include?(data.keys.first.to_s)
          errors << "#{path}: must be an integer >= #{min} or one of {#{KINDS.join("|")}: selector}"
          return Fixed.new(0)
        end
        kind, ref = data.first
        selector = Selector.build(ref, errors, "#{path}.#{kind}", targets_count: targets_count)
        new(kind.to_s, selector)
      end

      def initialize(kind, selector)
        @kind = kind
        @selector = selector
        freeze
      end

      def value(engine, ctx)
        refs = @selector ? @selector.resolve(engine, ctx) : []
        case @kind
        when "count" then refs.size
        when "power" then refs.sum { object_stat(engine, it, :power) }
        when "toughness" then refs.sum { object_stat(engine, it, :toughness) }
        when "hand_size" then refs.sum { player_of(engine, it)&.hand&.size.to_i }
        when "life" then refs.sum { player_of(engine, it)&.life.to_i }
        end
      end

      def to_s = "the #{@kind.tr("_", " ")} of #{@selector}"

      private

      def object_stat(engine, ref, stat)
        engine.state.objects.key?(ref) ? engine.public_send(stat, engine.object(ref)) : 0
      end

      def player_of(engine, ref)
        index = Filters.player_index(engine, ref)
        index && engine.player(index)
      end

      # A fixed number.
      class Fixed
        attr_reader :n

        def initialize(number)
          @n = number
          freeze
        end

        def value(_engine, _ctx) = @n
        def to_s = @n.to_s
      end
    end

    # A yes/no test about the game, checked when an effect resolves (CR 608.2c) or, as an
    # intervening "if" (CR 603.4), both when a trigger condition is met and on resolution:
    #   {"controls": {"each": "creature", "controller": "you"}, "at_least": 3}
    #   {"life": "you", "at_least": 10} / {"life": "you", "at_most": 5}
    #   {"hand_size": "you", "at_most": 0}
    #   {"your_turn": true}
    #   {"not": condition}, {"all": [conditions]}, {"any": [conditions]}
    class Condition
      def self.build(data, errors, path, targets_count: 0)
        unless data.is_a?(Hash)
          errors << "#{path}: must be a condition object"
          return nil
        end
        data = data.transform_keys(&:to_s)
        if data.key?("not") then Not.new(build(data["not"], errors, "#{path}.not", targets_count: targets_count))
        elsif data.key?("all") || data.key?("any")
          key = data.key?("all") ? "all" : "any"
          parts = Array(data[key]).each_with_index.map { |c, i| build(c, errors, "#{path}.#{key}[#{i}]", targets_count: targets_count) }
          Many.new(key, parts.compact)
        elsif data.key?("your_turn") then YourTurn.new(data["your_turn"] != false)
        else Compare.build(data, errors, path, targets_count)
        end
      end

      # A count/number compared with bounds: {"controls"|"life"|"hand_size": ..., "at_least": n, "at_most": n}.
      class Compare
        SUBJECTS = { "controls" => "count", "life" => "life", "hand_size" => "hand_size" }.freeze

        def self.build(data, errors, path, targets_count)
          subject = (data.keys & SUBJECTS.keys).first
          unless subject
            errors << "#{path}: unknown condition (use controls, life, hand_size, your_turn, not, all, any)"
            return nil
          end
          Mechanics.check_keys(data, [subject, "at_least", "at_most"], errors, path)
          amount = Amount.build({ SUBJECTS[subject] => data[subject] }, errors, "#{path}.#{subject}", targets_count: targets_count)
          bounds = %w[at_least at_most].to_h { [it, data[it]] }.compact
          errors << "#{path}: needs at_least and/or at_most" if bounds.empty?
          bounds.each { |k, v| errors << "#{path}.#{k}: must be an integer" unless v.is_a?(Integer) }
          new(amount, bounds["at_least"], bounds["at_most"])
        end

        def initialize(amount, at_least, at_most)
          @amount = amount
          @at_least = at_least
          @at_most = at_most
          freeze
        end

        def true?(engine, ctx)
          n = @amount.value(engine, ctx)
          (@at_least.nil? || n >= @at_least) && (@at_most.nil? || n <= @at_most)
        end

        def to_s
          "#{@amount} is #{["at least #{@at_least}", @at_most && "at most #{@at_most}"].compact.join(" and ")}"
            .sub("at least  and ", "")
        end
      end

      # It's the controller's turn.
      class YourTurn
        def initialize(wanted)
          @wanted = wanted
          freeze
        end

        def true?(engine, ctx) = (engine.state.active == ctx.controller) == @wanted
        def to_s = @wanted ? "it's your turn" : "it's not your turn"
      end

      # Negation.
      class Not
        def initialize(inner)
          @inner = inner
          freeze
        end

        def true?(engine, ctx) = !@inner&.true?(engine, ctx)
        def to_s = "not (#{@inner})"
      end

      # all / any.
      class Many
        def initialize(mode, parts)
          @mode = mode
          @parts = parts
          freeze
        end

        def true?(engine, ctx) = @mode == "all" ? @parts.all? { it.true?(engine, ctx) } : @parts.any? { it.true?(engine, ctx) }
        def to_s = @parts.join(@mode == "all" ? " and " : " or ")
      end
    end
  end
end
