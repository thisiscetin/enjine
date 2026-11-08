# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # Costs that need choices while casting or activating (CR 601.2h, 602.2b): which permanents to tap
      # or sacrifice, which counters to remove. Each choice is a `choose_cost` decision recorded in the
      # cast frame's "paid" list ({"cost": index, "object": id, ...}); the spell or ability keeps that list
      # (GameObject#paid) so effects can ask about "the sacrificed creature". Tapping happens at once
      # (cancelling untaps); sacrificing and removing counters happen as the spell or ability becomes cast.
      class Choosing < Primitive
        attr_reader :count, :filter

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, keys, errors, path)
          raw = Mechanics.fetch_param(params, :filter) || default_filter
          filter = Mechanics.build_entry(:filter, raw, errors, "#{path}.filter")
          count = Mechanics.integer_param(params, :count, errors, path, default: 1, min: 1)
          other = Mechanics.fetch_param(params, :other)
          errors << "#{path}.other: must be true or false" unless [nil, true, false].include?(other)
          new(filter, count, other == true, params, errors, path)
        end

        def self.keys = %w[filter count other]
        def self.default_filter = "permanent"

        def initialize(filter, count, other, _params, _errors, _path)
          super()
          @filter = filter
          @count = count
          @other = other
          freeze
        end

        def mana? = false
        def choices_needed = count

        # Permanents the controller of `object` controls that match (not `object` itself for "another").
        def matching(engine, object)
          engine.state.battlefield.select do |id|
            perm = engine.object(id)
            perm.controller == object.controller && !(@other && id == object.id) &&
              @filter.match_for?(engine, id, object.controller, object.id)
          end
        end

        # The options still open, given the choices already made for this cost (`chosen`: paid entries).
        def choice_options(engine, object, chosen)
          taken = chosen.map { it["object"] }
          candidates(engine, object).reject { taken.include?(it) }.map { { object: it } }
        end

        def candidates(engine, object) = matching(engine, object)
        def payable?(engine, object) = candidates(engine, object).size >= count

        # Called when a choice is made: the paid entry to record (and any immediate payment).
        def choose!(_engine, option) = { "object" => option[:object] }

        # Called as the spell or ability becomes cast, with this cost's paid entries.
        def pay_chosen!(_engine, _object, _entries) = nil

        # Costs without choices of their own are paid by ActivatedAbility's finishing step.
        def pay!(_engine, _object) = nil

        def what = @filter.is_a?(Class) ? @filter.primitive_name.tr("_", " ") : @filter.to_s

        def amount_words
          if count == 1
            @other ? "another" : "a"
          else
            count.to_s
          end
        end
      end

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

      # "Sacrifice a creature" / "Sacrifice another creature or artifact" as a cost (CR 701.21a, 601.2h).
      # The permanent is chosen while casting and sacrificed as the spell or ability becomes cast; what
      # it was (types, subtypes, power) is kept for "if you sacrificed a Klingon this way" (CR 608.2h).
      class SacrificePermanent < Choosing
        primitive :cost, :sacrifice_permanent,
                  description: "Sacrifice `count` permanents you control matching `filter` (`other: true`: not the " \
                               "source). Chosen while casting or activating, sacrificed as it becomes cast; the " \
                               "sacrificed permanent's last known types and subtypes are remembered (condition " \
                               "`sacrificed`).",
                  rules: %w[701.21a 601.2h 602.2b 118.3 608.2h],
                  params: { "filter" => "filter (default permanent)", "count" => "integer (default 1)",
                            "other" => "true: not the source itself" },
                  example: { "sacrifice_permanent" => { "filter" => "creature", "other" => true } }

        def pay_chosen!(engine, _object, entries)
          entries.each do |entry| # still there: chosen permanents can't be sacrificed for mana (Engine::Payment)
            perm = engine.object(entry["object"])
            facts = engine.chars(perm)
            entry.merge!("types" => facts.types.map(&:to_s), "subtypes" => facts.subtypes.map(&:to_s),
                         "power" => engine.power(perm))
            engine.move!(perm.id, :graveyard, reason: "sacrifice")
          end
        end

        def to_s = "Sacrifice #{amount_words} #{what}"
      end

      # "Remove N counters from among [permanents] you control" (CR 122.8 / 118.3): each choice is one
      # counter on one permanent; they are removed as the ability becomes cast.
      class RemoveCounters < Choosing
        primitive :cost, :remove_counters,
                  description: "Remove `count` counters (of kind `counter`, or any kind) from among permanents you " \
                               "control matching `filter` (default creature), one counter per choice. Removed as " \
                               "it becomes cast.",
                  rules: %w[602.2b 601.2h 118.3 122.1],
                  params: { "count" => "integer", "filter" => "filter (default creature)", "counter" => "counter name (optional)" },
                  example: { "remove_counters" => { "count" => 3 } }

        def self.keys = %w[filter count counter]
        def self.default_filter = "creature"

        def initialize(filter, count, other, params, errors, path)
          @counter = Mechanics.fetch_param(params, :counter)
          errors << "#{path}.counter: #{Counters.error(@counter)}" if @counter && Counters.error(@counter)
          super
        end

        # Counters still available: [object, kind] once per counter, minus those already chosen.
        def units(engine, object, chosen)
          taken = chosen.map { [it["object"], it["counter"]] }
          matching(engine, object).flat_map do |id|
            engine.object(id).counters.flat_map do |kind, n|
              next [] unless @counter.nil? || kind == @counter

              left = n - taken.count([id, kind])
              left.positive? ? [[id, kind]] * left : []
            end
          end
        end

        def payable?(engine, object) = units(engine, object, []).size >= count
        def choice_options(engine, object, chosen) = units(engine, object, chosen).uniq.map { { object: it[0], counter: it[1] } }
        def choose!(_engine, option) = { "object" => option[:object], "counter" => option[:counter] }

        def pay_chosen!(engine, _object, entries)
          entries.each { engine.remove_counters!(engine.object(it["object"]), it["counter"], 1) }
        end

        def to_s = "Remove #{count} #{"#{@counter} " if @counter}counters from among #{what}s you control"
      end

      # "Exile this card from your graveyard" / "Put this card from your graveyard on the bottom of your
      # library" as a cost: the ability functions only from the graveyard (CR 113.6m).
      class FromGraveyard < Primitive
        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          new
        end

        def mana? = false
        def zone = :graveyard
        def uses_source? = true
        def payable?(engine, object) = engine.player(object.owner).graveyard.include?(object.id)
      end

      # Exile this card from your graveyard (CR 406, 113.6m).
      class ExileSelfFromGraveyard < FromGraveyard
        primitive :cost, :exile_self_from_graveyard,
                  description: "Exile this card from your graveyard. An ability with this cost is activated from " \
                               "your graveyard.",
                  rules: %w[406.1 113.6m 602.2b 118.3],
                  example: "exile_self_from_graveyard"

        def pay!(engine, object) = engine.move!(object.id, :exile, reason: "cost")
        def to_s = "Exile this card from your graveyard"
      end

      # Put this card from your graveyard on the bottom of your library (CR 401, 113.6m).
      class BottomSelfFromGraveyard < FromGraveyard
        primitive :cost, :bottom_self_from_graveyard,
                  description: "Put this card from your graveyard on the bottom of your library. An ability with " \
                               "this cost is activated from your graveyard.",
                  rules: %w[401.1 113.6m 602.2b 118.3],
                  example: "bottom_self_from_graveyard"

        def pay!(engine, object) = engine.move!(object.id, :library, position: :bottom, reason: "cost")
        def to_s = "Put this card from your graveyard on the bottom of your library"
      end
    end
  end
end
