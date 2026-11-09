# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Earthbend N (CR 701.66a): "Target land you control becomes a 0/0 land creature with haste in addition to
      # its other types. Put N +1/+1 counters on it. When that land dies or is put into exile, return it to the
      # battlefield tapped under your control." The target is declared on the ability like any other target
      # (usually `{"land": {"controller": "you"}}`) and named by `to`. The land becomes a creature for as long as
      # it stays on the battlefield (no duration is stated, CR 611.2a), is the effect's result ("that land"), and
      # a delayed triggered ability watches it (CR 603.7c). Creating that ability is earthbending (CR 701.66b).
      class Earthbend < Effect
        primitive :effect, :earthbend,
                  description: "Earthbend `amount`: each referenced land (the target, `to`) becomes a 0/0 creature " \
                               "with haste that's still a land, gets `amount` +1/+1 counters, and when it dies or is " \
                               "put into exile it returns to the battlefield tapped under your control. The land is " \
                               "the effect's result.",
                  rules: %w[701.66a 701.66b 603.7c 611.2a 613.1d 613.4b],
                  params: { "amount" => "amount", "to" => "selector (the target land, e.g. {\"target\": 0})" },
                  example: { "earthbend" => { "amount" => 2, "to" => { "target" => 0 } } }

        # The delayed triggered ability: "When that land dies or is put into exile, return it to the battlefield
        # tapped under your control" ("it" is the card in its new zone, CR 400.7).
        RETURN = { "when" => { "any_of" => [{ "dies" => { "subject" => "watched" } },
                                            { "leaves_battlefield" => { "subject" => "watched", "to" => "exile" } }] },
                   "effects" => [{ "return_to_battlefield" => { "to" => { "triggering" => "object" }, "tapped" => true,
                                                                "under" => "you" } }] }.freeze

        attr_reader :ref, :delayed_ability

        def setup(_params, errors, path)
          @ref = "earthbend:#{path}"
          trigger = Mechanics.build_entry(:trigger, RETURN["when"], errors, "#{path}.when")
          effects = Abilities::StackAbility.parse_effects(RETURN, errors, path, 0)
          @delayed_ability = Abilities::TriggeredAbility.new(targets: [].freeze, effects: effects, trigger: trigger)
        end

        def nested_effects = delayed_ability.effects
        def to_s = "earthbend #{amount} → #{to}"

        def apply(engine, ctx)
          lands = objects(engine, ctx).select { engine.chars(it).land? }
          return if lands.empty?

          n = amount_for(engine, ctx)
          become_creature!(engine, ctx, lands)
          lands.each do |id|
            engine.record_result!(id)
            engine.add_counters!(engine.object(id), "+1/+1", n, by_player: ctx.controller)
            engine.create_delayed_trigger!("controller" => ctx.controller, "source" => ctx.source,
                                           "card" => engine.object(ctx.object).card, "ability" => ref, "watched" => [id])
            engine.emit Events::KeywordAction.new(player: engine.name(ctx.controller), action: "earthbend", amount: n)
          end
        end

        private

        # Layer 4 (a creature in addition to its other types), layer 6 (haste) and layer 7b (base 0/0), for as
        # long as it stays on the battlefield; the same continuous effects `become` creates.
        def become_creature!(engine, ctx, lands)
          lasting = { "duration" => "permanent" }
          engine.add_continuous_effect!("add_types", ctx, lands,
                                        { "types" => ["creature"], "supertypes" => [], "subtypes" => [] }.merge(lasting))
          engine.add_continuous_effect!("grant", ctx, lands, { "keywords" => ["haste"] }.merge(lasting))
          engine.add_continuous_effect!("base_power_toughness", ctx, lands, { "power" => 0, "toughness" => 0 }.merge(lasting))
        end
      end
    end
  end
end
