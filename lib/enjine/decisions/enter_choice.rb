# frozen_string_literal: true

module Enjine
  module Decisions
    # An "as this enters" choice (CR 614.12), e.g. pay life or enter tapped.
    class EnterChoice < Base
      def self.doc
        'Before `object` enters: `{type: "pay_life", life: n}` (only with enough life) or ' \
          '`{type: "enter_tapped"}` (CR 614.12, 119.4).'
      end

      def self.options(engine, pending) = engine.entering_choice(pending["object"]).options(engine, pending["player"])
      def self.submit(engine, _pending, option) = engine.enter_choice!(option)
    end
    register("enter_choice", EnterChoice)
  end
end
