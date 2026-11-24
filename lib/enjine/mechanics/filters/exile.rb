# frozen_string_literal: true

module Enjine
  module Mechanics
    module Filters
      # "Target creature card exiled with [this]" (CR 607.2a, 115.1): a card in exile that an ability of the
      # filter's source exiled. {"exiled_with": {"any_of": ["creature"]}} narrows it by card type. Without a
      # source (an "each" selector of a static ability) nothing matches.
      class ExiledWith < Filter
        primitive :filter, :exiled_with,
                  description: "A card in exile that one of this object's abilities exiled (linked abilities: \"the " \
                               "cards exiled with it\"); restrict with `any_of`/`not` for its card types.",
                  rules: %w[607.2a 406.6 115.1],
                  example: { "exiled_with" => { "any_of" => ["creature"] } }

        def self.zone = :exile
        def self.candidates(_engine, _controller) = []

        def self.candidates_for(engine, _controller, source, ctx: nil, **)
          source ? Linked.exiled_with(engine, source, ctx) : []
        end

        def self.match_for?(engine, ref, controller, source, **) = candidates_for(engine, controller, source).include?(ref)
      end
    end
  end
end
