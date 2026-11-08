# frozen_string_literal: true

module Enjine
  module Decisions
    CANCEL = { type: "cancel" }.freeze

    # CR 601.2c: choose the next target of the spell or ability being cast.
    class ChooseTarget < Base
      def self.doc = 'While casting/activating: `{type: "target", target: ref}` for the next target (ref is an ' \
                     'object id or "player:<name>"), or `{type: "cancel"}` to rewind the whole cast.'

      def self.options(engine, _pending)
        engine.target_candidates.map { { type: "target", target: _1 } } + [CANCEL]
      end

      def self.submit(engine, _pending, option)
        option[:type] == "cancel" ? engine.cancel_casting! : engine.choose_target!(option[:target])
      end
    end
    register("choose_target", ChooseTarget)

    # CR 601.2g-h: pay the mana cost one mana at a time. Mana abilities may be activated
    # now; mana in the pool is spent one symbol per decision.
    class PayCost < Base
      def self.doc = 'While casting/activating: `{type: "pay_mana", mana: "R"}` spends one mana from the pool, ' \
                     '`{type: "activate_mana", object: id, ability: i}` taps a source, `{type: "cancel"}` rewinds. ' \
                     "`remaining` shows what is left to pay."

      def self.options(engine, _pending)
        engine.payable_mana_types.map { { type: "pay_mana", mana: _1 } } +
          engine.payment_sources.map { |id, i| { type: "activate_mana", object: id, ability: i } } + [CANCEL]
      end

      def self.submit(engine, _pending, option)
        case option[:type]
        when "cancel" then engine.cancel_casting!
        when "pay_mana" then engine.pay_mana!(option[:mana])
        else engine.tap_for_payment!(option[:object], option[:ability])
        end
      end
    end
    register("pay_cost", PayCost)
  end
end
