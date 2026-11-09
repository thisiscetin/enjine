# frozen_string_literal: true

module Enjine
  module Mechanics
    module Types
      # Kindred (CR 308). A kindred card always has another card type, and is cast and resolves by that
      # type's rules (CR 308.1): a "Kindred Instant" is an instant. Its subtypes are creature types
      # (CR 308.2, 205.3m), so "Goblin spells" and "the number of creature types" see them.
      class Kindred < Primitive
        primitive :type, :kindred,
                  description: "A card type that goes with another one (\"Kindred Sorcery — Goblin\"): the card is " \
                               "cast and resolves as its other type, and its subtypes are creature types.",
                  rules: %w[308.1 308.2 205.3m],
                  example: { "name" => "Example Goblin Gambit", "mana_cost" => "{R}", "types" => %w[kindred sorcery],
                             "subtypes" => ["goblin"],
                             "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                                            "effects" => [{ "deal_damage" => { "amount" => 1,
                                                                                               "to" => { "target" => 0 } } }] } }] }

        def self.permanent? = false
        def self.playable_as_land? = false
        def self.instant_speed? = false

        # CR 308.1: each kindred card has another card type.
        def self.validate(card, errors)
          errors << "types: a kindred card needs another card type (CR 308.1)" if (Array(card["types"]).map(&:to_s) - ["kindred"]).empty?
        end
      end
    end
  end
end
