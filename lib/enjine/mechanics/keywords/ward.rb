# frozen_string_literal: true

require_relative "../effects/pay"

module Enjine
  module Mechanics
    module Abilities
      # Ward (CR 702.21a): "Whenever this permanent becomes the target of a spell or ability an opponent
      # controls, counter that spell or ability unless that player pays [cost]." A triggered ability: it
      # triggers as the target is chosen (CR 601.2c), goes on the stack once the spell is cast, and on
      # resolution the targeting spell's controller may pay. Engine#choose_target! tells the trigger which
      # spell or ability targeted it (its memory "targeted_by").
      class Ward < TriggeredAbility
        primitive :ability, :ward,
                  description: "Ward: whenever this permanent becomes the target of a spell or ability an opponent " \
                               "controls, counter that spell or ability unless its controller pays `cost`.",
                  rules: %w[702.21a 601.2c 603.2 701.6a],
                  params: { "cost" => "mana cost string, e.g. \"{2}\"" },
                  example: { "ward" => { "cost" => "{2}" } }

        # The trigger: this permanent becomes the target of an opponent's spell or ability.
        class BecomesTarget
          def event_class = Events::TargetChosen
          def watches?(event) = event.is_a?(Events::TargetChosen)
          def leaves_battlefield? = false
          def to_s = "When this becomes the target of a spell or ability an opponent controls"

          def match?(engine, event, source)
            return false unless event.target == source["id"]

            engine.names.index(event.player) != source["controller"]
          end
        end

        # Counters the spell or ability that targeted the permanent unless its controller pays.
        class Counter < Effects::CounterUnlessPays
          def refs(engine, ctx) = [engine.object(ctx.object).memory["targeted_by"]]
          def to_s = "counter that spell or ability unless its controller pays #{cost}"
        end

        TRIGGER = BecomesTarget.new.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost], errors, path)
          raw = Mechanics.fetch_param(params, :cost)
          errors << "#{path}.cost: required" if raw.nil?
          effect = Counter.new(to: nil, params: { "mana" => raw || "{0}" }, errors: errors, path: "#{path}.cost")
          new(targets: [].freeze, effects: [effect].freeze, trigger: TRIGGER)
        end

        def to_s = "Ward #{effects.first.cost}"
      end
    end
  end
end
