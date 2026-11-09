# frozen_string_literal: true

module Enjine
  module Mechanics
    module Types
      # Shared rules of permanent card types that are cast (artifact, creature,
      # enchantment, planeswalker): sorcery timing unless something grants flash (CR 307.1 analogues).
      class PermanentType < Primitive
        def self.permanent? = true
        def self.playable_as_land? = false
        def self.instant_speed? = false
        def self.validate(_card, _errors) = nil
      end

      # Creature (CR 302). Has power and toughness; can attack and block; summoning sickness (302.6).
      class Creature < PermanentType
        primitive :type, :creature,
                  description: "A permanent with power and toughness that can attack and block. Cast at sorcery " \
                               "speed. It can't attack or use {T} abilities unless controlled continuously since " \
                               "its controller's most recent turn began (summoning sickness).",
                  rules: %w[302.1 302.4 302.6 307.1],
                  example: { "name" => "Grizzly Bears", "mana_cost" => "{1}{G}", "types" => ["creature"],
                             "subtypes" => ["bear"], "power" => 2, "toughness" => 2 }

        def self.validate(card, errors)
          %w[power toughness].each { |k| errors << "#{k}: creatures need an integer #{k} (CR 302.4)" unless card.key?(k) }
        end
      end

      # Artifact (CR 301).
      class Artifact < PermanentType
        primitive :type, :artifact, description: "A permanent cast at sorcery speed.", rules: %w[301.1],
                                    example: { "name" => "Example Relic", "mana_cost" => "{2}", "types" => ["artifact"] }
      end

      # Enchantment (CR 303).
      class Enchantment < PermanentType
        primitive :type, :enchantment, description: "A permanent cast at sorcery speed.", rules: %w[303.1],
                                       example: { "name" => "Example Aura", "mana_cost" => "{1}{W}",
                                                  "types" => ["enchantment"] }
      end

      # Planeswalker (CR 306). Enters with loyalty counters; one loyalty ability per turn.
      class Planeswalker < PermanentType
        primitive :type, :planeswalker,
                  description: "A permanent that enters with loyalty counters equal to its printed loyalty. " \
                               "Its loyalty abilities can be activated at sorcery speed, one per turn. Damage dealt " \
                               "to it removes loyalty counters; at 0 loyalty it is put into its owner's graveyard.",
                  rules: %w[306.5b 306.8 120.3c 606.3 704.5i],
                  example: { "name" => "Vessa, Rally Captain", "mana_cost" => "{2}{W}{W}", "types" => ["planeswalker"],
                             "loyalty" => 3,
                             "abilities" => [{ "loyalty" => { "cost" => 1, "effects" => [
                               { "pump" => { "power" => 1, "toughness" => 1,
                                             "to" => { "each" => "creature", "controller" => "you" } } }
                             ] } }] }

        def self.validate(card, errors)
          errors << "loyalty: planeswalkers need an integer loyalty (CR 306.5b)" unless card["loyalty"].is_a?(Integer)
        end

        # CR 306.5b: a planeswalker enters with loyalty counters equal to its printed loyalty.
        def self.entering(definition, enters)
          enters["counters"]["loyalty"] = definition.loyalty if definition.loyalty
        end
      end
    end
  end
end
