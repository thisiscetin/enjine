# frozen_string_literal: true

module Enjine
  module Decisions
    # An "as this enters" choice (CR 614.12), e.g. pay life or enter tapped, a number or a card name.
    class EnterChoice < Base
      def self.doc
        'Before `object` enters: `{type: "pay_life", life: n}` (only with enough life) or ' \
          '`{type: "enter_tapped"}` (CR 614.12, 119.4), or `{type: "behold", object: id}` (CR 701.4a); ' \
          '`{type: "number", number: n}` for "choose a number"; ' \
          '`{type: "name", name: "..."}` for "choose a card name" (CR 201.4); `{type: "color", color: "R"}`, ' \
          '`{type: "creature_type", creature_type: "elf"}`, `{type: "card_type", card_type: "artifact"}`, ' \
          '`{type: "basic_land_type", basic_land_type: "forest"}` or ' \
          '`{type: "option", option: "word"}` for the other "choose a ..." abilities (CR 607.2d). With `effect: true` the permanent ' \
          "is being put onto the battlefield by a resolving effect (a token about to be created has `card`); " \
          "with several entering at once, each is asked in turn before any enters (CR 614.12a-b)."
      end

      def self.options(engine, pending) = engine.entering_options(pending)
      def self.submit(engine, _pending, option) = engine.enter_choice!(option)
    end
    register("enter_choice", EnterChoice)
  end
end
