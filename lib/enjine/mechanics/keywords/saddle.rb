# frozen_string_literal: true

require_relative "crew"

module Enjine
  module Mechanics
    module Costs
      # The cost of saddle N (CR 702.171a): "Tap any number of other untapped creatures you control with total
      # power N or greater", chosen exactly like crew's. Each creature tapped for it saddles the permanent
      # (CR 702.171c).
      class Saddle < Crew
        def choose!(engine, option) = super.merge("saddles" => true)

        def pay_chosen!(engine, object, entries)
          entries.each { engine.emit Events::SaddledMount.new(object: it["object"], mount: object.id) }
        end
      end
    end

    module Effects
      # "[It] becomes saddled until end of turn" (CR 702.171a-b): the saddled designation, which stays until the
      # turn ends or the permanent leaves the battlefield and isn't copiable (it lives on the object, stamped
      # with the turn, Engine#saddled?). The effect of a saddle ability, and of cards that saddle a Mount
      # without its saddle ability.
      class BecomeSaddled < Effect
        primitive :effect, :become_saddled,
                  description: "Each referenced permanent (default: this one) becomes saddled until end of turn " \
                               "(filters: `\"saddled\": true`).",
                  rules: %w[702.171a 702.171b],
                  params: { "to" => "selector of permanents (default self)" },
                  example: { "become_saddled" => { "to" => { "target" => 0 } } }

        def self.keys = %w[to if]
        def self.default_to = "self"
        def to_s = "becomes saddled until end of turn → #{to}"

        def apply(engine, ctx)
          riders = (engine.object(ctx.object).paid || []).select { it["saddles"] }.map { it["object"] }
          objects(engine, ctx).each do |id|
            engine.saddle!(id)
            engine.emit Events::BecameSaddled.new(object: id, riders: riders)
          end
        end
      end
    end

    module Abilities
      # Saddle N (CR 702.171a): an activated ability of a Mount, at sorcery speed. Written {"saddle": {"power": N}}.
      class Saddle < ActivatedAbility
        primitive :ability, :saddle,
                  description: "Saddle N: tap any number of other untapped creatures you control with total power N " \
                               "or more (chosen one at a time; `done` once the total is enough): this permanent " \
                               "becomes saddled until end of turn. Activate only as a sorcery.",
                  rules: %w[702.171a 702.171b 702.171c],
                  params: { "power" => "integer >= 1 (the N of saddle N)" },
                  example: { "saddle" => { "power" => 2 } }

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[power], errors, path)
          n = Mechanics.integer_param(params, :power, errors, path, min: 1)
          new(sorcery: true, targets: [].freeze, costs: [Costs::Saddle.new(n)].freeze,
              effects: [Effects::BecomeSaddled.new(to: Selector.new(:self), params: {}, errors: [], path: path)].freeze)
        end

        def power = costs.first.power
        def to_s = "Saddle #{power}"
      end
    end

    module Triggers
      # "Whenever this creature becomes saddled" (CR 702.171b): a saddle ability (or another effect) saddled it.
      class BecomesSaddled < BecomesCrewed
        primitive :trigger, :becomes_saddled,
                  description: "The subject becomes saddled (its saddle ability resolved, or an effect saddled it).",
                  rules: %w[702.171b 603.2],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}" },
                  example: { "becomes_saddled" => {} }

        def event_class = Events::BecameSaddled

        def occurrences(engine, event, source)
          return [] unless match?(engine, event, source)

          obj = engine.object(event.object)
          [{ "object" => obj.id, "player" => obj.controller, "card" => obj.card, "amount" => event.riders.size }]
        end

        def to_s = "Whenever #{@subject} becomes saddled"
      end

      # "Whenever this creature saddles a Mount" (CR 702.171c): it was tapped to pay a saddle cost. The event's
      # object for the effects ("that Mount") is the Mount.
      class SaddlesMount < CrewsVehicle
        primitive :trigger, :saddles_mount,
                  description: "The subject (a creature) saddles a Mount: it's tapped to pay that Mount's saddle " \
                               "cost. {\"triggering\": \"object\"} is the Mount.",
                  rules: %w[702.171c 603.2],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}" },
                  example: { "saddles_mount" => { "subject" => "self" } }

        def event_class = Events::SaddledMount

        def occurrences(engine, event, source)
          return [] unless match?(engine, event, source)

          mount = engine.state.objects[event.mount]
          [{ "object" => event.mount, "player" => engine.object(event.object).controller, "card" => mount&.card }.compact]
        end

        def to_s = "Whenever #{@subject} saddles a Mount"
      end
    end
  end
end
