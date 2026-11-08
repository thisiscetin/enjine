# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # "Tap another untapped creature you control" as a cost (CR 702.184a, 602.2b). The player chooses
      # the creature while activating (a `choose_cost` decision). Summoning sickness doesn't matter:
      # CR 302.6 restricts only a creature's own {T} abilities.
      class TapAnotherCreature < Primitive
        primitive :cost, :tap_another_creature,
                  description: "Tap another untapped creature you control, chosen while activating. A creature " \
                               "that came under your control this turn can be tapped this way.",
                  rules: %w[702.184a 601.2h 602.2b 302.6],
                  example: "tap_another_creature"

        INSTANCE = new.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          INSTANCE
        end

        def mana? = false
        def payable?(engine, object) = !choice_candidates(engine, object).empty?
        # Paid when chosen (Engine#choose_cost!).
        def pay!(_engine, _object) = nil
        def to_s = "Tap another untapped creature you control"

        def choice_candidates(engine, object)
          engine.state.battlefield.select do |id|
            other = engine.object(id)
            id != object.id && other.controller == object.controller && !other.tapped && engine.chars(other).creature?
          end
        end
      end
    end

    module Effects
      # The effect of a station ability (CR 702.184a): put charge counters on its source equal to the
      # power of the creature tapped to pay its cost. That's the creature's current power, or, if it has
      # left the battlefield, its power when it was tapped.
      class StationCharge < Effect
        def self.keys = %w[to]

        def apply(engine, ctx)
          paid = engine.object(ctx.object).paid&.first or return
          creature = paid["object"]
          n = engine.state.battlefield.include?(creature) ? engine.power(engine.object(creature)) : paid["power"]
          objects(engine, ctx).each { engine.add_counters!(engine.object(it), "charge", n) }
        end

        def to_s = "put charge counters equal to the tapped creature's power on this"
      end
    end

    module Keywords
      # Station (CR 702.184a, 2026-11-06 / 2025 rules): "Tap another untapped creature you control: Put a
      # number of charge counters on this permanent equal to the tapped creature's power. Activate only as
      # a sorcery." A station card has it at all times, whatever its charge counters (CR 722.4).
      class Station < Primitive
        primitive :keyword, :station,
                  description: "An activated ability: tap another untapped creature you control to put charge " \
                               "counters equal to its power on this permanent. Sorcery speed. Pair with " \
                               "`station_symbol` abilities for what the counters unlock.",
                  rules: %w[702.184a 722.4],
                  example: { "keywords" => ["station"] }

        def self.intrinsic_abilities
          @intrinsic_abilities ||= [
            Abilities::ActivatedAbility.new(
              sorcery: true, targets: [].freeze, costs: [Costs::TapAnotherCreature::INSTANCE].freeze,
              effects: [Effects::StationCharge.new(to: Selector.new(:self), params: {}, errors: [], path: "station")].freeze
            )
          ].freeze
        end
      end
    end

    module Abilities
      # A station symbol "{N+}" (CR 722.2): as long as this permanent has N or more charge counters, it
      # has the listed keywords and abilities and, with a power/toughness box, is a creature with that base
      # power and toughness in addition to its other types (CR 722.2a-b). A station card has no power or
      # toughness off the battlefield (CR 722.2c), so P/T goes here, not on the card.
      class StationSymbol < Primitive
        primitive :ability, :station_symbol,
                  description: "While this permanent has at least `at` charge counters it has `keywords` and " \
                               "`abilities`; with `power`/`toughness` it is also a creature with that base power " \
                               "and toughness (layers 4 and 7b).",
                  rules: %w[722.2a 722.2b 722.2c 613.1d 613.4b],
                  params: { "at" => "integer >= 1 (the N of {N+})", "power" => "integer", "toughness" => "integer",
                            "keywords" => "list of keywords", "abilities" => "list of abilities" },
                  example: { "station_symbol" => { "at" => 6, "power" => 3, "toughness" => 4, "keywords" => ["flying"] } }

        attr_reader :threshold, :power, :toughness, :keywords, :nested_abilities

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[at power toughness keywords abilities], errors, path)
          threshold = Mechanics.integer_param(params, :at, errors, path, min: 1)
          stats = %w[power toughness].map { Mechanics.fetch_param(params, it) }
          if stats.compact.size == 1 || !stats.compact.all?(Integer)
            errors << "#{path}: power and toughness must both be integers, or both be left out"
            stats = [nil, nil]
          end
          keywords = build_keywords(params, errors, path)
          abilities = build_abilities(params, errors, path)
          errors << "#{path}: needs power/toughness, keywords or abilities" if stats.compact.empty? && keywords.empty? && abilities.empty?
          new(threshold, *stats, keywords, abilities)
        end

        def self.build_keywords(params, errors, path)
          list = Mechanics.list_param(params, :keywords, errors, path).map { it.to_s.downcase.tr(" -", "__") }
          list.each { errors << "#{path}.keywords: unknown keyword #{it.inspect}" unless Enjine.registry.fetch(:keyword, it) }
          list.map(&:to_sym)
        end

        def self.build_abilities(params, errors, path)
          Mechanics.list_param(params, :abilities, errors, path).each_with_index.filter_map do |entry, i|
            ability = Mechanics.build_entry(:ability, entry, errors, "#{path}.abilities[#{i}]")
            if ability&.kind == :station_symbol
              errors << "#{path}.abilities[#{i}]: station symbols can't be nested"
              next
            end
            ability
          end
        end

        def initialize(threshold, power, toughness, keywords, abilities)
          super()
          @threshold = threshold
          @power = power
          @toughness = toughness
          @keywords = keywords.freeze
          @nested_abilities = abilities.freeze
          freeze
        end

        def kind = :station_symbol
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []

        def to_s
          bits = []
          bits << "#{power}/#{toughness} creature" if power
          bits.concat(keywords.map(&:to_s))
          bits.concat(nested_abilities.map(&:to_s))
          "#{threshold}+ | #{bits.join("; ")}"
        end
      end
    end
  end
end
