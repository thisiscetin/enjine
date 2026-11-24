# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # "Choose a creature type and behold two creatures of that type" (CR 601.2b, 205.3m, 607.2d): choosing the
      # type is part of the cost. It is a `choose_cost` decision, `{type: "cost", creature_type: "elf"}`, made in
      # cost order (so before a later `behold` of `{"subtypes": "chosen"}`), and the spell remembers the type at
      # once ("chosen_type", read by "of the chosen type" filters and card specs). Cancelling the cast forgets it.
      class ChooseCreatureType < Primitive
        primitive :cost, :choose_creature_type,
                  description: "Choose a creature type as part of the cost (a `choose_cost` decision with options " \
                               "`{type: \"cost\", creature_type: t}`). The spell remembers it as its chosen type: later " \
                               "costs and its effects read it with `\"subtypes\": \"chosen\"`.",
                  rules: %w[601.2b 205.3m 607.2d],
                  example: { "choose_creature_type" => {} }

        INSTANCE = new.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          INSTANCE
        end

        def mana? = false
        def choices_needed = 1
        def payable?(_engine, _object) = true

        def choice_options(_engine, _object, _chosen) = Chosen.values("creature_type", []).map { { creature_type: it } }

        # The spell being cast remembers the type now, so a later cost of "that type" can be chosen (CR 601.2b).
        def choose!(engine, option)
          type = option[:creature_type].to_s
          spell = engine.casting && engine.state.objects[engine.casting["object"]]
          spell&.memory&.store("chosen_type", type)
          { "creature_type" => type }
        end

        def to_s = "Choose a creature type"
      end
    end
  end
end
