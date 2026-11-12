# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # "Plot [cost]" (CR 702.170a-b, 116.2k): any time you have priority during your turn, if the stack is empty
      # and it's your main phase, you may pay `cost` and exile this card from your hand (a special action,
      # `{type: "special_action"}`). It becomes a plotted card (Effects::Plot.plot!): its owner may cast it
      # without paying its mana cost during their main phase while the stack is empty, on a later turn
      # (cast option `via: "plotted"`, Engine::AltCasting#plotted_methods).
      class Plot < Primitive
        primitive :ability, :plot,
                  description: "Plot `cost`: during your main phase, while the stack is empty, you may pay `cost` and " \
                               "exile this card from your hand (special action `{type: \"special_action\"}`). It becomes " \
                               "plotted: on a later turn you may cast it from exile without paying its mana cost, " \
                               "during your main phase while the stack is empty (cast option `via: \"plotted\"`).",
                  rules: %w[702.170a 702.170b 702.170d 116.2k],
                  params: { "cost" => "mana cost string" },
                  example: { "plot" => { "cost" => "{1}{R}" } }

        attr_reader :special_cost

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost], errors, path)
          new(Costs::ManaPayment.build(Mechanics.fetch_param(params, :cost).to_s, errors, "#{path}.cost").mana_cost)
        end

        def initialize(cost)
          super()
          @special_cost = cost
          freeze
        end

        def kind = :plot
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        def to_s = "Plot #{special_cost}"

        # CR 702.170a: during your turn, in your main phase, with an empty stack (as a sorcery, whatever its type).
        def special_allowed?(engine, obj, index) = obj.zone == :hand && engine.sorcery_timing?(index)

        def special!(engine, obj, _index) = Effects::Plot.plot!(engine, obj.id)
      end
    end

    module Effects
      # "It becomes plotted" / "plot that card" (CR 702.170c-d): the card is exiled face up (or stays exiled) and
      # becomes a plotted card, remembering the turn. Its owner may cast it without paying its mana cost on a later
      # turn, during their main phase while the stack is empty.
      class Plot < Effect
        primitive :effect, :plot,
                  description: "Each referenced card or spell is exiled (if it isn't already) and becomes plotted: its " \
                               "owner may cast it from exile without paying its mana cost during their main phase while " \
                               "the stack is empty, on any later turn (cast option `via: \"plotted\"`).",
                  rules: %w[702.170c 702.170d 406.1],
                  params: { "to" => "selector (a spell, a card, or an exiled card such as {\"result\": 0})" },
                  example: { "plot" => { "to" => { "target" => 0 } } }

        def self.keys = %w[to if]

        def self.plot!(engine, id)
          obj = engine.state.objects[id] or return
          fresh = obj.zone == :exile ? obj : engine.move!(id, :exile, reason: "plot")
          fresh.memory["plotted"] = engine.state.turn if fresh&.zone == :exile
        end

        def apply(engine, ctx)
          refs(engine, ctx).each do |id|
            obj = engine.state.objects[id]
            Plot.plot!(engine, id) if obj && !obj.ability? && obj.kind == "card"
          end
        end

        def to_s = "plot → #{to}"
      end
    end
  end
end
