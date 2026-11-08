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
                  rules: %w[400.7 400.4a 110.2 111.8 603.7c],
                  params: { "to" => "selector (usually {\"result\": n})", "tapped" => "boolean",
                            "under" => UNDER.join(" | ") },
                  example: { "return_to_battlefield" => { "to" => { "result" => 0 } } }

        attr_reader :tapped, :under

        def self.keys = %w[to tapped under if]

        def setup(params, errors, path)
          @tapped = Mechanics.fetch_param(params, :tapped) == true
          @under = Mechanics.fetch_param(params, :under) || "owner"
          errors << "#{path}.under: must be one of #{UNDER.join(", ")}" unless UNDER.include?(@under)
        end

        def to_s = "return to the battlefield#{" tapped" if tapped}#{" under your control" if under == "you"} → #{to}"

        def apply(engine, ctx)
          cards(engine, ctx).each do |id|
            controller = under == "you" ? ctx.controller : engine.object(id).owner
            engine.move!(id, :battlefield, controller: controller, reason: "return", enters: tapped ? { "tapped" => true } : nil)
          end
        end

        # CR 400.4a: an instant or sorcery card can't enter the battlefield. CR 111.8: a token that
        # has left the battlefield can't come back (it ceases to exist at the next SBA check).
        def cards(engine, ctx)
          refs(engine, ctx).select do |id|
            obj = engine.state.objects[id]
            obj && ZONES.include?(obj.zone) && !engine.catalog.fetch(obj.card).token? &&
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
        def mine(engine, ctx) = objects(engine, ctx).select { engine.object(it).controller == ctx.controller }
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
                  rules: %w[118.12 118.3 608.2d],
                  params: { "effects" => "list of effects (the optional part)", "then" => "list of effects",
                            "otherwise" => "list of effects" },
                  example: { "may" => { "effects" => [{ "discard" => { "amount" => 1 } }],
                                        "then" => [{ "draw" => { "amount" => 1 } }] } }

        def self.keys = LISTS + %w[if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @lists = LISTS.to_h do |key|
            [key, Abilities::StackAbility.parse_effects(params, errors, path, @targets_count, key: key.to_sym,
                                                                                              results_count: @results_count)]
          end.freeze
          errors << "#{path}.effects: needs at least one effect" if @lists["effects"].empty?
        end

        def effects = @lists["effects"]
        def nested_effects = @lists.values.flatten

        def to_s
          text = "you may: #{effects.join("; ")}"
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
          ask(engine, locals, ctx.controller, "You may: #{effects.join("; ")}", choices)
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
                  params: { "when" => "a trigger condition", "effects" => "list of effects" },
                  example: { "delayed_trigger" => { "when" => { "step_begins" => { "step" => "end", "whose" => "each" } },
                                                    "effects" => [{ "sacrifice" => { "to" => { "result" => 0 } } }] } }

        attr_reader :ref, :delayed_ability

        def self.keys = %w[when effects]
        def self.default_to = "you"

        def setup(params, errors, path)
          @ref = "delayed:#{path}"
          raw = Mechanics.fetch_param(params, :when)
          trigger = raw.nil? ? ((errors << "#{path}.when: required") && nil) : Mechanics.build_entry(:trigger, raw, errors, "#{path}.when")
          effects = Abilities::StackAbility.parse_effects(params, errors, path, 0, results_count: @results_count)
          errors << "#{path}.effects: needs at least one effect" if effects.empty?
          @delayed_ability = Abilities::TriggeredAbility.new(targets: [].freeze, effects: effects, trigger: trigger)
        end

        def nested_effects = delayed_ability.effects
        def to_s = "delayed: #{delayed_ability}"

        # CR 603.7d-e: controlled by the resolving object's controller, from the same source. It
        # remembers the results it may name (CR 603.7c).
        def apply(engine, ctx)
          engine.create_delayed_trigger!("controller" => ctx.controller, "source" => ctx.source,
                                         "card" => engine.object(ctx.object).card, "ability" => ref,
                                         "results" => Snapshot.deep_copy(ctx.results || []))
        end
      end
    end
  end
end
