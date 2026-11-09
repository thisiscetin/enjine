# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # The cost of crew N (CR 702.122a): "Tap any number of other untapped creatures you control with total
      # power N or greater." Each creature is a `choose_cost` decision and is tapped as it is chosen (cancelling
      # untaps it); once their total power is N or more the player may stop (`done`) or tap more. Summoning
      # sickness doesn't matter (CR 302.6). As the ability is activated each one crews the Vehicle (CR 702.122b).
      class Crew < Primitive
        attr_reader :power

        def initialize(power)
          super()
          @power = power
          freeze
        end

        def mana? = false
        def pay!(_engine, _object) = nil
        def choices_needed = power
        def to_s = "Tap any number of other untapped creatures you control with total power #{power} or greater"

        # The power a creature crews with (the place for "crews Vehicles as though its power were 2 greater").
        def crew_power(engine, creature) = engine.power(creature)

        def candidates(engine, object)
          engine.state.battlefield.select do |id|
            other = engine.object(id)
            id != object.id && other.controller == object.controller && !other.tapped && engine.chars(other).creature?
          end
        end

        def payable?(engine, object) = candidates(engine, object).sum { crew_power(engine, engine.object(it)) } >= power
        def choice_options(engine, object, _chosen) = candidates(engine, object).map { { object: it } }

        def choose!(engine, option)
          creature = engine.object(option[:object])
          engine.tap!(creature)
          { "object" => creature.id, "power" => crew_power(engine, creature), "tapped" => true }
        end

        def finishable?(entries) = entries.sum { it["power"] } >= power

        # Chosen once the total power is enough and the player is done (or nothing is left to tap).
        def chosen?(engine, object, entries, done)
          finishable?(entries) && (done || candidates(engine, object).empty?)
        end

        # CR 702.122b: each creature tapped to pay the cost crews the Vehicle.
        def pay_chosen!(engine, object, entries)
          entries.each { engine.emit Events::CrewedVehicle.new(object: it["object"], vehicle: object.id) }
        end
      end
    end

    module Effects
      # The effect of a crew ability (CR 702.122a, 702.122e): this permanent becomes an artifact creature until
      # end of turn, and it "becomes crewed" by the creatures tapped to pay the cost.
      class Crewed < Effect
        def self.keys = %w[to]

        def apply(engine, ctx)
          vehicle = objects(engine, ctx).first or return
          engine.add_continuous_effect!("add_types", ctx, [vehicle], "types" => %w[artifact creature], "supertypes" => [],
                                                                     "subtypes" => [])
          crew = (engine.object(ctx.object).paid || []).map { it["object"] }
          engine.emit Events::BecameCrewed.new(object: vehicle, crew: crew)
        end

        def to_s = "this becomes an artifact creature until end of turn"
      end
    end

    module Abilities
      # Crew N (CR 702.122a): an activated ability of a Vehicle. Written {"crew": {"power": N}}.
      class Crew < ActivatedAbility
        primitive :ability, :crew,
                  description: "Crew N: tap any number of other untapped creatures you control with total power N or " \
                               "more (chosen one at a time; `done` once the total is enough): this permanent becomes " \
                               "an artifact creature until end of turn. A Vehicle has its printed power and toughness " \
                               "only while it's a creature.",
                  rules: %w[702.122a 702.122b 702.122e 301.7 301.7a 301.7b 208.3 302.6],
                  params: { "power" => "integer >= 1 (the N of crew N)" },
                  example: { "crew" => { "power" => 3 } }

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[power], errors, path)
          n = Mechanics.integer_param(params, :power, errors, path, min: 1)
          new(sorcery: false, targets: [].freeze, costs: [Costs::Crew.new(n)].freeze,
              effects: [Effects::Crewed.new(to: Selector.new(:self), params: {}, errors: [], path: path)].freeze)
        end

        def power = costs.first.power
        def to_s = "Crew #{power}"
      end
    end

    module Triggers
      # "Whenever this Vehicle becomes crewed" (CR 702.122e): whenever its crew ability resolves.
      class BecomesCrewed < Trigger
        primitive :trigger, :becomes_crewed,
                  description: "A crew ability of the subject resolves (it becomes crewed).",
                  rules: %w[702.122e 603.2],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}" },
                  example: { "becomes_crewed" => {} }

        def event_class = Events::BecameCrewed

        def match?(engine, event, source)
          obj = engine.state.objects[event.object] or return false
          @subject.match?(engine, event.object, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        def occurrences(engine, event, source)
          return [] unless match?(engine, event, source)

          obj = engine.object(event.object)
          [{ "object" => obj.id, "player" => obj.controller, "card" => obj.card, "amount" => event.crew.size }]
        end

        def to_s = "Whenever #{@subject} becomes crewed"
      end

      # "Whenever this creature crews a Vehicle" (CR 702.122b): it was tapped to pay a crew cost. The event's
      # object for the effects ("that Vehicle") is the Vehicle.
      class CrewsVehicle < Trigger
        primitive :trigger, :crews_vehicle,
                  description: "The subject (a creature) crews a Vehicle: it's tapped to pay that Vehicle's crew cost. " \
                               "{\"triggering\": \"object\"} is the Vehicle.",
                  rules: %w[702.122b 603.2],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}" },
                  example: { "crews_vehicle" => { "subject" => "self" } }

        def event_class = Events::CrewedVehicle

        def match?(engine, event, source)
          obj = engine.state.objects[event.object] or return false
          @subject.match?(engine, event.object, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        def occurrences(engine, event, source)
          return [] unless match?(engine, event, source)

          vehicle = engine.state.objects[event.vehicle]
          [{ "object" => event.vehicle, "player" => engine.object(event.object).controller, "card" => vehicle&.card }.compact]
        end

        def to_s = "Whenever #{@subject} crews a Vehicle"
      end
    end
  end
end
