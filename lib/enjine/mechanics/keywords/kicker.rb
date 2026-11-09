# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # Additional costs of a spell (CR 601.2b, 601.2f-h, 118.8): paid as the spell is cast, on top of its
      # mana cost. Mana parts add to the total cost; other parts (sacrifice a creature) are chosen while
      # casting and paid as it becomes cast.
      class SpellCost < Primitive
        attr_reader :costs

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost], errors, path)
          costs = StackAbility.parse_costs(params, errors, path)
          errors << "#{path}.cost: must be a non-empty list" if costs.empty? && errors.none? { it.start_with?("#{path}.cost") }
          costs.each_with_index do |cost, i|
            next if spell_cost?(cost)

            errors << "#{path}.cost[#{i}]: a spell's additional cost must be mana, life or a chosen cost (sacrifice, tap, ...)"
          end
          new(costs)
        end

        def self.spell_cost?(cost)
          return cost.options.all? { spell_cost?(it) } if cost.is_a?(Costs::OneOf)

          cost.mana? || cost.respond_to?(:choices_needed) || cost.respond_to?(:spell_cost?)
        end

        def initialize(costs, optional: false)
          super()
          @costs = costs
          @optional = optional
          freeze
        end

        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        def mana_cost = Mana.sum_costs(costs.select(&:mana?).map(&:mana_cost))
        def choosing_costs = costs.reject(&:mana?)
        # Recorded as the spell's "kicked_with" when this optional cost is paid.
        def keyword = self.class.primitive_name.to_s
        # Whether paying it makes the spell kicked (CR 702.33d).
        def kicks? = false

        # Whether the non-mana parts can be paid by the spell's controller (CR 118.3).
        def payable?(engine, spell) = choosing_costs.all? { it.payable?(engine, spell) }
      end

      # Kicker (CR 702.33a): "You may pay an additional [cost] as you cast this spell." The choice is
      # announced while casting (CR 601.2b); a kicked spell remembers it (condition {"kicked": true},
      # CR 702.33d) and may have other targets (`kicked_targets` of its spell ability, CR 702.33g).
      class Kicker < SpellCost
        primitive :ability, :kicker,
                  description: "Kicker: as you cast this spell you may also pay `cost` (mana and/or chosen costs " \
                               "such as `sacrifice_permanent`). The spell is then kicked: `{\"kicked\": true}` " \
                               "conditions hold and its `kicked_targets` are used.",
                  rules: %w[702.33a 702.33d 702.33g 601.2b 601.2f 601.2h],
                  params: { "cost" => "list of costs, e.g. [{\"mana\": \"{1}{U}\"}]" },
                  example: { "kicker" => { "cost" => [{ "mana" => "{1}{U}" }] } }

        def kind = :kicker
        def kicks? = true
        def to_s = "Kicker #{costs.join(", ")}"
      end

      # An additional cost: "As an additional cost to cast this spell, sacrifice a creature." (CR 601.2b,
      # 601.2f-h, 118.8). An optional one ("you may behold a Dragon", CR 118.8b) is announced like kicker (the
      # `choose_kicker` decision) without making the spell kicked: {"cast_with": "additional_cost"} holds if it
      # was paid.
      class AdditionalCost < SpellCost
        primitive :ability, :additional_cost,
                  description: "As an additional cost to cast this spell, pay `cost` too (mana and/or chosen costs " \
                               "such as `sacrifice_permanent`). The spell can't be cast without it. `optional: true`: " \
                               "you may pay it (announced with the `choose_kicker` decision); the condition " \
                               "`{\"cast_with\": \"additional_cost\"}` then holds (the spell isn't kicked).",
                  rules: %w[601.2b 601.2f 601.2h 118.8 118.8b],
                  params: { "cost" => "list of costs", "optional" => "true: you may pay it" },
                  example: { "additional_cost" => { "cost" => [{ "sacrifice_permanent" => { "filter" => "creature" } }] } }

        def self.build(params, errors, path, **)
          optional = Mechanics.flag_param(params, :optional, errors, path)
          new(super(params.except("optional", :optional), errors, path).costs, optional: optional)
        end

        def kind = @optional ? :kicker : :additional_cost
        def to_s = "As an additional cost to cast this spell#{", you may" if @optional}: #{costs.join(", ")}"
      end
    end
  end
end
