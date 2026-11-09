# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Assimilate (CR 701.72, defined in the 2026-11-06 rules). A permanent: gain control of it and put a
      # +1/+1 counter on it (701.72a). A permanent card in another zone: put it onto the battlefield under
      # your control with a +1/+1 counter (701.72b). Either way it's a Borg artifact creature from then on:
      # it keeps its other card types and subtypes except its creature types (CR 205.1b).
      #
      # `choose: true` assimilates one of the referenced cards, chosen by the controller as it resolves
      # ("assimilate a creature card exiled with it", 701.72c, 607.2a); `for` keeps only cards matching a
      # card spec. What it put onto the battlefield is its result, so a later effect can say "if you can't".
      class Assimilate < ChoiceEffect
        primitive :effect, :assimilate,
                  description: "Assimilate each referenced permanent or permanent card: you gain control of it (or " \
                               "put it onto the battlefield under your control) with a +1/+1 counter, and it " \
                               "becomes a Borg artifact creature while it stays on the battlefield. `for`: only cards " \
                               "matching a card spec; `choose: true`: you choose one of them.",
                  rules: %w[701.72a 701.72b 701.72c 607.2a 205.1b 613.1b 613.1d 614.12a],
                  params: { "to" => "selector (permanents, or a target card in a graveyard, or \"exiled_with\")",
                            "for" => "card spec (default: any)", "choose" => "boolean" },
                  example: { "assimilate" => { "to" => { "target" => 0 } } }

        def self.keys = %w[to for choose if]

        def setup(params, errors, path)
          raw = Mechanics.fetch_param(params, :for)
          @spec = raw && CardSpec.build(raw, errors, "#{path}.for")
          @choose = Linked.flag(params, "choose", errors, path)
        end

        def to_s = "assimilate#{" one" if @choose}#{" #{@spec}" if @spec} → #{to}"

        def run(engine, ctx, locals)
          return :done unless locals.key?("refs") || condition.nil? || condition.true?(engine, ctx)

          refs = (locals["refs"] ||= candidates(engine, ctx))
          unless locals.key?("chosen")
            return ask_which(engine, ctx, locals, refs) if @choose && refs.size > 1 && answers(locals).empty?

            picked = answers(locals).map { it["object"] }
            picked = refs.first(1) if picked.empty?
            locals["chosen"] = @choose ? picked : refs
          end
          chosen = locals["chosen"].select { engine.state.objects.key?(it) }
          entering = chosen.reject { engine.object(it).zone == :battlefield }.map { [it, ctx.controller] }
          return :wait if engine.ask_entering_choices!(locals, entering) == :wait

          chosen.each do |id|
            engine.assimilate!(id, ctx.controller, ctx, enters: engine.with_entering_answer(locals, id, ctx.controller, nil))
          end
          :done
        end

        private

        def candidates(engine, ctx)
          refs(engine, ctx).select do |id|
            obj = engine.state.objects[id]
            obj && !obj.ability? && (@spec.nil? || @spec.match?(engine, obj, ctx))
          end
        end

        def ask_which(engine, ctx, locals, refs)
          ask(engine, locals, ctx.controller, "Choose a card to assimilate",
              refs.map { { "type" => "assimilate", "object" => it } })
        end
      end
    end
  end
end
