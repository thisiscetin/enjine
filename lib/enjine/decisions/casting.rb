# frozen_string_literal: true

module Enjine
  module Decisions
    CANCEL = { type: "cancel" }.freeze

    # CR 734.1: a cast or activation can be rewound ("cancel") until something irreversible has been
    # paid (Engine::Payment#cancellable?); a triggered ability being put on the stack never can.
    def self.with_cancel(engine, options) = engine.cancellable? ? options + [CANCEL] : options

    # CR 601.2b / 603.3c: choose a mode of a modal spell or ability, one per decision.
    class ChooseMode < Base
      def self.doc
        'Choose a mode of a modal ("choose one") spell or ability: `{type: "mode", mode: index}` ' \
          '(0-based, in printed order); `{type: "done"}` once enough are chosen when more are allowed; ' \
          '`{type: "cancel"}` rewinds a cast. `choose` modes in total (at least `min`).'
      end

      def self.options(engine, _pending) = Decisions.with_cancel(engine, engine.mode_options)

      def self.submit(engine, _pending, option)
        case option[:type]
        when "cancel" then engine.cancel_casting!
        when "done" then engine.modes_done!
        else engine.choose_mode!(option[:mode])
        end
      end
    end
    register("choose_mode", ChooseMode)

    # CR 601.2b / 702.33a: announce whether an optional additional cost (kicker) will be paid.
    class ChooseKicker < Base
      def self.doc
        'While casting a spell with kicker: `{type: "kick"}` pays the kicker cost too, `{type: "no_kick"}` ' \
          "doesn't; `{type: \"cancel\"}` rewinds. `cost` describes the kicker cost."
      end

      def self.options(engine, _pending) = Decisions.with_cancel(engine, engine.kicker_options)

      def self.submit(engine, _pending, option)
        option[:type] == "cancel" ? engine.cancel_casting! : engine.announce_kicker!(option[:type] == "kick")
      end
    end
    register("choose_kicker", ChooseKicker)

    # CR 601.2b / 107.3a: announce the value of X for a cost with {X}.
    class ChooseX < Base
      def self.doc
        'While casting/activating a spell or ability with {X} in its cost: `{type: "x", value: n}` ' \
          'announces X (0 up to `max`, the most the available mana could pay for); `{type: "cancel"}` rewinds.'
      end

      def self.options(engine, pending) = Decisions.with_cancel(engine, (0..pending["max"]).map { { type: "x", value: it } })

      def self.submit(engine, _pending, option)
        option[:type] == "cancel" ? engine.cancel_casting! : engine.announce_x!(option[:value])
      end
    end
    register("choose_x", ChooseX)

    # CR 601.2c: a variable number of targets ("X target", "any number of target", "up to N") is announced
    # before the targets are chosen.
    class ChooseTargetCount < Base
      def self.doc
        'While casting/activating: `{type: "count", count: n}` announces how many targets (from `min` to ' \
          '`max`, at most as many as there are legal ones) target ##`index` + 1 will have; `{type: "cancel"}` rewinds.'
      end

      def self.options(engine, _pending) = Decisions.with_cancel(engine, engine.target_count_options)

      def self.submit(engine, _pending, option)
        option[:type] == "cancel" ? engine.cancel_casting! : engine.choose_target_count!(option[:count])
      end
    end
    register("choose_target_count", ChooseTargetCount)

    # CR 601.2c: choose the next target of the spell or ability being cast.
    class ChooseTarget < Base
      def self.doc
        'While casting/activating: `{type: "target", target: ref}` for the next target (ref is an ' \
          'object id or "player:<name>"); `{type: "done"}` chooses no more for an "up to" target; ' \
          '`{type: "cancel"}` rewinds the whole cast.'
      end

      def self.options(engine, _pending) = Decisions.with_cancel(engine, engine.target_options)

      def self.submit(engine, _pending, option)
        case option[:type]
        when "cancel" then engine.cancel_casting!
        when "done" then engine.choose_target!(nil)
        else engine.choose_target!(option[:target])
        end
      end
    end
    register("choose_target", ChooseTarget)

    # CR 601.2d: divide an amount (counters, damage) among the chosen targets, one unit at a time
    # beyond the one each target must get.
    class Distribute < Base
      def self.doc
        'While casting: `{type: "assign", target: ref}` gives one more of the divided amount to that target ' \
          '(each target already has one); `{type: "cancel"}` rewinds. `left` is what remains to divide.'
      end

      def self.options(engine, _pending) = Decisions.with_cancel(engine, engine.distribute_options)

      def self.submit(engine, _pending, option)
        option[:type] == "cancel" ? engine.cancel_casting! : engine.distribute!(option[:target])
      end
    end
    register("distribute", Distribute)

    # CR 601.2h / 602.2b: a cost that needs a choice, e.g. which other creature to tap (CR 702.184a)
    # or which creature to sacrifice. Tapping happens at once; other choices are paid as it becomes
    # cast. Cancelling rewinds it.
    class ChooseCost < Base
      def self.doc
        'While casting/activating: `{type: "cost", object: id}` picks the permanent (or card) a cost uses ' \
          '(the creature to tap for station, the creature to sacrifice, the creature beamed up, ...); `{type: "done"}` ' \
          "stops choosing for a cost of any number of permanents once enough are chosen (crew: total power N or " \
          'more); `{type: "cancel"}` rewinds. `cost` describes the cost.'
      end

      def self.options(engine, _pending)
        options = engine.cost_choice_candidates.map { { type: "cost", **it } }
        options << { type: "done" } if engine.cost_choice_finishable?
        Decisions.with_cancel(engine, options)
      end

      def self.submit(engine, _pending, option)
        case option[:type]
        when "cancel" then engine.cancel_casting!
        when "done" then engine.finish_cost_choice!
        else engine.choose_cost!(option)
        end
      end
    end
    register("choose_cost", ChooseCost)

    # CR 601.2g-h: pay the mana cost one mana at a time. Mana abilities may be activated
    # now; mana in the pool is spent one symbol per decision. Also used for a cost paid while a
    # spell or ability resolves (CR 118.12), where "cancel" declines to pay.
    class PayCost < Base
      def self.doc
        'While casting/activating or paying a cost: `{type: "pay_mana", mana: "R"}` spends one mana from ' \
          'the pool (`restricted: i`: restricted mana, CR 106.6), `{type: "activate_mana", object: id, ability: ref}` ' \
          '(plus `mana: "{G}{G}"` when the mana is chosen) taps a source, `{type: "cancel"}` ' \
          "rewinds (or declines a payment asked for while resolving). Cancel isn't offered once a mana ability " \
          "with a cost other than {T} (a Treasure) has been activated. `{type: \"convoke\", object: id}` taps a " \
          "creature to pay for {1} or one mana of its color (a spell with convoke). `remaining` shows what is left to pay."
      end

      def self.options(engine, _pending)
        Decisions.with_cancel(engine, engine.payable_mana_options + engine.payment_mana_options + engine.convoke_options)
      end

      def self.submit(engine, _pending, option)
        case option[:type]
        when "cancel" then engine.cancel_payment!
        when "pay_mana" then engine.pay_mana!(option[:mana], option[:restricted])
        when "convoke" then engine.convoke!(option[:object]) # CR 702.51a
        else engine.tap_for_payment!(option[:object], option[:ability], option[:mana])
        end
      end
    end
    register("pay_cost", PayCost)
  end
end
