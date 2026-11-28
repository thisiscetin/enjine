# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # "Exile a creature you control" / "Exile another artifact you control" as a cost (CR 406.1, 601.2h, 602.2b).
      # The permanent is chosen while casting or activating and exiled as the spell or ability becomes cast. It's not
      # a sacrifice (nothing watching sacrifices sees it). What it was is kept like a sacrificed permanent's (types,
      # subtypes, power, toughness, mana value: amount `sacrificed`), and the card in exile is remembered by the
      # spell or ability (selector "exiled_for_cost").
      class ExilePermanent < Choosing
        primitive :cost, :exile_permanent,
                  description: "Exile `count` permanents you control matching `filter` (`other: true`: not the source). " \
                               "Chosen while casting or activating, exiled as it becomes cast; the exiled cards are " \
                               "`exiled_for_cost`, and their last known power, toughness and mana value are amount " \
                               "`sacrificed`.",
                  rules: %w[406.1 601.2h 602.2b 118.3 608.2h],
                  params: { "filter" => "filter (default permanent)", "count" => "integer (default 1)",
                            "other" => "true: not the source itself" },
                  example: { "exile_permanent" => { "filter" => "creature" } }

        def pay_chosen!(engine, _object, entries)
          entries.each do |entry|
            perm = engine.state.objects[entry["object"]]
            next unless perm&.zone == :battlefield

            facts = engine.chars(perm)
            entry.merge!("types" => facts.types.map(&:to_s), "subtypes" => facts.subtypes.map(&:to_s),
                         "power" => engine.power(perm), "toughness" => engine.toughness(perm),
                         "mana_value" => Amount.mana_value(engine, perm))
            fresh = engine.move!(perm.id, :exile, reason: "cost") or next
            holder = engine.casting && engine.state.objects[engine.casting["object"]]
            (holder.memory[CardsCost::EXILED] ||= []) << fresh.id if holder && fresh.zone == :exile
          end
        end

        def to_s = "Exile #{amount_words} #{what} you control"
      end
    end
  end
end
