# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Puts cards from exile or a graveyard onto the battlefield ("return that card to the
      # battlefield under its owner's control"). Usually aimed at {"result": n}: a flicker is
      # `exile` followed by `return_to_battlefield` of the exile's result.
      class ReturnToBattlefield < Effect
        UNDER = %w[owner you].freeze
        ZONES = %i[exile graveyard].freeze

        primitive :effect, :return_to_battlefield,
                  description: "Put each referenced card that is in exile or a graveyard onto the battlefield under its " \
                               "owner's control (`under: \"you\"`: under the controller's), tapped if `tapped: true`. " \
                               "A card that is no longer in the zone it was expected in, or isn't a permanent card, " \
                               "stays where it is.",
                  rules: %w[400.7 400.4a 110.2 111.8 603.7c 614.1c 122.6],
                  params: { "to" => "selector (usually {\"result\": n})", "tapped" => "boolean",
                            "under" => UNDER.join(" | "),
                            "counters" => "{counter name: n}: it enters with these counters (\"with a +1/+1 counter on it\")" },
                  example: { "return_to_battlefield" => { "to" => { "result" => 0 } } }

        attr_reader :tapped, :under, :counters

        def self.keys = %w[to tapped under counters if]

        def setup(params, errors, path)
          @tapped = Mechanics.fetch_param(params, :tapped) == true
          @under = Mechanics.fetch_param(params, :under) || "owner"
          errors << "#{path}.under: must be one of #{UNDER.join(", ")}" unless UNDER.include?(@under)
          @counters = parse_counters(Mechanics.fetch_param(params, :counters) || {}, errors, "#{path}.counters")
        end

        def parse_counters(raw, errors, path)
          return (errors << "#{path}: must be an object of counter name => count") && {} unless raw.is_a?(Hash)

          raw.to_h do |name, n|
            kind = Counters.normalize(name.to_s)
            message = Counters.error(kind)
            errors << "#{path}.#{name}: #{message}" if message
            errors << "#{path}.#{name}: must be a positive integer" unless n.is_a?(Integer) && n.positive?
            [kind, n]
          end.freeze
        end

        def to_s
          extra = counters.map { |kind, n| " with #{n} #{kind} counter(s)" }.join
          "return to the battlefield#{" tapped" if tapped}#{" under your control" if under == "you"}#{extra} → #{to}"
        end

        def apply(engine, ctx)
          enters = { "tapped" => tapped || nil, "counters" => counters.empty? ? nil : counters.dup }.compact
          cards(engine, ctx).each do |id|
            controller = under == "you" ? ctx.controller : engine.object(id).owner
            engine.move!(id, :battlefield, controller: controller, reason: "return", enters: enters.empty? ? nil : enters)
          end
        end

        # CR 400.4a: an instant or sorcery card can't enter the battlefield. CR 111.8: a token that
        # has left the battlefield can't come back (it ceases to exist at the next SBA check).
        def cards(engine, ctx)
          refs(engine, ctx).select do |id|
            obj = engine.state.objects[id]
            obj && ZONES.include?(obj.zone) && !engine.token?(obj) &&
              !(engine.chars(obj).types - %i[instant sorcery]).empty?
          end
        end
      end

      # Sacrifice permanents (CR 701.21): "sacrifice it at the beginning of the next end step".
      class Sacrifice < Effect
        primitive :effect, :sacrifice,
                  description: "The controller sacrifices each referenced permanent they control (it goes to its " \
                               "owner's graveyard; it isn't destroyed, so indestructible doesn't stop it).",
                  rules: %w[701.21a],
                  params: { "to" => "selector" },
                  example: { "sacrifice" => { "to" => { "result" => 0 } } }

        def self.keys = %w[to if]

        def apply(engine, ctx) = mine(engine, ctx).each { engine.move!(it, :graveyard, reason: "sacrifice") }

        # CR 701.21a: a player can't sacrifice a permanent they don't control.
        def mine(engine, ctx) = objects(engine, ctx).select { engine.can_sacrifice?(engine.object(it), ctx.controller) }
        def possible?(engine, ctx) = !mine(engine, ctx).empty?
      end

      # "You may [effects]. If you do, [then]. If you don't, [otherwise]." (CR 118.12): the controller
      # answers yes or no while it resolves (an effect_choice). Yes is offered only when every effect
      # in `effects` can be done fully, as for any cost (CR 118.3). `then` follows a yes and
      # `otherwise` a no, whatever the effects actually did.
      class May < ChoiceEffect
        LISTS = %w[effects then otherwise].freeze

        primitive :effect, :may,
                  description: "An optional effect. The controller chooses yes or no as it resolves; yes is offered only " \
                               "if every effect in `effects` can be done fully. On yes, `effects` then `then` (\"if you " \
                               "do\") happen; on no, `otherwise` (\"if you don't\"). Nested effects may name the results " \
                               "of earlier effects of the enclosing list.",
                  rules: %w[118.12 118.3 608.2d 608.2e],
                  params: { "effects" => "list of effects (the optional part)", "then" => "list of effects",
                            "otherwise" => "list of effects",
                            "chooser" => "who decides (default: the controller): a selector naming a player, or a " \
                                         "permanent whose controller decides (e.g. {\"target\": 0}), or " \
                                         "\"active_player\"" },
                  example: { "may" => { "effects" => [{ "discard" => { "amount" => 1 } }],
                                        "then" => [{ "draw" => { "amount" => 1 } }] } }

        def self.keys = LISTS + %w[if chooser]
        def self.default_to = "you"

        def setup(params, errors, path)
          @lists = LISTS.to_h do |key|
            [key, Abilities::StackAbility.parse_effects(params, errors, path, @targets_count, key: key.to_sym,
                                                                                              results_count: @results_count)]
          end.freeze
          errors << "#{path}.effects: needs at least one effect" if @lists["effects"].empty?
          raw = Mechanics.fetch_param(params, :chooser)
          @chooser = if raw.nil? || raw == "active_player" then raw
                     else Selector.build(raw, errors, "#{path}.chooser", targets_count: @targets_count, results_count: @results_count)
                     end
        end

        def effects = @lists["effects"]
        def nested_effects = @lists.values.flatten

        # CR 608.2e: an effect may have a player other than its controller make a choice. The chooser is
        # the named player, or the controller of the named permanent; nobody legal: the controller.
        def chooser_index(engine, ctx)
          return ctx.controller if @chooser.nil?
          return engine.state.active if @chooser == "active_player"

          ref = @chooser.resolve(engine, ctx).first
          Filters.player_index(engine, ref) || engine.state.objects[ref]&.controller || ctx.controller
        end

        def to_s
          text = "#{@chooser ? "#{@chooser} may have" : "you may"}: #{effects.join("; ")}"
          text += " — if you do: #{@lists["then"].join("; ")}" unless @lists["then"].empty?
          text += " — if you don't: #{@lists["otherwise"].join("; ")}" unless @lists["otherwise"].empty?
          text
        end

        def run(engine, ctx, locals)
          unless locals["chose"]
            return :done unless condition.nil? || condition.true?(engine, ctx)

            answer = answers(locals).first or return ask_yes_no(engine, ctx, locals)
            locals["chose"] = answer["type"]
            locals["next"] = 0
          end
          run_list(engine, ctx, locals, locals["chose"] == "yes" ? effects + @lists["then"] : @lists["otherwise"])
        end

        private

        def ask_yes_no(engine, ctx, locals)
          choices = [{ "type" => "no" }]
          choices.unshift({ "type" => "yes" }) if effects.all? { it.possible?(engine, ctx) }
          ask(engine, locals, chooser_index(engine, ctx), "You may: #{effects.join("; ")}", choices)
        end

        # The chosen list, one effect at a time; a waiting effect keeps its locals under "child"
        # (Engine#effect_answer! delivers answers there).
        def run_list(engine, ctx, locals, list)
          while locals["next"] < list.size
            return :wait if list[locals["next"]].run(engine, ctx, locals["child"] ||= {}) == :wait

            locals.delete("child")
            locals["next"] += 1
          end
          :done
        end
      end

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
                                           "(\"whenever ... this turn\", CR 603.7b)" },
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
          errors << "#{path}.this_turn: must be true or false" unless [nil, true, false].include?(@this_turn)
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
                               "of the creating list.",
                  rules: %w[603.12 603.12a 603.7d 603.7e 603.3d],
                  params: { "targets" => "list of target filters", "effects" => "list of effects" },
                  example: { "reflexive_trigger" => { "targets" => ["any_target"],
                                                      "effects" => [{ "deal_damage" => { "amount" => 2,
                                                                                         "to" => { "target" => 0 } } }] } }

        # Stands in for the trigger condition on the stack ability ("When you do").
        WhenYouDo = Data.define do
          def to_s = "When you do"
        end

        attr_reader :ref, :delayed_ability

        def self.keys = %w[targets effects]
        def self.default_to = "you"

        def setup(params, errors, path)
          @ref = "reflexive:#{path}"
          targets = Abilities::StackAbility.parse_targets(params, errors, path)
          effects = Abilities::StackAbility.parse_effects(params, errors, path, targets.size, results_count: @results_count)
          errors << "#{path}.effects: needs at least one effect" if effects.empty?
          @delayed_ability = Abilities::TriggeredAbility.new(targets: targets, effects: effects, trigger: WhenYouDo.new)
        end

        def nested_effects = delayed_ability.effects
        def to_s = "reflexive: #{delayed_ability}"

        def apply(engine, ctx)
          source = { "id" => ctx.source, "card" => engine.object(ctx.object).card, "controller" => ctx.controller,
                     "ability" => ref }
          engine.queue_pending_trigger!(source, nil, { "results" => Snapshot.deep_copy(ctx.results || []) })
        end
      end
    end
  end
end
