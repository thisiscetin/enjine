# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Exile (CR 406, 701.13). `link`: the card is "exiled with" the source, for its linked abilities
      # (CR 607.2a). `until_source_leaves`: it returns once the source leaves the battlefield (CR 610.3).
      class Exile < ZoneEffect
        primitive :effect, :exile,
                  description: "Exile each referenced permanent, spell, or card in a graveyard or hand. `link: true`: the cards " \
                               "are exiled with the source, for its \"exiled with\" abilities (the `exiled_with` selector). " \
                               "`until_source_leaves: true`: they return to the battlefield under their owners' control " \
                               "when the source leaves the battlefield; if it already has, nothing is exiled.",
                  rules: %w[406.1 701.13a 607.2a 406.6 610.3 610.3a 610.3b 610.3c],
                  params: { "to" => "selector", "link" => "boolean", "until_source_leaves" => "boolean" },
                  example: { "exile" => { "to" => { "target" => 0 } } }

        attr_reader :link, :until_leaves

        def self.keys = %w[to link until_source_leaves if]
        def self.zone = :exile
        # A spell too ("exile target spell", CR 701.13a).
        def self.from_zones = %i[battlefield graveyard hand stack]

        def setup(params, errors, path)
          @link = Mechanics.flag_param(params, "link", errors, path)
          @until_leaves = Mechanics.flag_param(params, "until_source_leaves", errors, path)
        end

        def to_s = "exile#{" until the source leaves" if until_leaves}#{" (linked)" if link} → #{to}"

        # CR 610.3a-b: if the source has already left the battlefield, the object doesn't move.
        def apply(engine, ctx)
          return if until_leaves && !engine.state.battlefield.include?(ctx.source)

          super
        end

        def move(engine, ctx, id)
          fresh = super or return
          engine.link_exiled!(ctx.source, fresh.id) if link || until_leaves
          return unless until_leaves

          (engine.object(ctx.source).memory[Linked::UNTIL_LEAVES] ||= []) << fresh.id
        end
      end
    end
  end
end
