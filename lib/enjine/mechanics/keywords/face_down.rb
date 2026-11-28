# frozen_string_literal: true

require_relative "alternative_costs"

module Enjine
  module Mechanics
    module Effects
      # Manifest (CR 701.40a) and cloak (CR 701.58a): each referenced player puts the top card of their library onto
      # the battlefield face down, `amount` times one at a time (CR 701.40e, 701.58e). See Engine::FaceDownPermanents.
      class Manifest < Effect
        primitive :effect, :manifest,
                  description: "Each referenced player (default you) manifests the top card of their library `amount` " \
                               "times (default 1): it enters face down as a nameless colorless 2/2 creature with no " \
                               "abilities. Its controller may turn it face up for its mana cost if it's a creature card " \
                               "(special action `turn_face_up`). The new permanents are this effect's results.",
                  rules: %w[701.40a 701.40b 701.40e 701.40f 701.40g 708.2 708.3],
                  params: { "amount" => "amount (default 1)", "to" => "players (default you)" },
                  example: { "manifest" => {} }

        def self.keys = %w[amount to if]
        def self.default_to = "you"
        def self.amount_optional?(_params) = true
        def as = "manifest"

        def setup(params, _errors, _path)
          @amount = Amount::Fixed.new(1) if Mechanics.fetch_param(params, :amount).nil?
        end

        def apply(engine, ctx)
          n = amount_for(engine, ctx)
          players(engine, ctx).each { |index| n.times { engine.manifest!(index, as) } }
        end

        def to_s = "#{to} #{as}#{"s" unless to.to_s == "you"} the top card of their library#{" #{amount} times" unless amount == 1}"
      end

      # Cloak (CR 701.58a): manifest, with ward {2} while face down.
      class Cloak < Manifest
        primitive :effect, :cloak,
                  description: "Each referenced player (default you) cloaks the top card of their library `amount` times " \
                               "(default 1): it enters face down as a nameless colorless 2/2 creature with ward {2}. Its " \
                               "controller may turn it face up for its mana cost if it's a creature card.",
                  rules: %w[701.58a 701.58b 701.58e 701.58f 701.58g 708.2 708.3],
                  params: { "amount" => "amount (default 1)", "to" => "players (default you)" },
                  example: { "cloak" => {} }

        def as = "cloak"
      end

      # Manifest dread (CR 701.62a): look at the top two cards of your library, manifest one of them, put the rest
      # into your graveyard. The choice is an `effect_choice` among the cards looked at (only one card: no choice).
      class ManifestDread < ChoiceEffect
        primitive :effect, :manifest_dread,
                  description: "Each referenced player (default you) manifests dread: looks at the top two cards of their " \
                               "library, manifests one of them (decision `effect_choice`) and puts the other into their " \
                               "graveyard. Triggers on it (`keyword_action` \"manifest_dread\") see it after it's complete.",
                  rules: %w[701.62a 701.62b 701.40a 701.20e],
                  params: { "to" => "players (default you)" },
                  example: { "manifest_dread" => {} }

        def self.keys = %w[to if]
        def self.default_to = "you"

        def run(engine, ctx, locals)
          unless locals.key?("queue")
            return :done unless condition.nil? || condition.true?(engine, ctx)

            locals["queue"] = players(engine, ctx)
          end
          while (index = locals["queue"].first)
            return :wait if dread!(engine, index, locals) == :wait

            locals["queue"].shift
            %w[answers looked asked].each { locals.delete(it) }
          end
          :done
        end

        def to_s = "manifest dread"

        private

        def dread!(engine, index, locals)
          looked = locals["looked"] ||= engine.player(index).library.first(2).tap { engine.look_at!(index, index, it) }
          chosen = looked.size == 1 ? looked.first : answers(locals).first&.fetch("object")
          if chosen.nil? && looked.size == 2
            return ask(engine, locals, index, "Manifest dread: choose the card to manifest; the other goes to your graveyard",
                       looked.map { { "type" => "manifest", "object" => it } })
          end
          engine.manifest!(index, "manifest", chosen) if chosen
          (looked - [chosen]).each { engine.move!(it, :graveyard, reason: "manifest_dread") if engine.state.objects[it]&.zone == :library }
          engine.emit Events::KeywordAction.new(player: engine.name(index), action: "manifest_dread", amount: 1) # CR 701.62b
        end
      end
    end

    module Abilities
      # Morph (CR 702.37a) and disguise (CR 702.168a): "You may cast this card as a 2/2 face-down creature with no text,
      # no name, no subtypes, and no mana cost [with ward {2}] by paying {3} rather than paying its mana cost." The cast
      # option is `via: "alt:<ref>"` (a sorcery-speed creature spell); `cost` is what turning it face up costs later
      # (special action `turn_face_up`, CR 702.37e, 702.168d).
      class Morph < AlternativeCost
        primitive :ability, :morph,
                  description: "Morph: you may cast this card face down as a nameless colorless 2/2 creature spell by " \
                               "paying {3} rather than its mana cost (cast option `via: \"alt:<ref>\"`). Any time you have " \
                               "priority you may turn the face-down permanent face up by paying `cost` (special action " \
                               "`{type: \"turn_face_up\", via: \"morph\"}`); abilities about entering don't trigger then.",
                  rules: %w[702.37a 702.37c 702.37d 702.37e 708.2 708.4 708.8 116.2b],
                  params: { "cost" => "mana cost string: the cost to turn it face up" },
                  example: { "morph" => { "cost" => "{1}{G}" } }

        CAST_FACE_DOWN = "{3}"

        attr_reader :face_up_cost

        def initialize(costs, path, errors)
          costs.each_index { |i| errors << "#{path}.cost[#{i}]: must be mana" unless costs[i].mana? }
          @face_up_cost = costs.empty? ? nil : Mana.sum_costs(costs.select(&:mana?).map(&:mana_cost))
          super([Costs::ManaPayment.build(CAST_FACE_DOWN, errors, path)], path, errors)
        end

        # Cast face down, a 2/2 creature spell without flash: at sorcery speed (CR 702.37c, 708.4).
        def method_for(ref, **)
          method = super
          method.merge("sorcery" => true, "alt" => method["alt"].merge("face_down" => keyword))
        end

        def to_s = "#{keyword.capitalize} #{face_up_cost}"
      end

      # Disguise (CR 702.168a): morph with ward {2} while face down.
      class Disguise < Morph
        primitive :ability, :disguise,
                  description: "Disguise: you may cast this card face down as a nameless colorless 2/2 creature spell " \
                               "with ward {2} by paying {3} rather than its mana cost (cast option `via: \"alt:<ref>\"`). " \
                               "Any time you have priority you may turn the face-down permanent face up by paying `cost` " \
                               "(special action `{type: \"turn_face_up\", via: \"disguise\"}`).",
                  rules: %w[702.168a 702.168b 702.168c 702.168d 708.2 708.4 708.8 116.2b],
                  params: { "cost" => "mana cost string: the cost to turn it face up" },
                  example: { "disguise" => { "cost" => "{4}{G}" } }
      end
    end

    module Triggers
      # "When this creature is turned face up" (CR 708.8: turning it face up isn't entering the battlefield).
      class TurnedFaceUp < Trigger
        primitive :trigger, :turned_face_up,
                  description: "The subject (default this permanent) is turned face up. On a card with morph, disguise or " \
                               "that can be manifested, it's \"when this creature is turned face up\".",
                  rules: %w[708.8 702.37e 702.168d 603.2],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, \"controller\": ...}" },
                  example: { "turned_face_up" => {} }

        def event_class = Events::TurnedFaceUp

        def match?(engine, event, source)
          obj = engine.state.objects[event.object] or return false
          @subject.match?(engine, obj.id, obj.controller, obj.card, source)
        end

        def to_s = "When #{@subject} is turned face up"
      end
    end
  end
end
