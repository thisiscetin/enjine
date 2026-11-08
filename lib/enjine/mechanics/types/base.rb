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

      # Instants and sorceries: never permanents; they go to the graveyard on resolution (CR 608.2n).
      class SpellType < Primitive
        def self.permanent? = false
        def self.playable_as_land? = false
        def self.validate(_card, _errors) = nil
      end
    end
  end
end
