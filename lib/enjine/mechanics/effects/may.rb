# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "You may [effects]. If you do, [then]. If you don't, [otherwise]." (CR 118.12): the controller
      # answers yes or no while it resolves (an effect_choice). Yes is offered only when every effect
      # in `effects` can be done fully, as for any cost (CR 118.3). `then` follows a yes and
      # `otherwise` a no, whatever the effects actually did.
      class May < ChoiceEffect
        include NestedList

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
          @lists = parse_lists(params, errors, path, LISTS)
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
      end
    end
  end
end
