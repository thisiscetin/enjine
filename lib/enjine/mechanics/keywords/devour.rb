# frozen_string_literal: true

require_relative "../abilities/entering_choices"

module Enjine
  module Mechanics
    module Abilities
      # Devour N / devour [quality] N (CR 702.82a, 702.82c): "As this object enters, you may sacrifice any number
      # of creatures ([quality] permanents). This permanent enters with N +1/+1 counters on it for each one
      # sacrificed this way." An "as this enters" choice of any number of permanents, picked one at a time
      # (enter_choice `{type: "devour", object: id}`, then `{type: "done"}`); they're sacrificed as it enters,
      # and it remembers how many it devoured (memory "devoured", CR 702.82b).
      class Devour < EnteringChoice
        primitive :ability, :devour,
                  description: "Devour `amount`: as this permanent enters, you may sacrifice any number of permanents " \
                               "matching `each` (default \"creature\"; \"land\" for devour land) that you control, one " \
                               "at a time; it enters with `amount` +1/+1 counters for each.",
                  rules: %w[702.82a 702.82b 702.82c 614.12 701.21a],
                  params: { "amount" => "integer >= 1", "each" => "permanent filter (default \"creature\")" },
                  example: { "devour" => { "amount" => 3, "each" => "land" } }

        attr_reader :amount

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[amount each], errors, path)
          amount = Mechanics.integer_param(params, :amount, errors, path, min: 1)
          raw = Mechanics.fetch_param(params, :each) || "creature"
          new(amount, Selector.build({ "each" => raw, "controller" => "you" }, errors, "#{path}.each", targets_count: 0))
        end

        def initialize(amount, selector)
          super()
          @amount = amount
          @selector = selector
          freeze
        end

        def to_s = "Devour #{amount} (#{@selector})"

        # The permanents still to pick from, then "done" (CR 702.82a: any number, so none is fine).
        def pick_options(engine, controller, chosen)
          ctx = EffectContext.new(controller, nil, nil, [], [])
          (@selector.resolve(engine, ctx) - chosen).map { { type: "devour", object: it } } + [{ type: "done" }]
        end

        def enters_for(answer)
          count = Array(answer[:objects]).size
          { "counters" => count.positive? ? { "+1/+1" => amount * count } : {}, "memory" => { "devoured" => count } }
        end

        # As it enters: the chosen permanents still there are sacrificed (CR 701.21a).
        def pay!(engine, controller, answer)
          Array(answer["objects"]).each do |id|
            obj = engine.state.objects[id]
            engine.move!(id, :graveyard, reason: "sacrifice") if obj&.zone == :battlefield && obj.controller == controller
          end
        end
      end
    end
  end
end
