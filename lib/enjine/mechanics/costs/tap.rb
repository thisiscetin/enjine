# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # "Tap N untapped [permanents] you control" (CR 601.2h, 602.2b): Collation Trimatrix taps three
      # artifact creatures. Summoning sickness doesn't matter (CR 302.6 is about {T} abilities only).
      class TapPermanents < Choosing
        primitive :cost, :tap_permanents,
                  description: "Tap `count` untapped permanents you control matching `filter` (default: creature), " \
                               "chosen while casting or activating; `other: true` excludes the source. They are " \
                               "tapped as they are chosen; cancelling untaps them.",
                  rules: %w[601.2h 602.2b 302.6 118.3],
                  params: { "count" => "integer (default 1)", "filter" => "filter (default creature)",
                            "other" => "true: not the source itself" },
                  example: { "tap_permanents" => { "count" => 3, "filter" => { "creature" => { "types" => ["artifact"] } } } }

        def self.default_filter = "creature"

        def candidates(engine, object) = matching(engine, object).reject { engine.object(it).tapped }

        def choose!(engine, option)
          perm = engine.object(option[:object])
          engine.tap!(perm)
          { "object" => perm.id, "power" => engine.power(perm), "tapped" => true }
        end

        def to_s = "Tap #{count == 1 ? "an" : count} untapped #{what}#{"s" if count > 1} you control"
      end

      # {T}: tap this permanent (CR 107.5, 602.5a).
      class Tap < Primitive
        primitive :cost, :tap,
                  description: "{T} — tap the permanent the ability belongs to. Requires it to be untapped.",
                  rules: %w[107.5 602.5a],
                  example: "tap"

        INSTANCE = new.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          INSTANCE
        end

        def payable?(engine, object) = !object.tapped && !engine.summoning_sick_for_tap?(object)

        def pay!(engine, object)
          engine.tap!(object)
        end

        def mana? = false
        def to_s = "{T}"
      end
    end
  end
end
