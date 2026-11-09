# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # +N/+N until end of turn (CR 611.2, 613.4c). Affected set is locked in on resolution (611.2c).
      # "Until your next turn" lasts until the controller's next turn begins (CR 611.2a, 500.1; see
      # Engine::Rules#end_effects_until_turn_of!).
      class Pump < Effect
        DURATIONS = %w[end_of_turn until_your_next_turn].freeze

        primitive :effect, :pump,
                  description: "Each referenced creature gets +power/+toughness until end of turn (`duration: " \
                               "\"until_your_next_turn\"`: until its controller's next turn begins). The set of " \
                               "affected creatures is locked in when the effect starts.",
                  rules: %w[611.2a 611.2c 613.4c 514.2 500.1],
                  params: { "power" => "amount (may be negative, e.g. {\"times\": [\"x\", -1]} for -X)",
                            "toughness" => "amount (may be negative)", "to" => "selector",
                            "duration" => DURATIONS.join(" | ") },
                  example: { "pump" => { "power" => 3, "toughness" => 3, "to" => { "target" => 0 } } }

        attr_reader :duration

        def self.keys = %w[power toughness to duration if]

        # A signed amount: an integer, or a computed Amount ("+X/+X, where X is ...", CR 608.2h).
        def self.signed(params, key, errors, path, **context)
          raw = Mechanics.fetch_param(params, key)
          raw.nil? ? Amount::Fixed.new(0) : Amount.build(raw, errors, "#{path}.#{key}", min: -1_000_000, **context)
        end

        def self.signed_text(amount) = amount.is_a?(Amount::Fixed) ? format("%+d", amount.n) : "+(#{amount})"

        def setup(params, errors, path)
          context = { targets_count: @targets_count, results_count: @results_count }
          @power = Pump.signed(params, :power, errors, path, **context)
          @toughness = Pump.signed(params, :toughness, errors, path, **context)
          @duration = Mechanics.fetch_param(params, :duration) || "end_of_turn"
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
        end

        # The fixed bonus (for display); computed bonuses are Amounts.
        def power = @power.is_a?(Amount::Fixed) ? @power.n : @power
        def toughness = @toughness.is_a?(Amount::Fixed) ? @toughness.n : @toughness

        def to_s
          "#{Pump.signed_text(@power)}/#{Pump.signed_text(@toughness)} until #{duration.delete_prefix("until_").tr("_", " ")} → #{to}"
        end

        # The amounts are computed once, as the effect starts (CR 608.2h, 611.2c). A noncreature it affects (an
        # uncrewed Vehicle) gets the bonus once it's a creature this turn (CR 611.2c, 208.3).
        def apply(engine, ctx)
          engine.add_continuous_effect!("pump", ctx, objects(engine, ctx), "power" => @power.value(engine, ctx),
                                                                           "toughness" => @toughness.value(engine, ctx),
                                                                           "duration" => duration)
        end
      end
    end
  end
end
