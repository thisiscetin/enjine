# frozen_string_literal: true

module Enjine
  module Agents
    # A random agent that would rather do something than pass: with priority it plays a land when it can,
    # and otherwise casts a spell or activates an ability `eagerness` percent of the time. Every other
    # decision (targets, payments, attacks, blocks) is uniform, as for Agents::Random. It still passes now
    # and then, so a free repeatable ability can't hold a game forever. Card checks use it so cards get used.
    class Busy < Random
      ACTIONS = %w[play_land cast activate].freeze

      def initialize(seed: 0, cancel_rate: 0.02, eagerness: 85)
        super(seed: seed, cancel_rate: cancel_rate)
        @eagerness = eagerness
      end

      def choose(decision)
        actions = decision.options.select { ACTIONS.include?(it[:type]) }
        return super if actions.empty? || @rng.rand(100) >= @eagerness

        lands = actions.select { it[:type] == "play_land" }
        pick = lands.empty? ? actions : lands
        pick[@rng.rand(pick.size)]
      end
    end
  end
end
