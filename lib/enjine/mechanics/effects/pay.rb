# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Paying a cost while a spell or ability resolves (CR 118.12): "[Player] may pay {1}. If they do,
      # [then]. If they don't, [otherwise]." The payer answers yes or no (yes only when the cost can be
      # paid, CR 118.3), then pays mana one decision at a time in a "pay" frame (mana abilities allowed,
      # CR 605.3a); declining or cancelling that payment counts as not paying.
      class Pay < ChoiceEffect
        include NestedList

        LISTS = %w[then otherwise].freeze

        primitive :effect, :pay,
                  description: "You may pay `mana` or `life` as it resolves. If you do, `then` happens; if you " \
                               "don't, `otherwise`. Paying mana works like paying a spell's cost (mana abilities may " \
                               "be activated); life can be paid only if you have that much (CR 119.4). For another " \
                               "player paying, see `counter_unless_pays`.",
                  rules: %w[118.12 118.12a 118.3 119.4 605.3a],
                  params: { "mana" => "mana cost string, e.g. \"{1}\"", "life" => "integer",
                            "then" => "list of effects",
                            "otherwise" => "list of effects" },
                  example: { "pay" => { "mana" => "{1}", "then" => [{ "draw" => { "amount" => 1 } }] } }

        attr_reader :cost, :life

        def self.keys = %w[mana life then otherwise if]
        def self.default_to = "you"

        def setup(params, errors, path)
          raw = Mechanics.fetch_param(params, :mana)
          @life = Mechanics.fetch_param(params, :life)
          errors << "#{path}: needs exactly one of mana, life" unless raw.nil? ^ @life.nil?
          errors << "#{path}.life: must be an integer >= 1" unless @life.nil? || (@life.is_a?(Integer) && @life >= 1)
          @cost = raw && Mana.parse_cost(raw, errors, "#{path}.mana")
          @lists = parse_lists(params, errors, path, LISTS)
        end

        def nested_effects = @lists.values.flatten
        def what = cost ? cost.to_s : "#{life} life"

        def to_s
          text = "you may pay #{what}"
          text += " — if paid: #{@lists["then"].join("; ")}" unless @lists["then"].empty?
          text += " — if not: #{@lists["otherwise"].join("; ")}" unless @lists["otherwise"].empty?
          text
        end

        def can_pay?(engine, index)
          cost ? engine.affordable?(index, cost, nil) : engine.player(index).life >= life
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

        # Asks yes/no, then pays; returns :wait while a decision or the payment is pending.
        def decide(engine, ctx, locals)
          index = ctx.controller
          answer, payment = answers(locals)
          unless answer
            choices = can_pay?(engine, index) ? [{ "type" => "pay" }, { "type" => "decline" }] : [{ "type" => "decline" }]
            return ask(engine, locals, index, "Pay #{what}?", choices)
          end
          return locals["outcome"] = "unpaid" if answer["type"] == "decline"
          return pay_life(engine, index, locals) if life
          return locals["outcome"] = (payment["type"] == "paid" ? "paid" : "unpaid") if payment

          engine.begin_payment!(index, cost, ctx.object)
          :wait
        end

        def pay_life(engine, index, locals)
          engine.change_life!(index, -life)
          locals["outcome"] = "paid"
        end
      end

      # "Counter target spell unless its controller pays {3}." (CR 701.6a, 118.12a): the spell's (or
      # ability's) controller may pay; if they don't, it's countered.
      class CounterUnlessPays < ChoiceEffect
        primitive :effect, :counter_unless_pays,
                  description: "Counter each referenced spell or ability unless its controller pays `mana` as this " \
                               "resolves (they choose, and pay like any cost; mana abilities allowed).",
                  rules: %w[701.6a 118.12a 605.3a],
                  params: { "mana" => "mana cost string", "to" => "selector (usually {\"target\": 0})" },
                  example: { "counter_unless_pays" => { "mana" => "{3}", "to" => { "target" => 0 } } }

        def self.keys = %w[mana to]

        attr_reader :cost

        def setup(params, errors, path)
          raw = Mechanics.fetch_param(params, :mana)
          @cost = raw.nil? ? ((errors << "#{path}.mana: required") && nil) : Mana.parse_cost(raw, errors, "#{path}.mana")
        end

        def to_s = "counter #{to} unless its controller pays #{cost}"

        def run(engine, ctx, locals)
          target = (locals["target"] ||= on_stack(engine, ctx).first) or return :done

          payer = engine.object(target).controller
          answer, payment = answers(locals)
          unless answer
            choices = engine.affordable?(payer, cost, nil) ? [{ "type" => "pay" }, { "type" => "decline" }] : [{ "type" => "decline" }]
            return ask(engine, locals, payer, "Pay #{cost} or #{engine.object(target).card} is countered?", choices)
          end
          if answer["type"] == "pay" && payment.nil?
            engine.begin_payment!(payer, cost, ctx.object)
            return :wait
          end
          engine.counter!(target) unless payment && payment["type"] == "paid"
          :done
        end

        def on_stack(engine, ctx) = refs(engine, ctx).select { engine.state.stack.include?(it) }
      end
    end
  end
end
