# frozen_string_literal: true

module Enjine
  module Agents
    # Picks uniformly among the legal options. No strategy: a fuzzing driver and CLI seat.
    class Random
      def initialize(seed: 0)
        @rng = Rng.from_seed(seed)
      end

      def choose(decision) = decision.options[@rng.rand(decision.options.size)]
    end
  end
end
