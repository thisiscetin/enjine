# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "Exile them, then meld them into [back face]" (CR 701.42a, 713.1a): the source, and a creature named
      # `with` that its controller both owns and controls, are exiled; if the two are a meld pair (CR 701.42b)
      # they come back as one permanent with the combined back face up (Engine::Faces#meld!), else they stay
      # exiled (CR 701.42c). The melded permanent is its result.
      class Meld < Effect
        primitive :effect, :meld,
                  description: "Exile this permanent and a creature named `with` that you both own and control, then " \
                               "meld them: a meld pair (cards with layout \"meld\" sharing a back face) enters the " \
                               "battlefield as one permanent with that back face up. When it leaves the battlefield, " \
                               "both cards go to the new zone.",
                  rules: %w[701.42a 701.42b 701.42c 713.1a 713.6 713.8],
                  params: { "with" => "the name of the other card of the pair" },
                  example: { "meld" => { "with" => "Fang, Fearless l'Cie" } }

        def self.keys = %w[with if]
        def self.default_to = "self"

        def setup(params, errors, path)
          @with = Mechanics.fetch_param(params, :with)
          errors << "#{path}.with: must be a card name" unless @with.is_a?(String) && !@with.empty?
        end

        def apply(engine, ctx)
          pair = [Condition::MeldWith.own(engine, ctx.controller, ctx.source),
                  Condition::MeldWith.partner(engine, ctx.controller, @with)]
          exiled = pair.compact.filter_map { engine.move!(it, :exile, reason: "meld") }
          engine.meld!(*exiled, ctx.controller) if exiled.size == 2
        end

        def to_s = "exile this and #{@with}, then meld them"
      end
    end

    class Condition
      # "If you both own and control [this] and a creature named [name]" (the meld cards' condition, CR 713.1a):
      # `{"meld_with": name}`.
      class MeldWith
        def self.build(data, errors, path)
          Mechanics.check_keys(data, %w[meld_with], errors, path)
          name = data["meld_with"]
          errors << "#{path}.meld_with: must be a card name" unless name.is_a?(String) && !name.empty?
          new(name)
        end

        # The source, if it's a permanent `index` owns and controls.
        def self.own(engine, index, id)
          obj = engine.state.objects[id]
          id if obj&.zone == :battlefield && obj.owner == index && obj.controller == index
        end

        # A creature named `name` that `index` owns and controls.
        def self.partner(engine, index, name)
          engine.state.battlefield.find do |id|
            obj = engine.object(id)
            obj.owner == index && obj.controller == index && (c = engine.chars(obj)).creature? && c.name == name
          end
        end

        def initialize(name)
          @name = name
          freeze
        end

        def true?(engine, ctx)
          !MeldWith.own(engine, ctx.controller, ctx.source).nil? && !MeldWith.partner(engine, ctx.controller, @name).nil?
        end

        def to_s = "you both own and control this and a creature named #{@name}"
      end
    end
  end
end
