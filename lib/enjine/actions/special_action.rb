# frozen_string_literal: true

module Enjine
  module Actions
    # CR 116.2f, 116.2h: special actions that pay a cost and exile a card from your hand (foretell, suspend).
    # The card's ability names the cost, when the action is allowed and what it does; the cost is paid in a
    # "pay" frame (Engine::Payment#begin_payment!), which can be cancelled, and the player gets priority
    # again afterwards (CR 116.3).
    class SpecialAction
      def self.doc
        '`{type: "special_action", object: id, ability: ref}` — a special action of a card in your hand: foretell ' \
          "(during your turn, pay {2} and exile it face down, CR 116.2h) or suspend (when you could begin to cast it, " \
          "pay its suspend cost and exile it with time counters, CR 116.2f)."
      end

      def self.options(engine, index)
        engine.player(index).hand.flat_map do |id|
          obj = engine.object(id)
          engine.chars(obj).abilities.filter_map do |inst|
            ability = inst.ability
            next unless ability.respond_to?(:special!) && ability.special_allowed?(engine, obj, index)
            next unless engine.affordable?(index, ability.special_cost, nil)

            { type: "special_action", object: id, ability: inst.ref }
          end
        end
      end

      def self.perform(engine, index, option)
        ability = engine.chars(option[:object]).ability(option[:ability])
        engine.begin_payment!(index, ability.special_cost, option[:object],
                              special: { "object" => option[:object], "ability" => option[:ability] })
      end
    end
    register("special_action", SpecialAction)
  end
end
