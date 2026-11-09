# frozen_string_literal: true

module Enjine
  module Decisions
    # An "as this enters" choice (CR 614.12), e.g. pay life or enter tapped, a number or a card name.
    class EnterChoice < Base
      def self.doc
        'Before `object` enters: `{type: "pay_life", life: n}` (only with enough life) or ' \
          '`{type: "enter_tapped"}` (CR 614.12, 119.4); `{type: "number", number: n}` for "choose a number"; ' \
          '`{type: "name", name: "..."}` for "choose a card name" (CR 201.4). With `effect: true` the permanent ' \
          "is being put onto the battlefield by a resolving effect (a token about to be created has `card`); " \
          "with several entering at once, each is asked in turn before any enters (CR 614.12a-b)."
      end

      def self.options(engine, pending) = engine.entering_options(pending)
      def self.submit(engine, _pending, option) = engine.enter_choice!(option)
    end
    register("enter_choice", EnterChoice)
  end
end
