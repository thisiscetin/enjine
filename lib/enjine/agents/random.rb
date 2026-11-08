# frozen_string_literal: true

module Enjine
  module Agents
    # Picks uniformly among the legal options. No strategy: a fuzzing driver and CLI seat.
    #
    # `cancel_rate` is the chance of choosing "cancel" when other options exist. With a
    # uniform pick, a 4-mana spell (about 8 payment decisions, each offering cancel)
    # would almost never finish casting, so expensive cards and planeswalkers would
    # go untested. The default keeps cancellation exercised but rare.
    class Random
      CANCEL = { type: "cancel" }.freeze

      def initialize(seed: 0, cancel_rate: 0.02)
        @rng = Rng.from_seed(seed)
        @cancel_threshold = (cancel_rate * 1_000_000).round
      end

      def choose(decision)
        options = decision.options
        others = options.include?(CANCEL) && options.size > 1 ? options - [CANCEL] : options
        return CANCEL if others.size < options.size && @rng.rand(1_000_000) < @cancel_threshold

        others[@rng.rand(others.size)]
      end
    end
  end
end
