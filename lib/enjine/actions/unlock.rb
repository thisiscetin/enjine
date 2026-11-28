# frozen_string_literal: true

module Enjine
  module Actions
    # CR 116.2m, 709.5e: unlocking a locked door of a Room permanent you control is a special action, taken any time
    # you have priority and the stack is empty during a main phase of your turn: you pay that door's mana cost (its
    # unlock cost) in a "pay" frame, which can be cancelled, then get priority again (CR 116.3).
    class Unlock
      def self.doc
        '`{type: "unlock", object: id, door: "left" | "right"}` — unlock a locked door of a Room you control by paying ' \
          "that door's mana cost (a special action, during a main phase of your turn with an empty stack, CR 116.2m, 709.5e)."
      end

      def self.options(engine, index) = engine.unlock_options(index)

      def self.perform(engine, index, option)
        engine.begin_payment!(index, engine.door_cost(engine.object(option[:object]), option[:door]), option[:object],
                              special: { "object" => option[:object], "unlock" => option[:door] })
      end
    end
    register("unlock", Unlock)
  end
end
