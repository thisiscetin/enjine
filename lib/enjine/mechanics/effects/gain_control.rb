# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "Gain control of target permanent" / "... until end of turn" / "Target opponent gains control of
      # target permanent you control" (CR 613.1b, 108.4, 506.4, 302.6).
      class GainControl < Effect
        DURATIONS = %w[permanent end_of_turn while_source_on_battlefield while_source_tapped].freeze

        primitive :effect, :gain_control,
                  description: "The player referenced by `gains` (default you) gains control of each referenced " \
                               "permanent: indefinitely (`duration: \"permanent\"`, default), until end of turn, or for " \
                               "as long as this effect's source remains on the battlefield / tapped (it does nothing " \
                               "if that is already over). " \
                               "A permanent that changes control leaves combat and is newly under its controller's " \
                               "control (it can't attack or {T} without haste).",
                  rules: %w[613.1b 108.4 506.4 302.6 514.2 611.2b],
                  params: { "to" => "selector (permanents)", "gains" => "selector (a player; default \"you\")",
                            "duration" => DURATIONS.join(" | ") },
                  example: { "gain_control" => { "to" => { "target" => 0 }, "duration" => "end_of_turn" } }

        attr_reader :gains, :duration

        def self.keys = %w[to gains duration if]

        def setup(params, errors, path)
          @gains = Selector.build(Mechanics.fetch_param(params, :gains) || "you", errors, "#{path}.gains",
                                  targets_count: @targets_count, results_count: @results_count)
          @duration = Mechanics.fetch_param(params, :duration) || "permanent"
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
        end

        def apply(engine, ctx)
          player = gains.resolve(engine, ctx).filter_map { Filters.player_index(engine, it) }.first or return
          return unless source_holds?(engine, ctx)

          objects(engine, ctx).each do |id|
            obj = engine.object(id)
            next engine.gain_control!(obj, player) if duration == "permanent"

            engine.gain_control_for!(obj, player, ctx, duration: duration,
                                                       source: duration == "end_of_turn" ? nil : ctx.source)
          end
        end

        def to_s = "#{gains} gains control#{" until end of turn" if duration == "end_of_turn"} → #{to}"

        private

        # CR 611.2b: a "for as long as" duration that has already ended never starts.
        def source_holds?(engine, ctx)
          return true unless duration.start_with?("while_source")

          on = engine.state.battlefield.include?(ctx.source)
          duration == "while_source_tapped" ? on && engine.object(ctx.source).tapped : on
        end
      end

      # "Exchange control of target artifact you control and target artifact an opponent controls" (CR 701.12a-b):
      # if both permanents are still there and controlled by different players, each player gains control of
      # the other one (indefinitely); otherwise nothing happens.
      class ExchangeControl < Effect
        primitive :effect, :exchange_control,
                  description: "The permanent `to` references and the one `with` references exchange controllers. " \
                               "If either is gone or both have the same controller, nothing happens.",
                  rules: %w[701.12a 701.12b 613.1b],
                  params: { "to" => "selector (a permanent)", "with" => "selector (a permanent)" },
                  example: { "exchange_control" => { "to" => { "target" => 0 }, "with" => { "target" => 1 } } }

        attr_reader :with

        def self.keys = %w[to with if]

        def setup(params, errors, path)
          @with = Exchange.with(params, errors, path, @targets_count, @results_count)
        end

        def apply(engine, ctx)
          first, second = [to, with].map { |sel| sel.resolve(engine, ctx).find { engine.state.battlefield.include?(it) } }
          return if first.nil? || second.nil? || first == second

          a = engine.object(first)
          b = engine.object(second)
          return if a.controller == b.controller

          timestamp = engine.next_timestamp!
          [[a, b.controller], [b, a.controller]].each { |obj, controller| engine.gain_control!(obj, controller, timestamp) }
        end

        def to_s = "exchange control of #{to} and #{with}"
      end

      # The `with` side of an exchange (CR 701.12a): a required selector.
      module Exchange
        def self.with(params, errors, path, targets_count, results_count)
          raw = Mechanics.fetch_param(params, :with)
          errors << "#{path}.with: required" if raw.nil?
          Selector.build(raw || "you", errors, "#{path}.with", targets_count: targets_count, results_count: results_count)
        end
      end
    end
  end
end
