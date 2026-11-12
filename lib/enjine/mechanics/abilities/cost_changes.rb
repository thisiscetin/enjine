# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # "costs {N} less" (CR 601.2f, 118.7a): an amount of generic mana, fixed or computed (Amount),
      # optionally only while a condition holds. Shared by the spell and activated-ability forms.
      class Reduction
        attr_reader :amount, :condition

        def self.build(data, errors, path)
          unless data.is_a?(Hash)
            errors << "#{path}: must be {\"amount\": n, \"if\": condition}"
            return new(Amount::Fixed.new(0), nil)
          end
          data = data.transform_keys(&:to_s)
          Mechanics.check_keys(data, %w[amount if], errors, path)
          amount = if data.key?("amount")
                     Amount.build(data["amount"], errors, "#{path}.amount", targets_count: 0)
                   else
                     (errors << "#{path}.amount: required") && Amount::Fixed.new(0)
                   end
          condition = data["if"] && Condition.build(data["if"], errors, "#{path}.if")
          new(amount, condition)
        end

        def initialize(amount, condition)
          @amount = amount
          @condition = condition
          freeze
        end

        # The generic mana it takes off now (0 when the condition doesn't hold).
        def reduction(engine, ctx) = condition.nil? || condition.true?(engine, ctx) ? amount.value(engine, ctx) : 0

        def to_s = "costs {#{amount}} less#{" if #{condition}" if condition}"
      end

      # "This spell costs {N} less to cast [if ... / for each ...]" (CR 601.2f). It functions while
      # the card is being cast; the condition sees the chosen targets ("if it targets ...").
      class CostReduction < Primitive
        primitive :ability, :cost_reduction,
                  description: "This spell costs `amount` generic mana less to cast, if the optional `if` condition " \
                               "holds when its total cost is determined (after targets are chosen). `amount` may be " \
                               "computed, e.g. {\"count\": {\"each\": \"artifact\", \"controller\": \"you\"}} for " \
                               "affinity for artifacts (CR 702.41a). It can't reduce colored mana or go below {0}.",
                  rules: %w[601.2f 118.7a 702.41a],
                  params: { "amount" => "amount (integer or computed)", "if" => "condition (optional)" },
                  example: { "cost_reduction" => { "amount" => 1, "if" => { "attacked" => true } } }

        attr_reader :rule

        def self.build(params, errors, path, **)
          new(Reduction.build(params, errors, path))
        end

        def initialize(rule)
          super()
          @rule = rule
          freeze
        end

        def reduction(engine, ctx) = rule.reduction(engine, ctx)
        def kind = :cost_reduction
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        def to_s = "This spell #{rule}."
      end

      # "Spells you cast cost {1} less" / "Noncreature spells your opponents cast cost {1} more"
      # (CR 601.2f): a static ability of a permanent that changes the total cost of matching spells.
      class CostModifier < Primitive
        TYPES = %w[artifact creature enchantment land planeswalker instant sorcery].freeze
        CASTERS = %w[you opponent any].freeze
        SPEC_KEYS = %w[subtypes colors].freeze

        primitive :ability, :cost_modifier,
                  description: "While on the battlefield: spells cast by `caster` (you, opponent or any; default you) " \
                               "whose card types match `spells` ({\"any_of\": [types], \"not\": [types]}, default all " \
                               "spells; `subtypes` and `colors` narrow it: \"Dragon spells\", \"red spells\") cost " \
                               "`reduce` less or `increase` more generic mana. `from` / `not_from`: only " \
                               "spells cast from (not from) that zone (hand | graveyard | exile | library | outside).",
                  rules: %w[601.2f 118.7a 604.1 601.2a],
                  params: { "spells" => "{\"any_of\": [types], \"not\": [types], \"subtypes\": [subtypes], \"colors\": [colors]} " \
                                        "(optional)",
                            "caster" => "you | opponent | any", "reduce" => "amount", "increase" => "amount",
                            "from" => "zone", "not_from" => "zone" },
                  example: { "cost_modifier" => { "spells" => { "not" => ["creature"] }, "reduce" => 1 } }

        attr_reader :caster, :any_of, :not_types, :amount, :sign

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[spells caster reduce increase] + CastFrom::KEYS, errors, path)
          spells = Mechanics.fetch_param(params, :spells) || {}
          unless spells.is_a?(Hash)
            errors << "#{path}.spells: must be an object"
            spells = {}
          end
          Mechanics.check_keys(spells, %w[any_of not] + SPEC_KEYS, errors, "#{path}.spells")
          lists = %w[any_of not].to_h do |key|
            list = Array(spells.transform_keys(&:to_s)[key]).map(&:to_s)
            errors << "#{path}.spells.#{key}: must be card types (#{TYPES.join(", ")})" unless (list - TYPES).empty?
            [key, list.map(&:to_sym)]
          end
          caster = Mechanics.fetch_param(params, :caster) || "you"
          errors << "#{path}.caster: must be one of #{CASTERS.join(", ")}" unless CASTERS.include?(caster)
          new(caster, lists["any_of"], lists["not"], *build_amount(params, errors, path),
              zones: CastFrom.build(params, errors, path), spec: build_spec(spells, errors, path))
        end

        # "Dragon spells", "red spells": the subtypes and colors in `spells`, matched as a card spec.
        def self.build_spec(spells, errors, path)
          data = spells.transform_keys(&:to_s).slice(*SPEC_KEYS)
          data.empty? ? nil : CardSpec.build(data, errors, "#{path}.spells")
        end

        def self.build_amount(params, errors, path)
          keys = %w[reduce increase].select { params.key?(it) }
          unless keys.size == 1
            errors << "#{path}: needs exactly one of reduce, increase"
            return [Amount::Fixed.new(0), -1]
          end
          [Amount.build(params[keys.first], errors, "#{path}.#{keys.first}", targets_count: 0), keys.first == "reduce" ? -1 : 1]
        end

        def initialize(caster, any_of, not_types, amount, sign, zones: CastFrom.new(nil, nil), spec: nil)
          super()
          @spec = spec
          @caster = caster
          @any_of = any_of.freeze
          @not_types = not_types.freeze
          @amount = amount
          @sign = sign
          @zones = zones
          freeze
        end

        def kind = :cost_modifier
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []

        # The generic change this permanent makes to `spell`, cast by player `caster_index`.
        def change_for(engine, permanent, spell, caster_index)
          return 0 unless caster == "any" || (caster == "you") == (caster_index == permanent.controller)

          chars = engine.chars(spell)
          types = chars.types
          return 0 if types.intersect?(not_types) || !(any_of.empty? || types.intersect?(any_of))
          return 0 if @spec && !@spec.chars_match?(engine, chars)
          return 0 unless @zones.match?(engine.cast_origin(spell))

          sign * amount.value(engine, EffectContext.new(permanent.controller, permanent.id, permanent.id, []))
        end

        def to_s
          narrow = @spec ? [@spec.colors.map(&:to_s), @spec.subtypes.map { it.to_s.capitalize }] : []
          kinds = [not_types.map { "non#{it}" }, narrow, any_of.join(" or ")].flatten.reject(&:empty?).join(" ")
          whose = { "you" => "you cast", "opponent" => "your opponents cast", "any" => "" }[caster]
          "#{[kinds, "spells", whose].reject(&:empty?).join(" ")}#{@zones} cost {#{amount}} " \
            "#{sign.negative? ? "less" : "more"}"
        end
      end
    end
  end
end
