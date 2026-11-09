# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Endure N (CR 701.63a): the permanent's controller creates an N/N white Spirit creature token unless
      # they put N +1/+1 counters on that permanent. The choice is an `effect_choice` ("counters" is offered
      # only while the permanent is on the battlefield). Endure 0 does nothing (CR 701.63b). N is a fixed
      # number: the token's power and toughness are its copiable values (CR 707.2).
      class Endure < ChoiceEffect
        primitive :effect, :endure,
                  description: "Each referenced permanent (default: this one) endures `amount`: its controller puts " \
                               "that many +1/+1 counters on it, or creates an N/N white Spirit creature token.",
                  rules: %w[701.63a 701.63b],
                  params: { "amount" => "integer >= 0", "to" => "selector of permanents (default self)" },
                  example: { "endure" => { "amount" => 2 } }

        def self.keys = %w[amount to if]
        def self.default_to = "self"

        def setup(params, errors, path)
          n = Mechanics.fetch_param(params, :amount)
          errors << "#{path}.amount: must be an integer from 0 to 99 (the Spirit token's size)" unless n.is_a?(Integer) && n.between?(0, 99)
          @n = n.is_a?(Integer) ? n.clamp(0, 99) : 0
          @spirit = CardDefinition.token({ "name" => "Spirit", "types" => ["creature"], "subtypes" => ["spirit"],
                                           "colors" => ["W"], "power" => @n, "toughness" => @n })
        end

        def created_tokens = [@spirit]

        def run(engine, ctx, locals)
          return :done if @n.zero? || !(locals.key?("queue") || condition.nil? || condition.true?(engine, ctx))

          queue = (locals["queue"] ||= refs(engine, ctx).select { engine.state.objects.key?(it) })
          while (id = queue.first)
            perm = engine.object(id)
            index = perm.zone == :battlefield ? perm.controller : ctx.controller
            answer = answers(locals).first
            if answer.nil? && perm.zone == :battlefield
              return ask(engine, locals, index, "Endure #{@n}: put #{@n} +1/+1 counters on it, or create a #{@n}/#{@n} Spirit?",
                         [{ "type" => "counters", "object" => id }, { "type" => "spirit" }])
            end
            answer&.[]("type") == "counters" ? engine.add_counters!(perm, "+1/+1", @n, by_player: index) : engine.create_token!(@spirit, index)
            queue.shift
            locals.delete("answers")
          end
          :done
        end

        def to_s = "endure #{@n} → #{to}"
      end
    end
  end
end
