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
        engine.state.battlefield.flat_map do |id|
          obj = engine.object(id)
          next [] unless obj.controller == index

          engine.definition(obj).abilities.each_with_index.filter_map do |ability, i|
            { type: "activate_mana", object: id, ability: i } if ability.mana_ability? && ability.activatable?(engine, obj)
          end
        end
      end

      def self.perform(engine, index, option)
        obj = engine.object(option[:object])
        ability = engine.definition(obj).abilities.fetch(option[:ability])
        ability.costs.each { |cost| cost.pay!(engine, obj) }
        engine.add_mana!(index, ability.produce, obj.id)
        engine.action_taken!(index)
      end
    end
    register("activate_mana", ActivateManaAbility)
  end
end
