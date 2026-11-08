# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Adding mana as the effect of a resolving spell or ability (CR 106.4): "Add {R}{R}{R}." or
      # "Add two mana of any one color." The color is chosen as the effect resolves (CR 608.2d).
      # Activated abilities without targets that add mana are mana abilities instead (CR 605.1a).
      class AddMana < ChoiceEffect
        COLORS = Mana::COLORS.map(&:to_s).freeze
        CHOICES = %w[any_one any].freeze

        primitive :effect, :add_mana,
                  description: "You add mana to your mana pool: the fixed mana in `produce`, or `amount` mana of a " \
                               "color you choose as it resolves (`color: \"any_one\"`: all of one color; " \
                               "`color: \"any\"`: each mana's color chosen separately, \"in any combination of " \
                               "colors\").",
                  rules: %w[106.1a 106.4 608.2d 605.1a],
                  params: { "produce" => "mana symbols, e.g. \"{R}{R}\"", "amount" => "amount (default 1; with produce: how many times)",
                            "color" => CHOICES.join(" | ") },
                  example: { "add_mana" => { "amount" => 2, "color" => "any_one" } }

        attr_reader :produce, :color

        def self.keys = %w[produce amount color if]
        def self.default_to = "you"

        def initialize(to:, params:, errors:, path:, targets_count: 0, results_count: 0)
          params = params.transform_keys(&:to_s)
          params["amount"] = 1 unless params.key?("amount")
          super
        end

        def setup(params, errors, path)
          raw = Mechanics.fetch_param(params, :produce)
          @color = Mechanics.fetch_param(params, :color)
          @produce = raw && Mana.parse_produce(raw, errors, "#{path}.produce")
          errors << "#{path}: needs exactly one of produce, color" unless raw.nil? ^ @color.nil?
          errors << "#{path}.color: must be one of #{CHOICES.join(", ")}" if @color && !CHOICES.include?(@color)
        end

        def run(engine, ctx, locals)
          return :done unless condition.nil? || condition.true?(engine, ctx)

          index = ctx.controller
          return add(engine, index, @produce * amount_for(engine, ctx), ctx) unless @color # "an amount of {G} equal to"

          n = (locals["n"] ||= amount_for(engine, ctx))
          picks = answers(locals)
          if picks.size < (@color == "any_one" ? [n, 1].min : n)
            return ask(engine, locals, index, "Choose the color of #{@color == "any_one" ? "the" : "the next"} mana",
                       COLORS.map { { "type" => "color", "color" => it } })
          end
          colors = picks.map { it["color"].to_sym }
          add(engine, index, @color == "any_one" ? colors * n : colors, ctx)
        end

        def to_s
          return "add #{produce.map { "{#{it}}" }.join}" if produce

          "add #{amount} mana of #{@color == "any_one" ? "any one color" : "any combination of colors"}"
        end

        private

        def add(engine, index, produce, ctx)
          engine.add_mana!(index, produce, ctx.source) unless produce.nil? || produce.empty?
          :done
        end
      end
    end
  end
end
