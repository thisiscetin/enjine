# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # Shared parsing for abilities that use the stack: targets and effects.
      class StackAbility < Primitive
        attr_reader :targets, :effects, :costs

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

        def initialize(targets:, effects:, costs: [].freeze)
          super()
          @targets = targets
          @effects = effects
          @costs = costs
          freeze
        end

        def mana_ability? = false
        def loyalty_cost = nil
        def effects_text = effects.join("; ")
        def to_s = "#{costs.join(", ")}: #{effects_text}"
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
          Mechanics.check_keys(params, %w[targets effects], errors, path)
          targets = parse_targets(params, errors, path)
          new(targets: targets, effects: parse_effects(params, errors, path, targets.size))
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
          Mechanics.check_keys(params, %w[cost targets effects timing], errors, path)
          timing = Mechanics.fetch_param(params, :timing) || "instant"
          errors << "#{path}.timing: must be \"instant\" or \"sorcery\"" unless %w[instant sorcery].include?(timing)
          costs = parse_costs(params, errors, path)
          errors << "#{path}.cost: must be a non-empty list" if costs.empty? && errors.none? { it.start_with?("#{path}.cost") }
          targets = parse_targets(params, errors, path)
          new(targets: targets, effects: parse_effects(params, errors, path, targets.size), costs: costs,
              sorcery: timing == "sorcery")
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
          Mechanics.check_keys(params, %w[when targets effects], errors, path)
          raw = Mechanics.fetch_param(params, :when)
          trigger = raw.nil? ? ((errors << "#{path}.when: required") && nil) : Mechanics.build_entry(:trigger, raw, errors, "#{path}.when")
          targets = parse_targets(params, errors, path)
          new(targets: targets, effects: parse_effects(params, errors, path, targets.size), trigger: trigger)
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
          Mechanics.check_keys(params, %w[cost targets effects], errors, path)
          cost = Mechanics.fetch_param(params, :cost)
          errors << "#{path}.cost: must be an integer loyalty change" unless cost.is_a?(Integer)
          targets = parse_targets(params, errors, path)
          new(targets: targets, effects: parse_effects(params, errors, path, targets.size), loyalty: cost.to_i)
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
