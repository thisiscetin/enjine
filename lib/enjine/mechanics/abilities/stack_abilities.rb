# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # Shared parsing for abilities that use the stack: targets and effects.
      class StackAbility < Primitive
        # One mode of a modal ability ("Choose one —", CR 700.2): its own targets and effects.
        Mode = Data.define(:targets, :effects)

        attr_reader :targets, :effects, :costs, :modes, :choose

        # Parses either plain targets/effects or {"choose": n, "modes": [{targets, effects}, ...]}.
        def self.parse_body(params, errors, path)
          modes_data = Mechanics.fetch_param(params, :modes)
          if modes_data.nil?
            targets = parse_targets(params, errors, path)
            return { targets: targets, effects: parse_effects(params, errors, path, targets.size), modes: [].freeze, choose: 0 }
          end
          unless modes_data.is_a?(Array) && modes_data.size >= 2
            errors << "#{path}.modes: must be a list of at least two modes"
            modes_data = []
          end
          errors << "#{path}: use either modes or targets/effects, not both" if params.key?("targets") || params.key?("effects")
          modes = modes_data.each_with_index.map do |mode, i|
            mode_path = "#{path}.modes[#{i}]"
            mode = mode.is_a?(Hash) ? mode.transform_keys(&:to_s) : {}
            Mechanics.check_keys(mode, %w[targets effects], errors, mode_path)
            mode_targets = parse_targets(mode, errors, mode_path)
            Mode.new(targets: mode_targets, effects: parse_effects(mode, errors, mode_path, mode_targets.size))
          end
          choose = Mechanics.integer_param(params, :choose, errors, path, default: 1, min: 1)
          errors << "#{path}.choose: can't exceed the number of modes" if choose > modes.size && !modes.empty?
          { targets: [].freeze, effects: [].freeze, modes: modes.freeze, choose: choose }
        end

        BODY_KEYS = %w[targets effects modes choose].freeze

        def self.parse_targets(params, errors, path)
          Mechanics.list_param(params, :targets, errors, path).each_with_index.filter_map do |entry, i|
            Mechanics.build_entry(:filter, entry, errors, "#{path}.targets[#{i}]")
          end.freeze
        end

        def self.parse_effects(params, errors, path, targets_count)
          list = Mechanics.list_param(params, :effects, errors, path)
          list.each_with_index.filter_map do |entry, i|
            Mechanics.build_entry(:effect, entry, errors, "#{path}.effects[#{i}]", targets_count: targets_count)
          end.freeze
        end

        def self.parse_costs(params, errors, path)
          Mechanics.list_param(params, :cost, errors, path).each_with_index.filter_map do |entry, i|
            Mechanics.build_entry(:cost, entry, errors, "#{path}.cost[#{i}]")
          end.freeze
        end

        def initialize(targets:, effects:, costs: [].freeze, modes: [].freeze, choose: 0)
          super()
          @targets = targets
          @effects = effects
          @costs = costs
          @modes = modes
          @choose = choose
          freeze
        end

        def modal? = !modes.empty?

        # Targets in order for the chosen modes (or the ability's own targets).
        def targets_for(chosen) = modal? ? chosen.sort.flat_map { modes[it].targets } : targets

        # [[effect, target offset, target count], ...] in resolution order (modes in printed order, CR 700.2a).
        def effect_plan(chosen)
          return effects.map { [it, 0, targets.size] } unless modal?

          offset = 0
          chosen.sort.flat_map do |index|
            mode = modes[index]
            plan = mode.effects.map { [it, offset, mode.targets.size] }
            offset += mode.targets.size
            plan
          end
        end

        def mana_ability? = false
        def loyalty_cost = nil

        def effects_text
          return effects.join("; ") unless modal?

          "choose #{choose} — " + modes.map { it.effects.join("; ") }.join(" • ")
        end

        def to_s = costs.empty? ? effects_text : "#{costs.join(", ")}: #{effects_text}"
        def sorcery_speed? = false
        def allowed_types = nil

        # Total mana cost to pay during activation.
        def mana_cost
          generic = 0
          colored = Hash.new(0)
          costs.select(&:mana?).each do |cost|
            generic += cost.mana_cost.generic
            cost.mana_cost.colored.each { |c, n| colored[c] += n }
          end
          Mana::Cost.new(generic: generic, colored: colored.to_h.freeze)
        end
      end

      # The spell ability of an instant or sorcery (CR 113.3a): what happens when it resolves.
      class SpellAbility < StackAbility
        primitive :ability, :spell,
                  description: "The spell ability of an instant or sorcery: its targets are chosen while casting " \
                               "and its effects happen in order when it resolves. If every target is illegal on " \
                               "resolution, it doesn't resolve.",
                  rules: %w[113.3a 601.2c 608.2b 608.2c],
                  params: { "targets" => "list of target filters", "effects" => "list of effects" },
                  example: { "spell" => { "targets" => ["any_target"],
                                          "effects" => [{ "deal_damage" => { "amount" => 3, "to" => { "target" => 0 } } }] } }

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, BODY_KEYS, errors, path)
          new(**parse_body(params, errors, path))
        end

        def kind = :spell
        def allowed_types = %i[instant sorcery]
      end

      # A non-mana activated ability "[Cost]: [Effect]" (CR 602).
      class ActivatedAbility < StackAbility
        primitive :ability, :activated,
                  description: "An activated ability: announce it, choose targets, pay its costs, then it goes on " \
                               "the stack. `timing: \"sorcery\"` restricts it to sorcery speed.",
                  rules: %w[602.1 602.2 602.5d],
                  params: { "cost" => "list of costs (tap, {\"mana\": \"{1}\"})", "targets" => "list of target filters",
                            "effects" => "list of effects", "timing" => "\"instant\" (default) or \"sorcery\"" },
                  example: { "activated" => { "cost" => ["tap"], "targets" => ["any_target"],
                                              "effects" => [{ "deal_damage" => { "amount" => 1, "to" => { "target" => 0 } } }] } }

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost timing] + BODY_KEYS, errors, path)
          timing = Mechanics.fetch_param(params, :timing) || "instant"
          errors << "#{path}.timing: must be \"instant\" or \"sorcery\"" unless %w[instant sorcery].include?(timing)
          costs = parse_costs(params, errors, path)
          errors << "#{path}.cost: must be a non-empty list" if costs.empty? && errors.none? { it.start_with?("#{path}.cost") }
          new(**parse_body(params, errors, path), costs: costs, sorcery: timing == "sorcery")
        end

        def initialize(sorcery:, **)
          @sorcery = sorcery
          super(**)
        end

        def kind = :activated
        def sorcery_speed? = @sorcery
      end

      # A triggered ability "When/Whenever/At [trigger], [effect]" (CR 603).
      class TriggeredAbility < StackAbility
        primitive :ability, :triggered,
                  description: "A triggered ability: when its trigger condition happens, it is put on the stack the " \
                               "next time a player would receive priority (in APNAP order), with targets chosen then.",
                  rules: %w[603.2 603.3 603.3b 603.3d],
                  params: { "when" => "a trigger condition, e.g. {\"enters\": {}}", "targets" => "list of target filters",
                            "effects" => "list of effects" },
                  example: { "triggered" => { "when" => { "enters" => {} }, "effects" => [{ "draw" => { "amount" => 1 } }] } }

        attr_reader :trigger

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[when] + BODY_KEYS, errors, path)
          raw = Mechanics.fetch_param(params, :when)
          trigger = raw.nil? ? ((errors << "#{path}.when: required") && nil) : Mechanics.build_entry(:trigger, raw, errors, "#{path}.when")
          new(**parse_body(params, errors, path), trigger: trigger)
        end

        def initialize(trigger:, **)
          @trigger = trigger
          super(**)
        end

        def kind = :triggered
        def to_s = "#{trigger}, #{effects_text}"
      end

      # A planeswalker loyalty ability "+N: ..." / "-N: ..." (CR 606).
      class LoyaltyAbility < StackAbility
        primitive :ability, :loyalty,
                  description: "A loyalty ability. Its cost adds (positive) or removes (negative) loyalty counters " \
                               "and is paid on activation. Sorcery speed, and only one loyalty ability per " \
                               "planeswalker per turn.",
                  rules: %w[606.3 606.4 606.5 602.2b],
                  params: { "cost" => "integer, e.g. 1 for +1 or -2", "targets" => "list of target filters",
                            "effects" => "list of effects" },
                  example: { "loyalty" => { "cost" => -3, "targets" => ["creature"],
                                            "effects" => [{ "deal_damage" => { "amount" => 3, "to" => { "target" => 0 } } }] } }

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost] + BODY_KEYS, errors, path)
          cost = Mechanics.fetch_param(params, :cost)
          errors << "#{path}.cost: must be an integer loyalty change" unless cost.is_a?(Integer)
          new(**parse_body(params, errors, path), loyalty: cost.to_i)
        end

        def initialize(loyalty:, **)
          @loyalty = loyalty
          super(**)
        end

        def kind = :loyalty
        def loyalty_cost = @loyalty
        def sorcery_speed? = true
        def allowed_types = [:planeswalker]

        def to_s = "#{"+" if @loyalty.positive?}#{@loyalty}: #{effects_text}"
      end
    end
  end
end
