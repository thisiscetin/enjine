# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Airbend (CR 701.65a): "exile those objects. For each card exiled this way, for as long as it remains
      # exiled, its owner may cast it by paying {2} rather than paying its mana cost." The permanents and spells
      # are the referenced ones (usually targets); each exiled card gets a permission for its owner whose
      # alternative cost is {2} (CR 118.9, Engine::Permissions). A token or a copy of a spell ceases to exist
      # (CR 111.7, 707.10a), so it can't be cast. Exiling one or more objects this way is airbending (CR 701.65b).
      class Airbend < ZoneEffect
        COST = "{2}"

        primitive :effect, :airbend,
                  description: "Airbend: exile each referenced permanent or spell; for as long as each card stays " \
                               "exiled, its owner may cast it by paying {2} rather than its mana cost (cast option " \
                               "`via: \"effect:<n>\"`). The exiled cards are the effect's results.",
                  rules: %w[701.65a 701.65b 118.9 601.2f],
                  params: { "to" => "selector of permanents and/or spells" },
                  example: { "airbend" => { "to" => { "target" => 0 } } }

        def self.zone = :exile
        def self.reason = "airbend"
        def self.from_zones = %i[battlefield stack]

        def to_s = "airbend → #{to}"

        def apply(engine, ctx)
          moved = movable(engine, ctx).filter_map { move(engine, ctx, it) }
          return if moved.empty?

          moved.select { it.zone == :exile }.group_by(&:owner).each do |owner, cards|
            engine.grant_play_permission!(owner, cards.map(&:id), duration: "while_exiled", play: "cast",
                                                                  alt: { "cost" => COST })
          end
          engine.emit Events::KeywordAction.new(player: engine.name(ctx.controller), action: "airbend", amount: moved.size)
        end
      end
    end
  end
end
