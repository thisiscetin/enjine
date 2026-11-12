# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # "Sacrifice this permanent" as a cost (CR 701.21, 602.2b).
      class SacrificeSelf < Primitive
        primitive :cost, :sacrifice,
                  description: "Sacrifice the permanent the ability belongs to (it goes to its owner's graveyard).",
                  rules: %w[701.21a 602.2b 118.3],
                  example: "sacrifice"

        INSTANCE = new.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          INSTANCE
        end

        def mana? = false
        def uses_source? = true
        # CR 701.21a, 614.17b: only a permanent on the battlefield its controller may sacrifice.
        def payable?(engine, object) = engine.can_sacrifice?(object, object.controller)
        def pay!(engine, object) = engine.move!(object.id, :graveyard, reason: "sacrifice")
        def to_s = "Sacrifice this"
      end

      # "Exile this permanent" as a cost (CR 406.1, 602.2b): it leaves the battlefield for exile. Unlike a
      # sacrifice, nothing that watches sacrifices sees it.
      class ExileSelf < Primitive
        primitive :cost, :exile_self,
                  description: "Exile the permanent the ability belongs to (\"Exile this enchantment: ...\").",
                  rules: %w[406.1 602.2b 118.3],
                  example: "exile_self"

        INSTANCE = new.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          INSTANCE
        end

        def mana? = false
        def uses_source? = true
        def payable?(engine, object) = engine.state.battlefield.include?(object.id)
        def pay!(engine, object) = engine.move!(object.id, :exile, reason: "cost")
        def to_s = "Exile this"
      end

      # The costs that take the permanent itself off the battlefield (CR 113.6m: not from another zone).
      LEAVING_SELF = [SacrificeSelf, ExileSelf].freeze

      # "Sacrifice a creature" / "Sacrifice another creature or artifact" as a cost (CR 701.21a, 601.2h).
      # The permanent is chosen while casting and sacrificed as the spell or ability becomes cast; what
      # it was (types, subtypes, power) is kept for "if you sacrificed a Klingon this way" (CR 608.2h).
      class SacrificePermanent < Choosing
        primitive :cost, :sacrifice_permanent,
                  description: "Sacrifice `count` permanents you control matching `filter` (`other: true`: not the " \
                               "source). Chosen while casting or activating, sacrificed as it becomes cast; the " \
                               "sacrificed permanent's last known types and subtypes are remembered (condition " \
                               "`sacrificed`), and its power, toughness and mana value (amount `sacrificed`).",
                  rules: %w[701.21a 601.2h 602.2b 118.3 608.2h],
                  params: { "filter" => "filter (default permanent)", "count" => "integer (default 1)",
                            "other" => "true: not the source itself" },
                  example: { "sacrifice_permanent" => { "filter" => "creature", "other" => true } }

        def pay_chosen!(engine, _object, entries)
          entries.each do |entry| # still there: chosen permanents can't be sacrificed for mana (Engine::Payment)
            perm = engine.object(entry["object"])
            facts = engine.chars(perm)
            entry.merge!("types" => facts.types.map(&:to_s), "subtypes" => facts.subtypes.map(&:to_s),
                         "power" => engine.power(perm), "toughness" => engine.toughness(perm),
                         "mana_value" => Amount.mana_value(engine, perm))
            engine.move!(perm.id, :graveyard, reason: "sacrifice")
          end
        end

        # CR 701.21a, 614.17b: only permanents their controller may sacrifice (Engine::Rules).
        def candidates(engine, object) = matching(engine, object).select { engine.can_sacrifice?(engine.object(it), object.controller) }

        def to_s = "Sacrifice #{amount_words} #{what}"
      end
    end
  end
end
