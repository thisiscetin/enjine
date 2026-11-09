# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "Behold a Dragon" as a resolving instruction (CR 701.4a), usually optional: "you may behold a Dragon.
      # If you do, create a Treasure token" is {"may": {"effects": [{"behold": ...}], "then": [...]}}. You
      # reveal a matching card from your hand or choose a matching permanent you control.
      class Behold < ChoiceEffect
        primitive :effect, :behold,
                  description: "You behold an object matching the card spec `card`: reveal such a card from your " \
                               "hand or choose such a permanent you control. Under `may`, \"yes\" is offered only " \
                               "when there is one.",
                  rules: %w[701.4a 701.4b 118.3],
                  params: { "card" => "card spec (required), e.g. {\"subtypes\": [\"dragon\"]}" },
                  example: { "may" => { "effects" => [{ "behold" => { "card" => { "subtypes" => ["dragon"] } } }],
                                        "then" => [{ "create_token" => { "token" => "Treasure" } }] } }

        def self.keys = %w[card if]
        def self.default_to = "you"

        def setup(params, errors, path)
          raw = Mechanics.fetch_param(params, :card)
          errors << "#{path}.card: required" if raw.nil?
          @card = CardSpec.build(raw, errors, "#{path}.card")
        end

        def possible?(engine, ctx) = !Beholding.candidates(engine, ctx.controller, @card).empty?

        def run(engine, ctx, locals)
          return :done unless condition.nil? || condition.true?(engine, ctx)

          options = Beholding.candidates(engine, ctx.controller, @card)
          chosen = answers(locals).first
          return :done if options.empty? && chosen.nil?

          choices = options.map { { "type" => "behold", "object" => it } }
          return ask(engine, locals, ctx.controller, "Behold a #{@card}", choices) unless chosen

          Beholding.behold!(engine, ctx.controller, chosen["object"]) if engine.state.objects.key?(chosen["object"])
          :done
        end

        def to_s = "behold a #{@card.to_s.delete_suffix(" card")}"
      end
    end
  end
end
