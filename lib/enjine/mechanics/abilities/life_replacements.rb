# frozen_string_literal: true

require_relative "replacement_effects"

module Enjine
  module Mechanics
    module Abilities
      # "If you would gain life, you gain twice that much life instead" / "... that much life plus 1 instead" /
      # "If an opponent would gain life, that player loses that much life instead" (CR 614.1a, 119.10): a
      # static replacement effect of a permanent that changes a life gain event. Replacements.gaining_life!
      # applies them.
      class LifeGainReplacement < StaticReplacement
        PLAYERS = %w[you opponent any].freeze

        primitive :ability, :life_gain_replacement,
                  description: "While this permanent is on the battlefield, each time `player` (you (default) | " \
                               "opponent | any, relative to its controller) would gain life, instead: `multiply` " \
                               "(2 = \"twice that much\"), `plus` an amount (\"that much life plus 1\"), or `lose: " \
                               "true` (\"that player loses that much life instead\"). Each applies once to an event; " \
                               "the affected player's best order is used: losing instead first, then adding, then " \
                               "multiplying. Gaining 0 life is no event (nothing applies).",
                  rules: %w[614.1a 614.5 616.1 119.10],
                  params: { "player" => PLAYERS.join(" | "), "multiply" => "integer >= 2", "plus" => "amount",
                            "lose" => "true" },
                  example: { "life_gain_replacement" => { "player" => "you", "plus" => 1 } }

        attr_reader :player, :multiply, :plus

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[player multiply plus lose], errors, path)
          player = params.fetch("player", "you")
          errors << "#{path}.player: must be one of #{PLAYERS.join(", ")}" unless PLAYERS.include?(player)
          modes = %w[multiply plus lose].select { params.key?(it) }
          errors << "#{path}: needs exactly one of multiply, plus, lose" unless modes.size == 1
          errors << "#{path}.lose: must be true" if params.key?("lose") && params["lose"] != true
          multiply = params.key?("multiply") ? Mechanics.integer_param(params, :multiply, errors, path, min: 2) : nil
          plus = params.key?("plus") ? Amount.build(params["plus"], errors, "#{path}.plus", targets_count: 0) : nil
          new(player, multiply, plus, params["lose"] == true)
        end

        def initialize(player, multiply, plus, lose)
          super()
          @player = player
          @multiply = multiply
          @plus = plus
          @lose = lose
          freeze
        end

        def kind = :life_gain_replacement
        def lose? = @lose

        # Whether it applies to `index` gaining life (CR 614.1a), relative to the holder's controller.
        def replaces_gain?(index, holder) = player == "any" || (player == "you") == (index == holder.controller)

        # The changed amount of life gained (not used for `lose`).
        def gained(engine, amount, holder)
          return amount * multiply if multiply

          amount + [plus.value(engine, EffectContext.new(holder.controller, holder.id, holder.id, [], [])), 0].max
        end

        def to_s
          who = { "you" => "you", "opponent" => "an opponent", "any" => "a player" }.fetch(player)
          instead = if multiply then "gain #{multiply} times that much"
                    elsif plus then "gain that much plus #{plus}"
                    else "lose that much"
                    end
          "if #{who} would gain life, #{instead} instead"
        end
      end
    end
  end
end
