# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Endure N (CR 701.63a): the permanent's controller creates an N/N white Spirit creature token unless
      # they put N +1/+1 counters on that permanent. The choice is an `effect_choice` ("counters" is offered
      # only while the permanent is on the battlefield). Endure 0 does nothing (CR 701.63b). N is any amount
      # ("endures X", "where X is the number of counters on this creature"), fixed as the effect starts; the
      # token's power and toughness are copiable values the effect gives it (CR 707.2, 111.4).
      class Endure < ChoiceEffect
        primitive :effect, :endure,
                  description: "Each referenced permanent (default: this one) endures `amount`: its controller puts " \
                               "that many +1/+1 counters on it, or creates an N/N white Spirit creature token.",
                  rules: %w[701.63a 701.63b 707.2 111.4],
                  params: { "amount" => "amount (2, \"x\", {\"counters\": ...})",
                            "to" => "selector of permanents (default self)" },
                  example: { "endure" => { "amount" => 2 } }

        SPIRIT = { "name" => "Spirit", "types" => ["creature"], "subtypes" => ["spirit"], "colors" => ["W"],
                   "power" => 0, "toughness" => 0 }.freeze

        def self.keys = %w[amount to if]
        def self.default_to = "self"
        def self.spirit = @spirit ||= CardDefinition.token(SPIRIT)

        def created_tokens = [Endure.spirit]

        def run(engine, ctx, locals)
          unless locals.key?("queue")
            return :done unless condition.nil? || condition.true?(engine, ctx)

            locals["n"] = [amount_for(engine, ctx), 0].max
            locals["queue"] = locals["n"].zero? ? [] : refs(engine, ctx).select { engine.state.objects.key?(it) }
          end
          n = locals["n"]
          while (id = locals["queue"].first)
            perm = engine.object(id)
            index = perm.zone == :battlefield ? perm.controller : ctx.controller
            answer = answers(locals).first
            if answer.nil? && perm.zone == :battlefield
              return ask(engine, locals, index, "Endure #{n}: put #{n} +1/+1 counters on it, or create a #{n}/#{n} Spirit?",
                         [{ "type" => "counters", "object" => id }, { "type" => "spirit" }])
            end
            answer&.[]("type") == "counters" ? engine.add_counters!(perm, "+1/+1", n, by_player: index) : spirit!(engine, index, n)
            locals["queue"].shift
            locals.delete("answers")
          end
          :done
        end

        def to_s = "endure #{amount} → #{to}"

        private

        # An N/N Spirit: N is part of the token's copiable values (Engine::Copies, "copy_except").
        def spirit!(engine, index, n)
          engine.create_token!(Endure.spirit, index, memory: { "copy_except" => { "power" => n, "toughness" => n } })
        end
      end
    end
  end
end
