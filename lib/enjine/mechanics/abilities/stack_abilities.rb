# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # One target of a spell or ability with options (CR 601.2c, 115.1d): {"filter": f, "optional": true}
      # is "up to one target f" (the player may choose none), and "distinct_from": [i, ...] keeps it
      # different from earlier targets of the same "target" word ("one or two target creatures").
      # "shares_type_with": i keeps it sharing a card type with earlier target i ("two target permanents that
      # share a card type", CR 115.1, 205.2a).
      # "count" is a variable number of targets for one "target" word (CR 601.2c, 115.3; Engine::TargetCounts):
      # an amount ("x": "X target creatures", 2: "two target creatures"; with "optional": "up to") or "any"
      # ("any number of target ..."). Its slot then holds a list, and {"target": n} means each of them.
      class TargetSpec
        KEYS = %w[filter optional distinct_from count shares_type_with].freeze

        attr_reader :filter, :distinct_from, :count, :shares_type_with

        def self.build(entry, errors, path, index)
          Mechanics.check_keys(entry, KEYS, errors, path)
          filter = Mechanics.build_entry(:filter, entry["filter"], errors, "#{path}.filter")
          distinct = Array(entry["distinct_from"])
          errors << "#{path}.distinct_from: must list earlier targets" unless distinct.all? { it.is_a?(Integer) && it >= 0 && it < index }
          optional = Mechanics.flag_param(entry, :optional, errors, path)
          shares = entry["shares_type_with"]
          unless shares.nil? || (shares.is_a?(Integer) && shares >= 0 && shares < index)
            errors << "#{path}.shares_type_with: must name an earlier target"
          end
          filter && new(filter, optional, distinct, build_count(entry, errors, path), shares_type_with: shares)
        end

        def self.build_count(entry, errors, path)
          return nil unless entry.key?("count")
          return :any if entry["count"] == "any"

          Amount.build(entry["count"], errors, "#{path}.count", targets_count: 0, min: 1)
        end

        def initialize(filter, optional, distinct_from, count = nil, shares_type_with: nil)
          @filter = filter
          @optional = optional
          @distinct_from = distinct_from.freeze
          @count = count
          @shares_type_with = shares_type_with
          freeze
        end

        def optional? = @optional
        def counted? = !@count.nil?

        # [min, max] objects to choose (max nil: any number).
        def count_range(engine, ctx)
          return [0, nil] if @count == :any

          n = [@count.value(engine, ctx), 0].max
          [optional? ? 0 : n, n]
        end

        def candidates_for(...) = filter.candidates_for(...)
        def match_for?(...) = filter.match_for?(...)
        def candidates(...) = filter.candidates(...)
        def match?(...) = filter.match?(...)
        def primitive_name = filter.primitive_name
        def to_s = "#{count_words}#{filter.is_a?(Class) ? primitive_name : filter}"

        private

        def count_words
          return "any number of " if @count == :any
          return "#{"up to " if optional?}#{@count.is_a?(Amount::Fixed) ? @count.n : "X"} " if counted?

          "up to one " if optional?
        end
      end

      # Shared parsing for abilities that use the stack: targets and effects.
      class StackAbility < Primitive
        # One mode of a modal ability ("Choose one —", CR 700.2): its own targets and effects, and for a spell
        # the additional mana cost paid when it's chosen (tiered, CR 702.183a), or nil.
        Mode = Data.define(:targets, :effects, :cost) do
          def initialize(targets:, effects:, cost: nil) = super
        end

        # Optional parts of the body: how many modes may be chosen and when more may (CR 700.2), modes
        # not chosen before for the same object, targets of a kicked spell (CR 702.33g), and an amount
        # divided among the targets as it's cast (CR 601.2d).
        Extras = Data.define(:choose_max, :choose_if, :unchosen, :kicked_targets, :divide) do
          def initialize(choose_max: nil, choose_if: nil, unchosen: false, kicked_targets: nil, divide: nil) = super
        end
        NO_EXTRAS = Extras.new

        attr_reader :targets, :effects, :costs, :modes, :choose, :extras

        # Parses either plain targets/effects or {"choose": n, "modes": [{targets, effects}, ...]}.
        # `choose` may be {"min": a, "max": b} ("choose one or more"), and `choose_if` {"if": condition,
        # "choose": ...} replaces it while the condition holds.
        # `mode_costs`: modes may have a `cost` (a spell's tiered modes, CR 702.183a).
        def self.parse_body(params, errors, path, mode_costs: false)
          modes_data = Mechanics.fetch_param(params, :modes)
          extras = parse_extras(params, errors, path)
          if modes_data.nil?
            targets = parse_targets(params, errors, path)
            check_kicked_targets(extras, targets, errors, path)
            check_divide(extras, targets, errors, path)
            return { targets: targets, effects: parse_effects(params, errors, path, targets.size), modes: [].freeze,
                     choose: 0, extras: extras }
          end
          unless modes_data.is_a?(Array) && modes_data.size >= 2
            errors << "#{path}.modes: must be a list of at least two modes"
            modes_data = []
          end
          errors << "#{path}: use either modes or targets/effects, not both" if params.key?("targets") || params.key?("effects")
          modes = modes_data.each_with_index.map do |mode, i|
            mode_path = "#{path}.modes[#{i}]"
            mode = mode.is_a?(Hash) ? mode.transform_keys(&:to_s) : {}
            Mechanics.check_keys(mode, %w[targets effects] + (mode_costs ? %w[cost] : []), errors, mode_path)
            mode_targets = parse_targets(mode, errors, mode_path)
            cost = mode.key?("cost") ? Mana.parse_cost(mode["cost"], errors, "#{mode_path}.cost") : nil
            Mode.new(targets: mode_targets, effects: parse_effects(mode, errors, mode_path, mode_targets.size), cost: cost)
          end
          min, max = parse_choose(Mechanics.fetch_param(params, :choose), errors, "#{path}.choose", modes.size)
          extras = extras.with(choose_max: max) if max != min
          { targets: [].freeze, effects: [].freeze, modes: modes.freeze, choose: min, extras: extras }
        end

        BODY_KEYS = %w[targets effects modes choose choose_if unchosen kicked_targets divide].freeze

        # [min, max] modes from 1, n or {"min": a, "max": b}.
        def self.parse_choose(raw, errors, path, mode_count)
          raw = 1 if raw.nil?
          min, max = raw.is_a?(Hash) ? [raw["min"], raw["max"]] : [raw, raw]
          unless min.is_a?(Integer) && max.is_a?(Integer) && min >= 1 && max >= min && (raw.is_a?(Integer) || raw.size == 2)
            errors << "#{path}: must be an integer >= 1 or {\"min\": a, \"max\": b}"
            return [1, 1]
          end
          errors << "#{path}: can't exceed the number of modes" if max > mode_count && mode_count.positive?
          [min, max]
        end

        def self.parse_extras(params, errors, path)
          extras = {}
          if (raw = Mechanics.fetch_param(params, :choose_if))
            extras[:choose_if] = parse_choose_if(raw, errors, "#{path}.choose_if", params)
          end
          extras[:unchosen] = Mechanics.flag_param(params, :unchosen, errors, path)
          raw = Mechanics.fetch_param(params, :kicked_targets)
          extras[:kicked_targets] = parse_targets(params, errors, path, key: :kicked_targets) unless raw.nil?
          extras[:divide] = Amount.build(params["divide"], errors, "#{path}.divide", targets_count: 0, min: 1) if params.key?("divide")
          Extras.new(**extras)
        end

        def self.parse_choose_if(raw, errors, path, params)
          unless raw.is_a?(Hash) && raw.key?("if") && raw.key?("choose")
            errors << "#{path}: must be {\"if\": condition, \"choose\": n or {\"min\": a, \"max\": b}}"
            return nil
          end
          Mechanics.check_keys(raw, %w[if choose], errors, path)
          count = Array(Mechanics.fetch_param(params, :modes)).size
          [Condition.build(raw["if"], errors, "#{path}.if"), *parse_choose(raw["choose"], errors, "#{path}.choose", count)]
        end

        # CR 601.2d: each target gets at least one, so there must be a first, required target. A counted one
        # ("one, two, or three targets": count 3, optional) needs at least one target when dividing.
        def self.check_divide(extras, targets, errors, path)
          first = targets.first
          return if extras.divide.nil? || (first && (!first.respond_to?(:optional?) || !first.optional? || first.counted?))

          errors << "#{path}.divide: needs a first target that isn't optional"
        end

        # CR 702.33g: the kicked spell's targets replace the normal ones, one for one.
        def self.check_kicked_targets(extras, targets, errors, path)
          return if extras.kicked_targets.nil? || extras.kicked_targets.size == targets.size

          errors << "#{path}.kicked_targets: must list as many targets as targets"
        end

        def self.parse_targets(params, errors, path, key: :targets)
          Mechanics.list_param(params, key, errors, path).each_with_index.filter_map do |entry, i|
            entry_path = "#{path}.#{key}[#{i}]"
            if entry.is_a?(Hash) && entry.key?("filter")
              TargetSpec.build(entry, errors, entry_path, i)
            else
              Mechanics.build_entry(:filter, entry, errors, entry_path)
            end
          end.freeze
        end

        # Effect i may name the results of effects 0...i ({"result": n}). A nested list (`results_count`
        # given) sees only its parent's earlier results.
        def self.parse_effects(params, errors, path, targets_count, key: :effects, results_count: nil)
          list = Mechanics.list_param(params, key, errors, path)
          list.each_with_index.filter_map do |entry, i|
            Mechanics.build_entry(:effect, entry, errors, "#{path}.#{key}[#{i}]", targets_count: targets_count,
                                                                                  results_count: results_count || i)
          end.freeze
        end

        def self.parse_costs(params, errors, path)
          Mechanics.list_param(params, :cost, errors, path).each_with_index.filter_map do |entry, i|
            Mechanics.build_entry(:cost, entry, errors, "#{path}.cost[#{i}]")
          end.freeze
        end

        def initialize(targets:, effects:, costs: [].freeze, modes: [].freeze, choose: 0, extras: NO_EXTRAS)
          super()
          @targets = targets
          @effects = effects
          @costs = costs
          @modes = modes
          @choose = choose
          @extras = extras
          freeze
        end

        def modal? = !modes.empty?
        def try_effects = effects

        # The additional mana costs of the chosen modes (a spell's tiered modes, CR 702.183a).
        def mode_costs(chosen) = modal? ? chosen.filter_map { modes[it].cost } : []

        # Targets in order for the chosen modes (or the ability's own targets); a kicked spell uses its
        # kicked targets (CR 702.33g).
        def targets_for(chosen, kicked: false)
          return chosen.sort.flat_map { modes[it].targets } if modal?

          kicked && extras.kicked_targets ? extras.kicked_targets : targets
        end

        # [min, max] modes to choose now (CR 700.2): `choose_if` applies while its condition holds.
        def choice_range(engine, ctx)
          cond, min, max = extras.choose_if
          return [min, max] if cond&.true?(engine, ctx)

          [choose, extras.choose_max || choose]
        end

        # [[effect, target offset, target count, index in its list], ...] in resolution order (modes in
        # printed order, CR 700.2a). The index lets {"result": n} find results within the same list.
        def effect_plan(chosen)
          return effects.each_with_index.map { |e, i| [e, 0, targets.size, i] } unless modal?

          offset = 0
          chosen.sort.flat_map do |index|
            mode = modes[index]
            plan = mode.effects.each_with_index.map { |e, i| [e, offset, mode.targets.size, i] }
            offset += mode.targets.size
            plan
          end
        end

        def mana_ability? = false
        def loyalty_cost = nil

        # The zone the ability functions in (CR 113.6): a cost that moves the card out of a zone
        # (e.g. discarding it from hand) says where it can be activated (CR 113.6m).
        def zone = costs.find { it.respond_to?(:zone) }&.zone || :battlefield

        def effects_text
          return effects.join("; ") unless modal?

          "choose #{choose} — " + modes.map { it.effects.join("; ") }.join(" • ")
        end

        def to_s = costs.empty? ? effects_text : "#{costs.join(", ")}: #{effects_text}"
        def sorcery_speed? = false
        def allowed_types = nil

        # Total mana cost to pay during activation.
        def mana_cost
          Mana.sum_costs(costs.select(&:mana?).map(&:mana_cost))
        end
      end

      # The spell ability of an instant or sorcery (CR 113.3a): what happens when it resolves.
      class SpellAbility < StackAbility
        primitive :ability, :spell,
                  description: "The spell ability of an instant or sorcery: its targets are chosen while casting " \
                               "and its effects happen in order when it resolves. If every target is illegal on " \
                               "resolution, it doesn't resolve. A mode of a modal spell may have a `cost`: a mana " \
                               "cost paid in addition when that mode is chosen (tiered: \"Choose one additional " \
                               "cost\").",
                  rules: %w[113.3a 601.2c 608.2b 608.2c 702.183a 601.2f],
                  params: { "targets" => "list of target filters", "effects" => "list of effects",
                            "modes" => "list of {targets, effects, cost} (with `choose`)" },
                  example: { "spell" => { "targets" => ["any_target"],
                                          "effects" => [{ "deal_damage" => { "amount" => 3, "to" => { "target" => 0 } } }] } }

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, BODY_KEYS, errors, path)
          new(**parse_body(params, errors, path, mode_costs: true))
        end

        def kind = :spell
        def allowed_types = %i[instant sorcery]
      end

      # A non-mana activated ability "[Cost]: [Effect]" (CR 602).
      class ActivatedAbility < StackAbility
        primitive :ability, :activated,
                  description: "An activated ability: announce it, choose targets, pay its costs, then it goes on " \
                               "the stack. `timing: \"sorcery\"` restricts it to sorcery speed, `\"your_turn\"` to your " \
                               "turns; `limit: \"once_each_turn\"` to one activation per turn, `\"once\"` to one " \
                               "activation for as long as the object exists; `only_if` to when a " \
                               "condition holds. `zone` (\"exile\", \"graveyard\" or \"hand\") makes it function only " \
                               "while its card is in that zone (\"activate only if this card is exiled\"). `exhaust: " \
                               "true` makes it an exhaust ability: it can be activated only once (CR 702.177a). " \
                               "`power_up: true` makes it a power-up ability: activate only once, and if the " \
                               "permanent entered this turn its cost is reduced by the permanent's mana cost " \
                               "(CR 702.193). `boast: true`: activate only if this creature attacked this turn and " \
                               "only once each turn (CR 702.142a).",
                  rules: %w[602.1 602.2 602.5b 602.5d 702.177a 702.193a 702.193b 702.142a],
                  params: { "cost" => "list of costs (tap, {\"mana\": \"{1}\"}, {\"mana\": \"{X}\"})",
                            "targets" => "list of target filters", "effects" => "list of effects",
                            "timing" => "\"instant\" (default), \"sorcery\" or \"your_turn\"",
                            "limit" => "\"once_each_turn\" | \"once\" (CR 602.5b)", "only_if" => "condition (\"activate only if ...\")",
                            "exhaust" => "true: \"Exhaust — [cost]: [effect]\", activate only once (CR 702.177a)",
                            "power_up" => "true: \"Power-up — [cost]: [effect]\" (CR 702.193a)",
                            "boast" => "true: \"Boast — [cost]: [effect]\" (CR 702.142a)",
                            "zone" => "\"exile\" | \"graveyard\" | \"hand\" (CR 113.6b; default: the battlefield, or the " \
                                      "zone a cost moves the card from)",
                            "cost_reduction" => "{\"amount\": amount, \"if\": condition}: \"this ability costs {N} less " \
                                                "to activate\" (CR 601.2f, 602.2b)" },
                  example: { "activated" => { "cost" => ["tap"], "targets" => ["any_target"],
                                              "effects" => [{ "deal_damage" => { "amount" => 1, "to" => { "target" => 0 } } }] } }

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost timing cost_reduction limit only_if zone exhaust power_up boast] + BODY_KEYS, errors, path)
          timing = Mechanics.fetch_param(params, :timing) || "instant"
          errors << "#{path}.timing: must be one of #{TIMINGS.join(", ")}" unless TIMINGS.include?(timing)
          restriction = parse_restriction(params, errors, path)
          costs = parse_costs(params, errors, path)
          errors << "#{path}.cost: must be a non-empty list" if costs.empty? && errors.none? { it.start_with?("#{path}.cost") }
          raw = Mechanics.fetch_param(params, :cost_reduction)
          reduction = raw && Reduction.build(raw, errors, "#{path}.cost_reduction")
          check_cost_zones(costs, errors, path)
          zone = parse_zone(params, costs, errors, path)
          body = parse_body(params, errors, path)
          check_mana_ability(body, errors, path)
          new(**body, costs: costs, sorcery: timing == "sorcery", cost_reduction: reduction, zone: zone,
                      restriction: restriction.merge(your_turn: timing == "your_turn"))
        end

        ZONES = %w[exile graveyard hand].freeze

        # CR 113.6b: "activate only if this card is exiled" (an ability that functions only from a zone).
        def self.parse_zone(params, costs, errors, path)
          zone = Mechanics.fetch_param(params, :zone) or return nil
          return (errors << "#{path}.zone: must be one of #{ZONES.join(", ")}") && nil unless ZONES.include?(zone)

          own = costs.filter_map { it.zone if it.respond_to?(:zone) }.first
          errors << "#{path}.zone: its costs are paid from the #{own}" if own && own.to_s != zone
          if costs.any? { it.is_a?(Costs::Tap) || Costs::LEAVING_SELF.include?(it.class) }
            errors << "#{path}.zone: an ability of a card in the #{zone} can't tap, sacrifice or exile it"
          end
          zone.to_sym
        end

        TIMINGS = %w[instant sorcery your_turn].freeze
        LIMITS = { "once_each_turn" => 1, "once" => nil }.freeze

        # CR 602.5b: "Activate only once each turn" and "Activate only if [condition]".
        def self.parse_restriction(params, errors, path)
          limit = Mechanics.fetch_param(params, :limit)
          errors << "#{path}.limit: must be one of #{LIMITS.keys.join(", ")}" unless limit.nil? || LIMITS.key?(limit)
          raw = Mechanics.fetch_param(params, :only_if)
          flags = %i[exhaust power_up boast].to_h { [it, Mechanics.flag_param(params, it, errors, path)] }
          errors << "#{path}: exhaust and power_up can't be used together" if flags[:exhaust] && flags[:power_up]
          errors << "#{path}.boast: can't be combined with limit" if flags[:boast] && limit
          { per_turn: flags[:boast] ? 1 : LIMITS[limit], only_if: raw && Condition.build(raw, errors, "#{path}.only_if"),
            once: limit == "once", **flags }
        end

        # CR 605.1a: an activated ability without targets that could add mana is a mana ability,
        # which doesn't use the stack.
        def self.check_mana_ability(body, errors, path)
          plans = body[:modes].empty? ? [body] : body[:modes].map(&:to_h)
          return unless plans.any? { it[:targets].empty? && it[:effects].any?(Effects::AddMana) }

          errors << "#{path}: an activated ability without targets that adds mana is a mana ability (CR 605.1a); " \
                    "use a \"mana\" ability"
        end

        # CR 113.6m: an ability can't both function from the hand (or graveyard) and tap or sacrifice its
        # permanent, nor function from two zones.
        def self.check_cost_zones(costs, errors, path)
          zones = costs.filter_map { it.zone if it.respond_to?(:zone) }.uniq
          errors << "#{path}.cost: costs can't be paid from both #{zones.join(" and ")}" if zones.size > 1
          return if zones.empty? || costs.none? { it.is_a?(Costs::Tap) || Costs::LEAVING_SELF.include?(it.class) }

          errors << "#{path}.cost: a cost paid from the #{zones.first} can't be combined with tap, sacrifice or exile"
        end

        attr_reader :cost_reduction

        def initialize(sorcery:, cost_reduction: nil, restriction: {}, zone: nil, **)
          @sorcery = sorcery
          @cost_reduction = cost_reduction
          @restriction = restriction
          @zone = zone
          super(**)
        end

        def kind = :activated
        def zone = @zone || super
        def sorcery_speed? = @sorcery

        # How many times it may be activated each turn (nil: no limit, CR 602.5b).
        def per_turn = @restriction[:per_turn]

        # An exhaust ability: "Activate only once" (CR 702.177a), see Engine::CastChoices#activation_allowed?.
        def exhaust? = @restriction[:exhaust] == true

        # A power-up ability (CR 702.193a): activate only once; cheaper the turn its permanent entered
        # (Keywords::PowerUp).
        def power_up? = @restriction[:power_up] == true

        # A boast ability (CR 702.142a): only if this creature attacked this turn, and only once each turn.
        def boast? = @restriction[:boast] == true

        # "Activate only once" for as long as the object exists (CR 602.5b, per object, CR 400.7): exhaust,
        # power-up, or `limit: "once"`.
        def once? = exhaust? || power_up? || @restriction[:once] == true

        KEYWORD_WORDS = { exhaust?: "Exhaust", power_up?: "Power-up", boast?: "Boast" }.freeze

        def to_s
          word = KEYWORD_WORDS.find { |flag, _| public_send(flag) }&.last
          text = word ? "#{word} — #{super}" : super
          @restriction[:once] ? "#{text} (activate only once)" : text
        end

        # CR 602.5b: restrictions on when it may be activated, besides timing and costs.
        def restriction_met?(engine, index, source)
          return false if boast? && !engine.attacked_this_turn?(source) # CR 702.142a
          return false if @restriction[:your_turn] && engine.state.active != index
          return false if @restriction[:only_if] && !@restriction[:only_if].true?(engine, EffectContext.new(index, source, nil, nil))

          true
        end
      end

      # A triggered ability "When/Whenever/At [trigger], [effect]" (CR 603).
      class TriggeredAbility < StackAbility
        primitive :ability, :triggered,
                  description: "A triggered ability: when its trigger condition happens, it is put on the stack the " \
                               "next time a player would receive priority (in APNAP order), with targets chosen then.",
                  rules: %w[603.2 603.3 603.3b 603.3d],
                  params: { "when" => "a trigger condition, e.g. {\"enters\": {}}", "targets" => "list of target filters",
                            "effects" => "list of effects",
                            "if" => "condition: an intervening \"if\", checked when it triggers and on resolution (CR 603.4)",
                            "while" => "condition checked only when it triggers (\"whenever you attack while ...\", CR 603.2)",
                            "limit" => "\"once_each_turn\": it triggers at most once each turn (per object)",
                            "zone" => "\"graveyard\": the ability functions only while its card is in a graveyard (CR 113.6k)" },
                  example: { "triggered" => { "when" => { "enters" => {} }, "effects" => [{ "draw" => { "amount" => 1 } }] } }

        attr_reader :trigger, :condition, :while_condition, :limit

        LIMITS = %w[once_each_turn].freeze
        ZONES = %w[battlefield graveyard].freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[when if while limit zone] + BODY_KEYS, errors, path)
          raw = Mechanics.fetch_param(params, :when)
          trigger = raw.nil? ? ((errors << "#{path}.when: required") && nil) : Mechanics.build_entry(:trigger, raw, errors, "#{path}.when")
          raw_if = Mechanics.fetch_param(params, :if)
          condition = raw_if && Condition.build(raw_if, errors, "#{path}.if")
          raw_while = Mechanics.fetch_param(params, :while)
          during = raw_while && Condition.build(raw_while, errors, "#{path}.while")
          limit = Mechanics.fetch_param(params, :limit)
          errors << "#{path}.limit: must be one of #{LIMITS.join(", ")}" unless limit.nil? || LIMITS.include?(limit)
          zone = Mechanics.fetch_param(params, :zone) || "battlefield"
          errors << "#{path}.zone: must be one of #{ZONES.join(", ")}" unless ZONES.include?(zone)
          new(**parse_body(params, errors, path), trigger: trigger, condition: condition, while_condition: during,
                                                  limit: limit, zone: zone.to_sym)
        end

        def initialize(trigger:, condition: nil, while_condition: nil, limit: nil, zone: :battlefield, **)
          @trigger = trigger
          @condition = condition
          @while_condition = while_condition
          @limit = limit
          @zone = zone
          super(**)
        end

        # CR 113.6k: a trigger condition that can't trigger from the battlefield functions where it can.
        attr_reader :zone

        # CR 603.4: an intervening "if" must be true when the trigger event happens and on resolution.
        # A "while" condition is part of the trigger event (CR 603.2): only checked as it triggers, which is
        # when no resolving `object` is given.
        # `facts`: the trigger event being checked (no ability object exists yet), see Selector.memory.
        def condition_met?(engine, controller, source, object = nil, facts: nil)
          ctx = EffectContext.new(controller, source, object, [], nil, nil, facts && { "triggering" => facts })
          return false if object.nil? && while_condition && !while_condition.true?(engine, ctx)

          condition.nil? || condition.true?(engine, ctx)
        end

        def kind = :triggered

        def to_s
          "#{trigger}#{" while #{while_condition}" if while_condition}, #{"if #{condition}, " if condition}#{effects_text}" \
            "#{" (only once each turn)" if limit}#{" (from a graveyard)" if zone == :graveyard}"
        end
      end

      # A planeswalker loyalty ability "+N: ..." / "-N: ..." (CR 606).
      class LoyaltyAbility < StackAbility
        primitive :ability, :loyalty,
                  description: "A loyalty ability. Its cost adds (positive) or removes (negative) loyalty counters " \
                               "and is paid on activation. Sorcery speed, and only one loyalty ability per " \
                               "planeswalker per turn.",
                  rules: %w[606.3 606.4 606.5 602.2b],
                  params: { "cost" => "integer, e.g. 1 for +1 or -2; or \"-X\" (X is announced, at most its loyalty)",
                            "targets" => "list of target filters",
                            "effects" => "list of effects" },
                  example: { "loyalty" => { "cost" => -3, "targets" => ["creature"],
                                            "effects" => [{ "deal_damage" => { "amount" => 3, "to" => { "target" => 0 } } }] } }

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost] + BODY_KEYS, errors, path)
          cost = Mechanics.fetch_param(params, :cost)
          errors << "#{path}.cost: must be an integer loyalty change or \"-X\"" unless cost.is_a?(Integer) || cost == "-X"
          new(**parse_body(params, errors, path), loyalty: cost == "-X" ? cost : cost.to_i)
        end

        def initialize(loyalty:, **)
          @loyalty = loyalty
          super(**)
        end

        def kind = :loyalty
        def loyalty? = true
        # The fixed loyalty change; a "-X" ability's is chosen as it's activated (CR 107.3, 601.2b), so it's 0 here.
        def loyalty_cost = x_loyalty? ? 0 : @loyalty
        def x_loyalty? = @loyalty == "-X"
        def sorcery_speed? = true
        def allowed_types = [:planeswalker]

        def to_s = "#{"+" if !x_loyalty? && @loyalty.positive?}#{@loyalty}: #{effects_text}"
      end
    end
  end
end
