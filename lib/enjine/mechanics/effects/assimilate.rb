# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Assimilate (CR 701.72, defined in the 2026-11-06 rules). A permanent: gain control of it and put a
      # +1/+1 counter on it (701.72a). A permanent card in another zone: put it onto the battlefield under
      # your control with a +1/+1 counter (701.72b). Either way it's a Borg artifact creature from then on:
      # it keeps its other card types and subtypes except its creature types (CR 205.1b).
      class Assimilate < Effect
        primitive :effect, :assimilate,
                  description: "Assimilate each referenced permanent or permanent card: you gain control of it (or " \
                               "put it onto the battlefield under your control) with a +1/+1 counter, and it " \
                               "becomes a Borg artifact creature while it stays on the battlefield.",
                  rules: %w[701.72a 701.72b 205.1b 613.1b 613.1d],
                  params: { "to" => "selector (permanents, or a target card in a graveyard)" },
                  example: { "assimilate" => { "to" => { "target" => 0 } } }

        def self.keys = %w[to if]

        def apply(engine, ctx)
          refs(engine, ctx).each { engine.assimilate!(it, ctx.controller, ctx) }
        end

        def to_s = "assimilate → #{to}"
      end
    end
  end
end
