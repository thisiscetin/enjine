# frozen_string_literal: true

require_relative "../abilities/designated"

module Enjine
  module Mechanics
    module Effects
      # "Harness [this permanent]" (CR 701.64a): "If this permanent isn't harnessed, it becomes harnessed." Harnessed is
      # a designation it keeps until it leaves the battlefield, not an ability or a copiable value (CR 701.64b).
      class Harness < Effect
        primitive :effect, :harness,
                  description: "Each referenced permanent (default: this one) becomes harnessed if it isn't (a designation " \
                               "it keeps until it leaves the battlefield). Its `infinity` abilities work while it is.",
                  rules: %w[701.64a 701.64b],
                  params: { "to" => "selector of permanents (default self)" },
                  example: { "harness" => {} }

        def self.keys = %w[to if]
        def self.default_to = "self"

        def apply(engine, ctx)
          refs(engine, ctx).each { (obj = engine.state.objects[it]) && engine.designate!(obj, "harnessed") }
        end

        def to_s = "harness #{to}"
      end
    end

    module Abilities
      # "∞ — [ability]" (CR 702.186): "As long as this permanent is harnessed, it has [ability]" (see
      # DesignatedAbility). {"infinity": {"triggered": {...}}}.
      class Infinity < Primitive
        primitive :ability, :infinity,
                  description: "An Infinity card's \"∞ — [ability]\": one static, triggered or activated ability that works " \
                               "only while this permanent is harnessed. Condition `{\"harnessed\": true}` reads the " \
                               "designation.",
                  rules: %w[702.186a 702.186b 701.64b],
                  params: { "(ability)" => "{\"static\" | \"triggered\" | \"activated\": {...}}" },
                  example: { "infinity" => { "triggered" => { "when" => { "step_begins" => { "step" => "upkeep", "whose" => "your" } },
                                                              "effects" => [{ "draw" => { "amount" => 1 } }] } } }

        def self.build(params, errors, path, **) = DesignatedAbility.build("harnessed", params, errors, path)
      end
    end
  end
end
