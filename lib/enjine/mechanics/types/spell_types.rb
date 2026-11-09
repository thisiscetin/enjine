# frozen_string_literal: true

module Enjine
  module Mechanics
    module Types
      # Instants and sorceries: never permanents; they go to the graveyard on resolution (CR 608.2n).
      class SpellType < Primitive
        def self.permanent? = false
        def self.playable_as_land? = false
        def self.validate(_card, _errors) = nil
      end

      # Instant (CR 304). Cast any time you have priority.
      class Instant < SpellType
        primitive :type, :instant,
                  description: "A spell cast any time its controller has priority. Its spell ability resolves, " \
                               "then it goes to the graveyard.",
                  rules: %w[304.1 304.2 608.2n],
                  example: { "name" => "Lightning Bolt", "mana_cost" => "{R}", "types" => ["instant"],
                             "abilities" => [{ "spell" => { "targets" => ["any_target"],
                                                            "effects" => [{ "deal_damage" => { "amount" => 3,
                                                                                               "to" => { "target" => 0 } } }] } }] }

        def self.instant_speed? = true
      end

      # Sorcery (CR 307). Main phase, empty stack, own turn.
      class Sorcery < SpellType
        primitive :type, :sorcery,
                  description: "A spell cast only in its controller's main phase while the stack is empty.",
                  rules: %w[307.1 307.2 608.2n],
                  example: { "name" => "Divination", "mana_cost" => "{2}{U}", "types" => ["sorcery"],
                             "abilities" => [{ "spell" => { "effects" => [{ "draw" => { "amount" => 2 } }] } }] }

        def self.instant_speed? = false
      end
    end
  end
end
