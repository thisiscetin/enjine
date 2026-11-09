# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "Gain control of target permanent" / "... until end of turn" / "Target opponent gains control of
      # target permanent you control" (CR 613.1b, 108.4, 506.4, 302.6).
      class GainControl < Effect
        DURATIONS = %w[permanent end_of_turn].freeze

        primitive :effect, :gain_control,
                  description: "The player referenced by `gains` (default you) gains control of each referenced " \
                               "permanent: indefinitely (`duration: \"permanent\"`, default) or until end of turn. " \
                               "A permanent that changes control leaves combat and is newly under its controller's " \
                               "control (it can't attack or {T} without haste).",
                  rules: %w[613.1b 108.4 506.4 302.6 514.2],
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
          objects(engine, ctx).each do |id|
            obj = engine.object(id)
            duration == "permanent" ? engine.gain_control!(obj, player) : engine.gain_control_until_end_of_turn!(obj, player, ctx)
          end
        end

        def to_s = "#{gains} gains control#{" until end of turn" if duration == "end_of_turn"} → #{to}"
      end
    end
  end
end
