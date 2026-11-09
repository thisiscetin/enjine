# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "If you don't control a [kind of permanent], create one as a token. Choose one you control. Put N
      # [counters] on it.": the shared shape of amass (CR 701.47a) and empower Jace (CR 701.71a). The choice
      # is an `effect_choice` only when there is more than one candidate. The chosen permanent is the
      # effect's result ("the amassed Army", CR 701.47c), unless it is the token just created (already one).
      class ChooseOrCreate < ChoiceEffect
        def self.keys = %w[amount if]
        def self.default_to = "you"

        def run(engine, ctx, locals)
          return :done unless locals.key?("n") || condition.nil? || condition.true?(engine, ctx)

          unless locals.key?("n")
            locals["n"] = amount_for(engine, ctx)
            engine.create_token!(token, ctx.controller) if candidates(engine, ctx.controller).empty?
          end
          options = candidates(engine, ctx.controller)
          answer = answers(locals).first
          if answer.nil? && options.size > 1
            return ask(engine, locals, ctx.controller, "#{self}: choose one",
                       options.map { { "type" => "choose", "object" => it } })
          end
          chosen = answer ? answer["object"] : options.first
          finish(engine, ctx, chosen, locals) if chosen
          :done
        end

        def created_tokens = [token]

        private

        def candidates(engine, index)
          engine.state.battlefield.select { engine.object(it).controller == index && candidate?(engine, engine.object(it)) }
        end

        def finish(engine, ctx, chosen, locals)
          perm = engine.object(chosen)
          engine.record_result!(chosen) if answers(locals).any?
          engine.add_counters!(perm, counter, locals["n"], by_player: ctx.controller)
        end
      end

      # Amass [subtype] N (CR 701.47a): if you don't control an Army creature, create a 0/0 black [subtype]
      # Army creature token; choose an Army creature you control; put N +1/+1 counters on it; if it isn't a
      # [subtype], it becomes one in addition to its other types (layer 4, for as long as it stays).
      class Amass < ChooseOrCreate
        primitive :effect, :amass,
                  description: "Amass `subtype` `amount`: if you control no Army creature, create a 0/0 black " \
                               "[subtype] Army creature token; then put `amount` +1/+1 counters on an Army creature " \
                               "you control (chosen if there are several), which becomes a [subtype] too.",
                  rules: %w[701.47a 701.47b 701.47c 613.1d],
                  params: { "subtype" => "lowercase creature type, e.g. \"orc\"", "amount" => "amount" },
                  example: { "amass" => { "subtype" => "orc", "amount" => 2 } }

        attr_reader :subtype, :token

        def self.keys = %w[subtype amount if]

        def setup(params, errors, path)
          @subtype = Mechanics.fetch_param(params, :subtype).to_s
          unless CardDefinition::SUBTYPE_FORMAT.match?(@subtype) && @subtype != "army"
            errors << "#{path}.subtype: must be a lowercase creature type other than army"
            @subtype = "zombie"
          end
          @token = CardDefinition.token({ "name" => "#{@subtype.split("_").map(&:capitalize).join(" ")} Army",
                                          "types" => ["creature"], "subtypes" => [@subtype, "army"], "colors" => ["B"],
                                          "power" => 0, "toughness" => 0 })
        end

        def counter = "+1/+1"
        def to_s = "amass #{subtype.tr("_", " ")} #{amount}"

        private

        def candidate?(engine, perm)
          chars = engine.chars(perm)
          chars.creature? && chars.subtypes.include?(:army)
        end

        def finish(engine, ctx, chosen, locals)
          super
          return if engine.chars(chosen).subtypes.include?(subtype.to_sym)

          engine.add_continuous_effect!("add_subtypes", ctx, [chosen], "subtypes" => [subtype], "duration" => "permanent")
        end
      end

      # Empower Jace N (CR 701.71a): if you don't control a Jace planeswalker token, create a blue Jace
      # planeswalker token with 0 loyalty, "[-1]: Surveil 1" and "[-3]: Draw a card"; choose a Jace
      # planeswalker token you control; put N loyalty counters on it. State-based actions aren't checked
      # while the effect resolves, so the new token gets its counters first (CR 704.3).
      class EmpowerJace < ChooseOrCreate
        primitive :effect, :empower_jace,
                  description: "Empower Jace `amount`: if you control no Jace planeswalker token, create a blue Jace " \
                               "planeswalker token (0 loyalty; -1: surveil 1; -3: draw a card); then put `amount` " \
                               "loyalty counters on a Jace planeswalker token you control.",
                  rules: %w[701.71a 704.3],
                  params: { "amount" => "amount" },
                  example: { "empower_jace" => { "amount" => 2 } }

        TOKEN = { "name" => "Jace", "types" => ["planeswalker"], "subtypes" => ["jace"], "colors" => ["U"], "loyalty" => 0,
                  "abilities" => [{ "loyalty" => { "cost" => -1, "effects" => [{ "surveil" => { "amount" => 1 } }] } },
                                  { "loyalty" => { "cost" => -3, "effects" => [{ "draw" => { "amount" => 1 } }] } }] }.freeze

        def token = EmpowerJace.token
        def self.token = @token ||= CardDefinition.token(TOKEN)
        def counter = "loyalty"
        def to_s = "empower Jace #{amount}"

        private

        def candidate?(engine, perm)
          chars = engine.chars(perm)
          engine.token?(perm) && chars.planeswalker? && chars.subtypes.include?(:jace)
        end
      end
    end
  end
end
