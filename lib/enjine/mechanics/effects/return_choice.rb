# frozen_string_literal: true

require_relative "sacrifice"

module Enjine
  module Mechanics
    module Effects
      # "Return a land you control to its owner's hand": like sacrifice_choice, each referenced player
      # chooses permanents they control matching `filter` (a choice, not a target), in turn order starting
      # with the active player (CR 101.4); then all of them are put into their owners' hands at once.
      class ReturnChoice < SacrificeChoice
        primitive :effect, :return_choice,
                  description: "Each referenced player (default: you) returns `count` (default 1; \"any\": any number) " \
                               "permanents they control matching `filter` to their owners' hands, chosen by them in " \
                               "turn order starting with the active player (not targeted); all move at once.",
                  rules: %w[101.4 400.7 608.2c],
                  params: { "filter" => "a filter, e.g. \"land\"", "count" => "integer or \"any\"",
                            "to" => "selector of players" },
                  example: { "return_choice" => { "filter" => "land" } }

        def finish!(engine, id) = engine.move!(id, :hand, reason: "return")
        def choosable?(_engine, obj, index) = obj.zone == :battlefield && obj.controller == index
        def verb = "return"

        def to_s = "#{to} returns #{count == "any" ? "any number of" : count} #{words} of their choice to its owner's hand"
      end
    end
  end
end
