# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Paying a cost while a spell or ability resolves (CR 118.12): any costs (mana, life, discarding,
      # sacrificing, poison counters, a choice between costs). The payer is asked whether to pay — one choice per
      # way the costs could be paid now (CR 118.3), so a `one_of` is chosen with it — then makes the cost's choices
      # (which card to discard) one `effect_choice` at a time, then pays the mana in a "pay" frame (mana abilities
      # allowed, CR 605.3a); declining or cancelling that payment counts as not paying, and nothing is paid. The
      # rest is paid once the mana is.
      module PaysCosts
        # The costs given as `cost` (a list), or as the shorthands `mana`, `life` and `waterbend`.
        def parse_payment(params, errors, path)
          keys = %w[mana life waterbend cost] & self.class.keys
          given = keys.reject { Mechanics.fetch_param(params, it).nil? }
          errors << "#{path}: needs exactly one of #{keys.join(", ")}" unless given.size == 1
          raw = given.first && Mechanics.fetch_param(params, given.first)
          case given.first
          when "cost"
            Abilities::StackAbility.parse_costs(params, errors, path).tap do
              errors << "#{path}.cost: must be a non-empty list" if it.empty?
            end
          when "life"
            return [Costs::PayLife.new(raw)].freeze if raw.is_a?(Integer) && raw >= 1

            (errors << "#{path}.life: must be an integer >= 1") && [].freeze
          when nil then [].freeze
          else [Mechanics.build_entry(:cost, { given.first => raw }, errors, path)].compact.freeze
          end
        end

        # Each way of paying `costs` open to the payer now: its other parts payable for `payer_obj` (an object
        # the payer controls, CR 118.3) and its mana affordable.
        def open_variants(engine, payer_obj, costs)
          engine.cost_variants(costs).each_index.select do |i|
            variant = engine.cost_variants(costs)[i]
            variant.reject(&:mana?).all? { it.payable?(engine, payer_obj) } &&
              engine.affordable?(payer_obj.controller, engine.costs_mana(variant), nil, engine.waterbend_purpose(variant))
          end
        end

        # `{type: "pay"}` (with `option` and `cost` when the costs can be paid more than one way) for each open way.
        def pay_choices(engine, payer_obj, costs)
          ways = engine.cost_variants(costs)
          open_variants(engine, payer_obj, costs).map do |i|
            ways.size == 1 ? { "type" => "pay" } : { "type" => "pay", "option" => i, "cost" => ways[i].join(", ") }
          end
        end

        # "{2}", "3 life", "discard a card or {2}".
        def costs_text(costs) = costs.map { it.to_s.gsub(/(\A| or )[Pp]ay /, "\\1").sub(/\A\w/, &:downcase) }.join(", ")

        # After a "pay" answer: makes the choices, pays the mana, then the rest. :wait while asking or paying
        # mana; otherwise "paid" or "unpaid".
        def pay_costs(engine, ctx, locals, payer_obj, costs)
          paying = locals["paying"] ||= { "variant" => answers(locals).last["option"].to_i, "entries" => {},
                                          "seen" => answers(locals).size }
          variant = engine.cost_variants(costs)[paying["variant"]]
          if answers(locals).size > paying["seen"]
            paying["seen"] = answers(locals).size
            answer = answers(locals).last
            return "unpaid" if paying.delete("mana") && answer["type"] != "paid"

            take_choice(engine, paying, variant, answer) if paying["cost"]
          end
          choose_next(engine, locals, paying, variant, payer_obj) || pay_variant(engine, ctx, paying, variant, payer_obj)
        end

        private

        def take_choice(engine, paying, variant, answer)
          i = paying.delete("cost")
          (paying["entries"][i.to_s] ||= []) << variant[i].choose!(engine, { object: answer["object"] })
        end

        # Asks for the next choice a cost needs (CR 601.2h, as for casting); nil when none is left.
        def choose_next(engine, locals, paying, variant, payer_obj)
          variant.each_with_index do |cost, i|
            next unless cost.respond_to?(:choices_needed)

            chosen = paying["entries"].fetch(i.to_s, [])
            options = cost.choice_options(engine, payer_obj, chosen)
            next if chosen.size >= cost.choices_needed || options.empty?

            paying["cost"] = i
            return ask(engine, locals, payer_obj.controller, cost.to_s, options.map { { "type" => "cost", "object" => it[:object] } })
          end
          nil
        end

        def pay_variant(engine, ctx, paying, variant, payer_obj)
          mana = engine.costs_mana(variant)
          if mana.mana_value.positive? && !paying["mana_paid"]
            paying["mana"] = paying["mana_paid"] = true
            bend = engine.waterbend_generic(variant)
            engine.begin_payment!(payer_obj.controller, mana, ctx.object, waterbend: bend.positive? ? bend : nil)
            return :wait
          end
          variant.each_with_index do |cost, i|
            next if cost.mana?

            if cost.respond_to?(:choices_needed)
              cost.pay_chosen!(engine, payer_obj,
                               paying["entries"].fetch(i.to_s, []))
            else
              cost.pay!(engine, payer_obj)
            end
          end
          "paid"
        end
      end

      # "[Player] may pay {1}. If they do, [then]. If they don't, [otherwise]." (CR 118.12): the payer answers
      # pay or decline (pay only when the cost can be paid, CR 118.3), then pays (PaysCosts).
      class Pay < ChoiceEffect
        include NestedList
        include PaysCosts

        LISTS = %w[then otherwise].freeze

        primitive :effect, :pay,
                  description: "You may pay `cost` (a list of costs: mana, life, discarding, sacrificing, a `one_of` " \
                               "choice, ...) as it resolves; `mana`, `life` and `waterbend` are shorthands for one cost. " \
                               "If you do, `then` happens; if you don't, `otherwise`. Paying mana works like paying a " \
                               "spell's cost (mana abilities may be activated; a `waterbend` cost may also be paid by " \
                               "tapping artifacts and creatures, CR 701.67a); a cost that can't be paid can't be " \
                               "chosen (CR 118.3). For another player paying, see `counter_unless_pays`.",
                  rules: %w[118.12 118.12a 118.3 119.4 605.3a 701.67a 701.67c],
                  params: { "cost" => "list of costs, e.g. [{\"one_of\": [{\"sacrifice_permanent\": {\"filter\": " \
                                      "\"artifact\"}}, {\"discard\": {}}]}]",
                            "mana" => "mana cost string, e.g. \"{1}\"", "life" => "integer",
                            "waterbend" => "mana cost string: \"unless you waterbend {2}\"",
                            "then" => "list of effects",
                            "otherwise" => "list of effects" },
                  example: { "pay" => { "mana" => "{1}", "then" => [{ "draw" => { "amount" => 1 } }] } }

        attr_reader :costs

        def self.keys = %w[cost mana life waterbend then otherwise if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @costs = parse_payment(params, errors, path)
          @lists = parse_lists(params, errors, path, LISTS)
        end

        def nested_effects = @lists.values.flatten
        def what = costs_text(costs)

        def to_s
          text = "you may pay #{what}"
          text += " — if paid: #{@lists["then"].join("; ")}" unless @lists["then"].empty?
          text += " — if not: #{@lists["otherwise"].join("; ")}" unless @lists["otherwise"].empty?
          text
        end

        def run(engine, ctx, locals)
          unless locals["outcome"]
            return :done unless condition.nil? || condition.true?(engine, ctx)

            status = decide(engine, ctx, locals)
            return status if status == :wait

            locals["next"] = 0
          end
          run_list(engine, ctx, locals, @lists[locals["outcome"] == "paid" ? "then" : "otherwise"])
        end

        private

        # Asks pay or decline, then pays; returns :wait while a decision or the payment is pending.
        def decide(engine, ctx, locals)
          payer = engine.object(ctx.object)
          unless locals["paying"] || answers(locals).first
            choices = pay_choices(engine, payer, costs) + [{ "type" => "decline" }]
            return ask(engine, locals, payer.controller, "Pay #{what}?", choices)
          end
          return locals["outcome"] = "unpaid" if answers(locals).first["type"] == "decline"

          result = pay_costs(engine, ctx, locals, payer, costs)
          result == :wait ? :wait : (locals["outcome"] = result)
        end
      end

      # "Counter target spell unless its controller pays {3}." (CR 701.6a, 118.12a): the spell's (or
      # ability's) controller may pay (PaysCosts); if they don't, it's countered.
      class CounterUnlessPays < ChoiceEffect
        include PaysCosts

        primitive :effect, :counter_unless_pays,
                  description: "Counter each referenced spell or ability unless its controller pays `mana` (or " \
                               "`waterbend`s that cost, CR 701.67a, or pays the list of costs `cost`) as this " \
                               "resolves (they choose, and pay like any cost; mana abilities allowed).",
                  rules: %w[701.6a 118.12a 605.3a 701.67a],
                  params: { "mana" => "mana cost string", "waterbend" => "mana cost string, instead of mana",
                            "cost" => "list of costs, instead of mana", "to" => "selector (usually {\"target\": 0})" },
                  example: { "counter_unless_pays" => { "mana" => "{3}", "to" => { "target" => 0 } } }

        def self.keys = %w[mana waterbend cost to if]

        attr_reader :costs

        def setup(params, errors, path) = @costs = parse_payment(params, errors, path)

        def what = costs_text(costs)
        def to_s = "counter #{to} unless its controller pays #{what}"

        def run(engine, ctx, locals)
          return :done unless locals["target"] || condition.nil? || condition.true?(engine, ctx)

          target = (locals["target"] ||= on_stack(engine, ctx).first) or return :done

          payer = engine.object(target)
          unless locals["paying"] || answers(locals).first
            choices = pay_choices(engine, payer, costs) + [{ "type" => "decline" }]
            return ask(engine, locals, payer.controller, "Pay #{what} or #{payer.card} is countered?", choices)
          end
          paid = answers(locals).first["type"] == "pay" && pay_costs(engine, ctx, locals, payer, costs)
          return :wait if paid == :wait

          engine.counter!(target) unless paid == "paid"
          :done
        end

        def on_stack(engine, ctx) = refs(engine, ctx).select { engine.state.stack.include?(it) }
      end
    end
  end
end
