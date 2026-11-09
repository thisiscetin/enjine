# frozen_string_literal: true

module Enjine
  module Mechanics
    # A number an effect uses, computed when the effect resolves (CR 608.2h):
    #   3                                             a fixed number
    #   "x"                                           the X announced for this spell or ability (CR 107.3)
    #   {"count": selector}                           how many objects/players match ({"count": {"result": 0}}:
    #                                                 how many the first effect moved or created, e.g. cards drawn)
    #   {"power": selector} / {"toughness": ...}      total power / toughness ("Picard's power": {"power": "self"})
    #   {"greatest_power": selector}                  the greatest power among them (0 for none)
    #   {"hand_size" | "life" | "graveyard_size": player selector}
    #   {"distinct_names": selector}                  how many different names they have (strange new worlds)
    #   {"distinct_types": selector}                  how many different creature types they have (CR 205.3m)
    #   {"counters": {"of": selector, "kind": name}}  counters on them (any kind without "kind", CR 122)
    #   {"life_gained_this_turn" | "life_lost_this_turn" | "dilemmas_this_turn" | "returned_this_turn"
    #    | "spells_cast_this_game": player selector}  this turn's (or game's) history, see Engine::TurnHistory
    #   {"spells_cast_this_turn": {"by": player selector, "matching": spell filter}}
    #   {"died_this_turn" | "entered_this_turn": {"each": filter, "controller": you|opponent|any}}
    #   {"this_way": n}                               how much effect n of this list changed (life it took)
    #   {"times": [a, b]} / {"plus": [a, b]} / {"divide": [a, b]}   arithmetic on amounts; division rounds down
    #                                                 (CR 107.1a). "-X" is {"times": ["x", -1]}.
    # A source that has left the battlefield is used as it last existed (CR 608.2h).
    class Amount
      SELECTOR_KINDS = %w[count power toughness greatest_power hand_size life graveyard_size distinct_names distinct_types
                          life_gained_this_turn life_lost_this_turn dilemmas_this_turn returned_this_turn
                          spells_cast_this_game].freeze
      ARITHMETIC = %w[times plus divide].freeze
      KINDS = (SELECTOR_KINDS + ARITHMETIC + %w[counters spells_cast_this_turn died_this_turn entered_this_turn this_way]).freeze
      # Player history counters: kind -> turn_log/game_log key.
      HISTORY = { "life_gained_this_turn" => "life_gained", "life_lost_this_turn" => "life_lost",
                  "dilemmas_this_turn" => "dilemmas", "returned_this_turn" => "returned" }.freeze

      # `min`: the smallest fixed number allowed (computed amounts may be anything their parts give).
      def self.build(data, errors, path, targets_count:, min: 0, results_count: 0)
        return Fixed.new(data) if data.is_a?(Integer) && data >= min
        return X::INSTANCE if data == "x"
        return Triggering::INSTANCE if data == { "triggering" => "amount" } # "that many" (CR 603.2)

        unless data.is_a?(Hash) && data.size == 1 && KINDS.include?(data.keys.first.to_s)
          errors << "#{path}: must be an integer >= #{min}, \"x\" or one of {#{KINDS.join("|")}: ...}"
          return Fixed.new(0)
        end
        kind, ref = data.first
        kind = kind.to_s
        context = { targets_count: targets_count, results_count: results_count }
        return Arithmetic.build(kind, ref, errors, "#{path}.#{kind}", **context) if ARITHMETIC.include?(kind)
        return Counters.build(ref, errors, "#{path}.#{kind}", **context) if kind == "counters"
        return SpellsCast.build(ref, errors, "#{path}.#{kind}", **context) if kind == "spells_cast_this_turn"
        return Departed.build(kind, ref, errors, "#{path}.#{kind}") if %w[died_this_turn entered_this_turn].include?(kind)
        return ThisWay.build(ref, errors, "#{path}.#{kind}", results_count) if kind == "this_way"

        new(kind, Selector.build(ref, errors, "#{path}.#{kind}", **context))
      end

      # Whether the amount can be computed during the layer pass (CR 613): it may count objects by
      # their types, but must not read power or toughness (that would depend on the pass's result).
      def self.layer_safe?(amount) = !amount.respond_to?(:reads_power?) || !amount.reads_power?

      def initialize(kind, selector)
        @kind = kind
        @selector = selector
        freeze
      end

      def reads_power? = %w[power toughness greatest_power].include?(@kind)

      def value(engine, ctx)
        refs = @selector.resolve(engine, ctx) # built without errors: a selector
        case @kind
        when "count" then refs.size
        when "power", "toughness" then refs.empty? ? Amount.last_known(engine, ctx, @selector, @kind) : stats(engine, refs).sum
        when "greatest_power" then stats(engine, refs).max.to_i
        when "distinct_names" then live(engine, refs).map { engine.chars(it).name }.uniq.size
        when "distinct_types" then live(engine, refs).flat_map { Amount.creature_types(engine.chars(it)) }.uniq.size
        else players(engine, refs).sum { player_value(engine, it) }
        end
      end

      def to_s = "the #{@kind.tr("_", " ")} of #{@selector}"

      # CR 205.3m: a creature's subtypes are creature types, except those that belong to its other card types.
      def self.creature_types(chars)
        chars.creature? ? chars.subtypes - Engine::SetMechanics::NON_CREATURE_SUBTYPES : []
      end

      # CR 608.2h: "its power" of a source that has left the battlefield is its last known value.
      def self.last_known(engine, ctx, selector, key)
        return 0 unless selector.kind == :self

        lki = engine.state.objects[ctx.object]&.memory&.[]("source_lki")
        lki ? lki[key].to_i : 0
      end

      private

      def live(engine, refs) = refs.select { engine.state.objects.key?(it) }
      def stats(engine, refs) = live(engine, refs).map { engine.public_send(@kind == "toughness" ? :toughness : :power, engine.object(it)) }
      def players(engine, refs) = refs.filter_map { Filters.player_index(engine, it) }

      def player_value(engine, index)
        case @kind
        when "hand_size" then engine.player(index).hand.size
        when "life" then engine.player(index).life
        when "graveyard_size" then engine.player(index).graveyard.size
        when "spells_cast_this_game" then engine.game_log(index).fetch("spells", 0)
        else engine.turn_log(index).fetch(HISTORY.fetch(@kind), 0)
        end
      end

      # X (CR 107.3a): the value announced for the resolving spell or ability. An enters-the-battlefield
      # trigger carries the X its permanent was cast with (CR 107.3m). 0 when none was announced.
      class X
        INSTANCE = new.freeze

        def value(engine, ctx) = engine.state.objects[ctx.object]&.x.to_i
        def to_s = "X"
      end

      # "That many": the number in the event that triggered the resolving ability (damage dealt, life
      # gained, counters put), see Triggers.event_facts. 0 outside a triggered ability.
      class Triggering
        INSTANCE = new.freeze

        def value(engine, ctx) = Selector.memory(engine, ctx).fetch("triggering", {})["amount"].to_i
        def to_s = "that many"
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

      # {"times" | "plus" | "divide": [a, b]}: a × b, a + b, or a ÷ b rounded down (CR 107.1a).
      class Arithmetic
        def self.build(kind, parts, errors, path, **context)
          unless parts.is_a?(Array) && parts.size == 2
            errors << "#{path}: must be a list of two amounts"
            return Fixed.new(0)
          end
          left, right = parts.each_with_index.map { |p, i| Amount.build(p, errors, "#{path}[#{i}]", min: -1000, **context) }
          errors << "#{path}[1]: must be a positive integer" if kind == "divide" && !(parts[1].is_a?(Integer) && parts[1].positive?)
          new(kind, left, right)
        end

        def initialize(kind, left, right)
          @kind = kind
          @left = left
          @right = right
          freeze
        end

        def reads_power? = [@left, @right].any? { !Amount.layer_safe?(it) }

        def value(engine, ctx)
          a = @left.value(engine, ctx)
          b = @right.value(engine, ctx)
          case @kind
          when "times" then a * b
          when "plus" then a + b
          else a.div(b) # b was checked positive
          end
        end

        def to_s = "#{@left} #{{ "times" => "×", "plus" => "+", "divide" => "÷" }[@kind]} #{@right}"
      end

      # {"this_way": n}: how much effect n of the same list changed, e.g. the life a lose_life effect took
      # (CR 608.2c).
      class ThisWay
        def self.build(index, errors, path, results_count)
          unless index.is_a?(Integer) && index >= 0 && index < results_count
            errors << "#{path}: must refer to one of the #{results_count} earlier effects"
          end
          new(index.to_i)
        end

        def initialize(index)
          @index = index
          freeze
        end

        def value(_engine, ctx) = ctx.amounts&.[](@index).to_i
        def to_s = "the amount from effect ##{@index + 1}"
      end

      # {"counters": {"of": selector, "kind": name}}: counters of one kind (or of every kind) on the
      # objects (CR 122). A source that has left the battlefield counts as it last existed (CR 608.2h).
      class Counters
        def self.build(data, errors, path, **context)
          data = data.is_a?(Hash) ? data.transform_keys(&:to_s) : {}
          Mechanics.check_keys(data, %w[of kind], errors, path)
          errors << "#{path}.of: required" unless data.key?("of")
          kind = data["kind"] && Mechanics::Counters.normalize(data["kind"])
          errors << "#{path}.kind: #{Mechanics::Counters.error(kind)}" if kind && Mechanics::Counters.error(kind)
          new(Selector.build(data.fetch("of", "self"), errors, "#{path}.of", **context), kind)
        end

        def initialize(selector, kind)
          @selector = selector
          @kind = kind
          freeze
        end

        def value(engine, ctx)
          refs = @selector.resolve(engine, ctx).select { engine.state.objects.key?(it) }
          counters = refs.map { engine.object(it).counters }
          if refs.empty? && @selector.kind == :self
            counters = [engine.state.objects[ctx.object]&.memory&.dig("source_lki",
                                                                      "counters") || {}]
          end
          counters.sum { @kind ? it.fetch(@kind, 0) : it.values.sum }
        end

        def to_s = "the number of #{"#{@kind} " if @kind}counters on #{@selector}"
      end

      # {"spells_cast_this_turn": {"by": "you", "matching": {"spell": {"not": ["creature"]}}}}: spells the
      # players cast this turn whose card types match (CR 601.2i; a cancelled cast never counts).
      class SpellsCast
        def self.build(data, errors, path, **context)
          data = data.is_a?(Hash) ? data.transform_keys(&:to_s) : {}
          Mechanics.check_keys(data, %w[by matching], errors, path)
          casters = Selector.build(data.fetch("by", "you"), errors, "#{path}.by", **context)
          filter = data["matching"] && Mechanics.build_entry(:filter, data["matching"], errors, "#{path}.matching")
          new(casters, filter)
        end

        def initialize(casters, filter)
          @by = casters
          @filter = filter
          freeze
        end

        def value(engine, ctx)
          players = @by.resolve(engine, ctx).filter_map { Filters.player_index(engine, it) }
          players.sum do |index|
            Array(engine.turn_log(index)["spells"]).count { @filter.nil? || Departed.facts_match?(engine, @filter, it, nil) }
          end
        end

        def to_s = "the number of #{@filter || "spell"}s cast this turn by #{@by}"
      end

      # {"died_this_turn" | "entered_this_turn": {"each": filter, "controller": ...}}: permanents that
      # died (CR 700.4) or entered this turn, matched by their card and the card types (and, for entering
      # ones, the subtypes, e.g. "an Equipment entered") they had then.
      class Departed
        def self.build(kind, data, errors, path)
          data = data.is_a?(Hash) ? data.transform_keys(&:to_s) : {}
          Mechanics.check_keys(data, %w[each controller], errors, path)
          filter = Mechanics.build_entry(:filter, data.fetch("each", "permanent"), errors, "#{path}.each")
          controller = data.fetch("controller", "any")
          errors << "#{path}.controller: must be one of you, opponent, any" unless %w[you opponent any].include?(controller)
          new(kind == "died_this_turn" ? "died" : "entered", filter, controller)
        end

        # Whether a card (with the card types it had, when given) matches a filter's characteristics.
        def self.facts_match?(engine, filter, card, types, subtypes = nil)
          defn = engine.catalog.fetch(card)
          chars = defn.printed_characteristics
          chars = chars.with(types: types.map(&:to_sym)) if types
          chars = chars.with(subtypes: subtypes.map(&:to_sym)) if subtypes
          filter.matches_facts?(Filters::Facts.new(chars: chars, counters: {}, token: defn.token?))
        end

        def initialize(key, filter, controller)
          @key = key
          @filter = filter
          @controller = controller
          freeze
        end

        def value(engine, ctx)
          engine.state.players.each_index.sum do |index|
            next 0 unless @controller == "any" || (@controller == "you") == (index == ctx.controller)

            Array(engine.turn_log(index)[@key]).count do |card, types, subtypes|
              @filter && Departed.facts_match?(engine, @filter, card, types, subtypes)
            end
          end
        end

        def to_s = "the number of #{@filter} that #{@key} this turn"
      end
    end

    # A yes/no test about the game, checked when an effect resolves (CR 608.2c) or, as an
    # intervening "if" (CR 603.4), both when a trigger condition is met and on resolution:
    #   {"amount": amount, "at_least": n, "at_most": n}   any Amount compared with bounds, e.g. total power
    #                                    of creatures you control N or more: {"amount": {"power": {"each":
    #                                    "creature", "controller": "you"}}, "at_least": 8}; "if you do" after a
    #                                    mandatory effect: {"amount": {"count": {"result": 0}}, "at_least": 1}
    #   {"controls": selector, "at_least": 3} / {"life": "you", ...} / {"hand_size": "you", ...}  (short forms)
    #   {"your_turn": true}
    #   {"was_cast": true}                          "if you cast it": the source permanent was cast (CR 400.7d)
    #   {"cast_with": "warp"} / {"cast_from": "graveyard"}   how this spell (or the spell this permanent was) was
    #                              cast; {"cast_with_this_turn": "warp"}: a spell was cast with it this turn
    #   {"targets": filter}        one of the chosen targets matches (e.g. "if it targets a tapped creature")
    #   {"attacked": true}         a creature is attacking you (CR 508.1b)
    #   {"source": filter}         the source is on the battlefield and matches ("if this isn't a creature":
    #                              {"not": {"source": "creature"}})
    #   {"attacked_this_turn": true}  the source attacked this turn
    #   {"nth_resolution": n}      this is the nth time this turn this ability resolves (CR 608.2)
    #   {"share_card_type": selector}  the referenced objects share a card type ("exiled_with": linked cards)
    #   {"not": condition}, {"all": [conditions]}, {"any": [conditions]}
    class Condition
      FLAGS = %w[your_turn was_cast attacked attacked_this_turn].freeze

      def self.build(data, errors, path, targets_count: 0, results_count: 0)
        unless data.is_a?(Hash)
          errors << "#{path}: must be a condition object"
          return nil
        end
        data = data.transform_keys(&:to_s)
        context = { targets_count: targets_count, results_count: results_count }
        if data.key?("not") then Not.new(build(data["not"], errors, "#{path}.not", **context))
        elsif data.key?("all") || data.key?("any")
          key = data.key?("all") ? "all" : "any"
          parts = Array(data[key]).each_with_index.map { |c, i| build(c, errors, "#{path}.#{key}[#{i}]", **context) }
          Many.new(key, parts.compact)
        elsif data.key?("kicked") then WasKicked.new(data["kicked"] != false)
        elsif (key = CastHow::KEYS.find { data.key?(it) }) then CastHow.build(key, data, errors, path) # keywords/alternative_costs.rb
        elsif data.key?("sacrificed") then Sacrificed.build(data, errors, path)
        elsif (flag = FLAGS.find { data.key?(it) }) then Flag.new(flag, data[flag] != false)
        elsif data.key?("targets") then Targets.build(data, errors, path)
        elsif data.key?("triggering") then TriggeringIs.build(data, errors, path)
        elsif data.key?("began_extra_turn") then BeganExtraTurn.new(data["began_extra_turn"] != false) # CR 500.7
        elsif data.key?("share_card_type") then ShareCardType.build(data, errors, path, targets_count) # effects/zones.rb
        elsif data.key?("source") then Source.build(data, errors, path)
        elsif data.key?("nth_resolution") then NthResolution.build(data, errors, path)
        else Compare.build(data, errors, path, **context)
        end
      end

      # An Amount compared with bounds: {"amount": amount, "at_least": n, "at_most": n}, or a short form
      # {"controls"|"life"|"hand_size": selector, ...}.
      class Compare
        SUBJECTS = { "controls" => "count", "life" => "life", "hand_size" => "hand_size" }.freeze

        def self.build(data, errors, path, targets_count:, results_count: 0)
          subject = (data.keys & (SUBJECTS.keys + ["amount"])).first
          unless subject
            errors << "#{path}: unknown condition (use amount, controls, life, hand_size, your_turn, was_cast, targets, " \
                      "attacked, source, attacked_this_turn, nth_resolution, kicked, sacrificed, cast_with, cast_from, " \
                      "cast_with_this_turn, not, all, any)"
            return nil
          end
          Mechanics.check_keys(data, [subject, "at_least", "at_most"], errors, path)
          raw = subject == "amount" ? data[subject] : { SUBJECTS[subject] => data[subject] }
          amount = Amount.build(raw, errors, "#{path}.#{subject}", targets_count: targets_count, results_count: results_count)
          bounds = %w[at_least at_most].to_h { [it, data[it]] }.compact
          errors << "#{path}: needs at_least and/or at_most" if bounds.empty?
          bounds.each { |k, v| errors << "#{path}.#{k}: must be an integer" unless v.is_a?(Integer) }
          new(amount, bounds["at_least"], bounds["at_most"])
        end

        attr_reader :amount

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

        def to_s = "#{@amount} is #{[@at_least && "at least #{@at_least}", @at_most && "at most #{@at_most}"].compact.join(" and ")}"
      end

      # A yes/no fact about the turn or the source.
      class Flag
        def initialize(flag, wanted)
          @flag = flag
          @wanted = wanted
          freeze
        end

        def true?(engine, ctx) = holds?(engine, ctx) == @wanted

        WORDS = { "your_turn" => ["it's your turn", "it's not your turn"], "was_cast" => ["it was cast", "it wasn't cast"],
                  "attacked" => ["a creature is attacking you", "no creature is attacking you"],
                  "attacked_this_turn" => ["it attacked this turn", "it didn't attack this turn"] }.freeze

        def to_s = WORDS.fetch(@flag)[@wanted ? 0 : 1]

        private

        def holds?(engine, ctx)
          case @flag
          when "your_turn" then engine.state.active == ctx.controller
          when "attacked" # a creature is attacking the controller, not a planeswalker they control (CR 508.1b)
            you = Filters.player_ref(engine, ctx.controller)
            engine.attackers.values.any? { it["target"] == you }
          when "attacked_this_turn" then engine.attacked_this_turn?(ctx.source)
          else was_cast?(engine, ctx)
          end
        end

        # "If you cast it": the source permanent entered as a resolving spell (CR 400.7d). Once the
        # source has left, its triggered ability remembers it (last known information, CR 603.4 / 608.2h).
        def was_cast?(engine, ctx)
          source = engine.state.objects[ctx.source]
          cast = source ? source.memory["cast"] : engine.state.objects[ctx.object]&.memory&.[]("source_cast")
          cast == true
        end
      end

      # One of the chosen targets matches a filter. Before targets are chosen (`ctx.targets` nil, as when
      # checking whether a cost reduction could apply) it counts as met.
      class Targets
        def self.build(data, errors, path)
          Mechanics.check_keys(data, %w[targets], errors, path)
          new(Mechanics.build_entry(:filter, data["targets"], errors, "#{path}.targets"))
        end

        def initialize(filter)
          @filter = filter
          freeze
        end

        def true?(engine, ctx)
          return true if ctx.targets.nil?

          ctx.targets.compact.any? { @filter&.match?(engine, it, ctx.controller) }
        end

        def to_s = "it targets a #{@filter.respond_to?(:primitive_name) ? @filter.primitive_name : @filter}"
      end

      # The source is on the battlefield and matches a filter, by its current characteristics.
      class Source
        def self.build(data, errors, path)
          Mechanics.check_keys(data, %w[source], errors, path)
          new(Mechanics.build_entry(:filter, data["source"], errors, "#{path}.source"))
        end

        def initialize(filter)
          @filter = filter
          freeze
        end

        def true?(engine, ctx)
          !@filter.nil? && engine.state.battlefield.include?(ctx.source) && @filter.match?(engine, ctx.source, ctx.controller)
        end

        def to_s = "it's a #{@filter}"
      end

      # The nth resolution of an ability this turn: the resolving ability (ctx.object)
      # has finished resolving n - 1 times this turn (Engine::TurnHistory counts completed resolutions).
      class NthResolution
        def self.build(data, errors, path)
          Mechanics.check_keys(data, %w[nth_resolution], errors, path)
          n = data["nth_resolution"]
          errors << "#{path}.nth_resolution: must be a positive integer" unless n.is_a?(Integer) && n.positive?
          new(n)
        end

        def initialize(nth)
          @nth = nth
          freeze
        end

        def true?(engine, ctx)
          obj = engine.state.objects[ctx.object]
          !obj.nil? && obj.ability? && engine.times_resolved(obj.source, obj.ability) + 1 == @nth
        end

        def to_s = "this is resolution number #{@nth} of this ability this turn"
      end

      # "If this spell was kicked" (CR 702.33d): the resolving spell (or the spell a permanent was) paid
      # its kicker cost. Recorded on the stack object as it became cast, and carried to the permanent it
      # becomes (CR 400.7d) and to that permanent's triggered abilities. While a trigger is being checked
      # (no ability object yet, CR 603.4) the source permanent answers.
      class WasKicked
        def initialize(wanted)
          @wanted = wanted
          freeze
        end

        def true?(engine, ctx)
          holder = engine.state.objects[ctx.object || ctx.source]
          (holder&.memory&.[]("kicked") == true) == @wanted
        end

        def to_s = @wanted ? "it was kicked" : "it wasn't kicked"
      end

      # "If you sacrificed a Klingon this way" (CR 608.2h): a permanent sacrificed to pay the resolving
      # spell's or ability's cost had these subtypes / card types as it last existed.
      #   {"sacrificed": {"subtypes": ["klingon"]}}   {"sacrificed": {"types": ["artifact"]}}
      class Sacrificed
        def self.build(data, errors, path)
          Mechanics.check_keys(data, %w[sacrificed], errors, path)
          spec = data["sacrificed"]
          ok = spec.is_a?(Hash) && !spec.empty? && (spec.keys - %w[types subtypes]).empty? &&
               spec.values.all? { it.is_a?(Array) && !it.empty? && it.all?(String) }
          errors << "#{path}.sacrificed: must be {\"types\": [...]} and/or {\"subtypes\": [...]}" unless ok
          new(ok ? spec : {})
        end

        def initialize(spec)
          @spec = spec
          freeze
        end

        def true?(engine, ctx)
          paid = engine.state.objects[ctx.object]&.paid || []
          paid.any? { |entry| entry["subtypes"] && @spec.all? { |key, wanted| entry[key].intersect?(wanted) } }
        end

        def to_s = "a sacrificed permanent was #{@spec.values.flatten.join(" or ")}"
      end

      # {"triggering": filter}: "if it's a Saga spell" — the card the trigger event was about matches a
      # filter on its card's characteristics (types, subtypes, ...), wherever it is now.
      class TriggeringIs
        def self.build(data, errors, path)
          Mechanics.check_keys(data, %w[triggering], errors, path)
          new(Mechanics.build_entry(:filter, data["triggering"], errors, "#{path}.triggering"))
        end

        def initialize(filter)
          @filter = filter
          freeze
        end

        def true?(engine, ctx)
          card = Selector.memory(engine, ctx).fetch("triggering", {})["card"]
          return false unless card && @filter

          defn = engine.catalog.fetch(card)
          @filter.matches_facts?(Filters::Facts.new(chars: defn.printed_characteristics, counters: {}, token: defn.token?))
        end

        def to_s = "it's a #{@filter.respond_to?(:primitive_name) ? @filter.primitive_name.tr("_", " ") : @filter}"
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
