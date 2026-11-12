# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Creates a delayed triggered ability (CR 603.7): "at the beginning of the next end step,
      # return it". It is defined here, in the card data, and addressed as "delayed:<path>".
      class DelayedTrigger < Effect
        primitive :effect, :delayed_trigger,
                  description: "Creates a delayed triggered ability with the controller and source of the resolving " \
                               "spell or ability. It triggers only once, the next time `when` happens (e.g. " \
                               "{\"step_begins\": {\"step\": \"end\", \"whose\": \"each\"}} for the next end step). Its " \
                               "`effects` may use {\"result\": n} for what earlier effects of the creating list moved or " \
                               "created; those objects are affected only if they are still where they were put.",
                  rules: %w[603.7a 603.7b 603.7c 603.7d 603.7e],
                  params: { "when" => "a trigger condition", "effects" => "list of effects",
                            "watch" => "selector resolved now (e.g. {\"target\": 0}): the objects its trigger subject " \
                                       "\"watched\" and its effects' selector \"watched\" mean (\"when that creature dies\")",
                            "this_turn" => "true: it lasts until the end of this turn and triggers each time " \
                                           "(\"whenever ... this turn\", CR 603.7b); \"once\": only the next time " \
                                           "this turn (\"at the beginning of the next combat this turn\")" },
                  example: { "delayed_trigger" => { "when" => { "step_begins" => { "step" => "end", "whose" => "each" } },
                                                    "effects" => [{ "sacrifice" => { "to" => { "result" => 0 } } }] } }

        attr_reader :ref, :delayed_ability

        def self.keys = %w[when effects watch this_turn]
        def self.default_to = "you"

        def setup(params, errors, path)
          @ref = "delayed:#{path}"
          raw = Mechanics.fetch_param(params, :when)
          trigger = raw.nil? ? ((errors << "#{path}.when: required") && nil) : Mechanics.build_entry(:trigger, raw, errors, "#{path}.when")
          effects = Abilities::StackAbility.parse_effects(params, errors, path, 0, results_count: @results_count)
          errors << "#{path}.effects: needs at least one effect" if effects.empty?
          @delayed_ability = Abilities::TriggeredAbility.new(targets: [].freeze, effects: effects, trigger: trigger)
          raw_watch = Mechanics.fetch_param(params, :watch)
          @watch = raw_watch && Selector.build(raw_watch, errors, "#{path}.watch", targets_count: @targets_count,
                                                                                   results_count: @results_count)
          @this_turn = Mechanics.fetch_param(params, :this_turn)
          errors << "#{path}.this_turn: must be true, false or \"once\"" unless [nil, true, false, "once"].include?(@this_turn)
        end

        def nested_effects = delayed_ability.effects
        def to_s = "delayed#{" this turn" if @this_turn}: #{delayed_ability}#{" (watching #{@watch})" if @watch}"

        # CR 603.7d-e: controlled by the resolving object's controller, from the same source. It
        # remembers the results it may name and the objects it watches (CR 603.7c).
        def apply(engine, ctx)
          entry = { "controller" => ctx.controller, "source" => ctx.source, "card" => engine.object(ctx.object).card,
                    "ability" => ref, "results" => Snapshot.deep_copy(ctx.results || []) }
          entry["watched"] = @watch.resolve(engine, ctx) if @watch
          entry["turn"] = engine.state.turn if @this_turn
          entry["once"] = true if @this_turn == "once" # CR 603.7b: the next time only, and only this turn
          engine.create_delayed_trigger!(entry)
        end
      end

      # A reflexive triggered ability (CR 603.12): "When you do, [effect]". Put it where the action it
      # depends on is known to have happened, usually a "may"'s `then`. It triggers at once and goes on the
      # stack the next time a player would receive priority, with its own targets chosen then (CR 603.3d).
      class ReflexiveTrigger < Effect
        primitive :effect, :reflexive_trigger,
                  description: "Creates a reflexive triggered ability (\"when you do, ...\") that triggers immediately, " \
                               "with the controller and source of the resolving spell or ability. Its `targets` are " \
                               "chosen as it's put on the stack; its `effects` may name the results of earlier effects " \
                               "of the creating list. With `if`, it triggers only when the condition holds " \
                               "(\"when excess damage is dealt this way\").",
                  rules: %w[603.12 603.12a 603.7d 603.7e 603.3d],
                  params: { "targets" => "list of target filters", "effects" => "list of effects", "if" => "condition",
                            "divide" => "amount divided among the targets as it's put on the stack (CR 601.2d)" },
                  example: { "reflexive_trigger" => { "targets" => ["any_target"],
                                                      "effects" => [{ "deal_damage" => { "amount" => 2,
                                                                                         "to" => { "target" => 0 } } }] } }

        # Stands in for the trigger condition on the stack ability ("When you do").
        WhenYouDo = Data.define do
          def to_s = "When you do"
        end

        attr_reader :ref, :delayed_ability

        def self.keys = %w[targets effects divide if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @ref = "reflexive:#{path}"
          targets = Abilities::StackAbility.parse_targets(params, errors, path)
          effects = Abilities::StackAbility.parse_effects(params, errors, path, targets.size, results_count: @results_count)
          errors << "#{path}.effects: needs at least one effect" if effects.empty?
          extras = Abilities::StackAbility.parse_extras(params.slice("divide"), errors, path)
          Abilities::StackAbility.check_divide(extras, targets, errors, path)
          @delayed_ability = Abilities::TriggeredAbility.new(targets: targets, effects: effects, trigger: WhenYouDo.new,
                                                             extras: extras)
        end

        def nested_effects = delayed_ability.effects
        def to_s = "reflexive: #{delayed_ability}"

        def apply(engine, ctx)
          # Created by a replacement's follow-up (Engine::FollowUps), its spell may be long gone: its card is remembered.
          memory = Selector.memory(engine, ctx)
          card = engine.state.objects[ctx.object]&.card || memory["source_card"]
          source = { "id" => ctx.source, "card" => card, "controller" => ctx.controller, "ability" => ref }
          engine.queue_pending_trigger!(source, nil, { "results" => Snapshot.deep_copy(ctx.results || []),
                                                       "amounts" => (ctx.amounts || []).dup,
                                                       "triggering" => memory["triggering"]&.dup,
                                                       "departed" => engine.departed_snapshot }.compact)
        end
      end
    end
  end
end
