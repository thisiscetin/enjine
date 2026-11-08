# frozen_string_literal: true

module Enjine
  module Actions
    # CR 605.3a: a player may activate a mana ability whenever they have priority.
    # It resolves immediately (CR 605.3b). Mana is always tapped manually, one source at a time.
    class ActivateManaAbility
      def self.doc
        '`{type: "activate_mana", object: id, ability: index}` — activate a mana ability; it resolves immediately (CR 605.3).'
      end

      def self.options(engine, index)
        engine.all_mana_sources(index).map { |id, i| { type: "activate_mana", object: id, ability: i } }
      end

      def self.perform(engine, index, option)
        engine.activate_mana_ability!(index, option[:object], option[:ability])
        engine.action_taken!(index)
      end
    end
    register("activate_mana", ActivateManaAbility)
  end
end
