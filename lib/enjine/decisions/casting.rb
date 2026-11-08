# frozen_string_literal: true

module Enjine
  module Decisions
    CANCEL = { type: "cancel" }.freeze

    # CR 601.2b / 603.3c: choose a mode of a modal spell or ability, one per decision.
    class ChooseMode < Base
      def self.doc
        'Choose a mode of a modal ("choose one") spell or ability: `{type: "mode", mode: index}` ' \
          '(0-based, in printed order); `{type: "cancel"}` rewinds a cast. `choose` modes in total.'
      end

      def self.options(engine, _pending)
        options = engine.mode_options.map { { type: "mode", mode: it } }
        engine.casting["kind"] == "trigger" ? options : options + [CANCEL]
      end

      def self.submit(engine, _pending, option)
        option[:type] == "cancel" ? engine.cancel_casting! : engine.choose_mode!(option[:mode])
      end
    end
    register("choose_mode", ChooseMode)

    # CR 601.2c: choose the next target of the spell or ability being cast.
    class ChooseTarget < Base
      def self.doc
        'While casting/activating: `{type: "target", target: ref}` for the next target (ref is an ' \
          'object id or "player:<name>"), or `{type: "cancel"}` to rewind the whole cast.'
      end

      def self.options(engine, _pending)
        options = engine.target_candidates.map { { type: "target", target: it } }
        engine.casting["kind"] == "trigger" ? options : options + [CANCEL] # triggers can't be "cancelled"
      end

      def self.submit(engine, _pending, option)
        option[:type] == "cancel" ? engine.cancel_casting! : engine.choose_target!(option[:target])
      end
    end
    register("choose_target", ChooseTarget)

    # CR 601.2g-h: pay the mana cost one mana at a time. Mana abilities may be activated
    # now; mana in the pool is spent one symbol per decision.
    class PayCost < Base
      def self.doc
        'While casting/activating: `{type: "pay_mana", mana: "R"}` spends one mana from the pool, ' \
          '`{type: "activate_mana", object: id, ability: ref}` taps a source, `{type: "cancel"}` rewinds. ' \
          "`remaining` shows what is left to pay."
      end

      def self.options(engine, _pending)
        engine.payable_mana_types.map { { type: "pay_mana", mana: it } } +
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
