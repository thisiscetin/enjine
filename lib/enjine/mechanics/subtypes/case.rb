# frozen_string_literal: true

require_relative "../abilities/designated"

module Enjine
  module Mechanics
    module Effects
      # "This Case becomes solved" (CR 720.3a-b): each referenced permanent that isn't solved becomes solved.
      class Solve < Effect
        primitive :effect, :solve,
                  description: "Each referenced permanent (default: this one) becomes solved if it isn't (a designation it " \
                               "keeps until it leaves the battlefield). Usually written through `to_solve`.",
                  rules: %w[720.3a 720.3b],
                  params: { "to" => "selector of permanents (default self)" },
                  example: { "solve" => {} }

        def self.keys = %w[to if]
        def self.default_to = "self"

        def apply(engine, ctx)
          refs(engine, ctx).each { (obj = engine.state.objects[it]) && engine.designate!(obj, "solved") }
        end

        def to_s = "#{to} becomes solved"
      end
    end

    module Abilities
      # A Case's "To solve — [condition]" (CR 720.3a): "At the beginning of your end step, if [condition] and this
      # Case is not solved, this Case becomes solved." Written {"to_solve": condition}; it builds that triggered ability.
      class ToSolve < Primitive
        primitive :ability, :to_solve,
                  description: "A Case's \"To solve — [condition]\": at the beginning of your end step, if the condition " \
                               "holds and this Case isn't solved, it becomes solved (an intervening-if triggered ability). " \
                               "The parameter is the condition itself.",
                  rules: %w[720.3a 720.3b 603.4],
                  params: { "(condition)" => "any condition, e.g. {\"hand_size\": \"you\", \"at_most\": 0}" },
                  example: { "to_solve" => { "amount" => { "life_gained_this_turn" => "you" }, "at_least" => 5 } }

        def self.build(params, errors, path, **)
          unless params.is_a?(Hash) && !params.empty?
            errors << "#{path}: must be a condition, e.g. {\"amount\": {\"life_gained_this_turn\": \"you\"}, \"at_least\": 5}"
            return nil
          end
          data = { "when" => { "step_begins" => { "step" => "end", "whose" => "your" } },
                   "if" => { "all" => [params, { "solved" => false }] }, "effects" => [{ "solve" => {} }] }
          TriggeredAbility.build(data, errors, path)
        end
      end

      # "Solved — [ability]" (CR 702.169, 720.3c): the ability works only while this Case is solved (see
      # DesignatedAbility). {"solved": {"activated": {...}}}.
      class Solved < Primitive
        primitive :ability, :solved,
                  description: "A Case's \"Solved — [ability]\": one static, triggered or activated ability that works " \
                               "only while this permanent is solved (a static applies as long as it's solved, a triggered " \
                               "ability triggers only if it's solved, an activated ability can be activated only if it's " \
                               "solved). Condition `{\"solved\": true}` reads the designation.",
                  rules: %w[702.169a 702.169b 702.169c 702.169d 720.3b 720.3c],
                  params: { "(ability)" => "{\"static\" | \"triggered\" | \"activated\": {...}}" },
                  example: { "solved" => { "activated" => { "cost" => ["sacrifice"],
                                                            "effects" => [{ "draw" => { "amount" => 1 } }] } } }

        def self.build(params, errors, path, **) = DesignatedAbility.build("solved", params, errors, path)
      end
    end
  end
end
