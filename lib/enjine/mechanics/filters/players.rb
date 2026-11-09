# frozen_string_literal: true

module Enjine
  module Mechanics
    module Filters
      # A player.
      class Player < Filter
        primitive :filter, :player, description: "A player.", rules: %w[115.1], example: "player"
        def self.players?(_engine, index, _controller) = !index.nil?
      end

      # An opponent of the controller.
      class Opponent < Filter
        primitive :filter, :opponent, description: "An opponent of the ability's controller.", rules: %w[102.2],
                                      example: "opponent"
        def self.players?(_engine, index, controller) = !index.nil? && index != controller
      end
    end
  end
end
