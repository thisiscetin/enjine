# frozen_string_literal: true

require_relative "../effects/delayed_triggers"
require_relative "../abilities/play_permissions"

module Enjine
  module Mechanics
    module Keywords
      # Paradigm (CR 702.192a): two spell abilities that follow the spell's own effects. "If this is the first
      # time a spell you control with this spell's name has resolved this game, at the beginning of each of
      # your precombat main phases for the rest of the game, create a copy of this object in exile. You may
      # cast the copy without paying its mana cost" and "Exile this spell." The engine applies them as the
      # spell finishes resolving (Engine::Resolution#finish_resolution!); the delayed triggered ability is
      # "delayed:keyword:paradigm" of the spell's card and lasts for the rest of the game.
      class Paradigm < Primitive
        primitive :keyword, :paradigm,
                  description: "As this instant or sorcery finishes resolving: if it's the first time a spell you " \
                               "control with its name has resolved this game, at the beginning of each of your " \
                               "precombat main phases for the rest of the game you create a copy of the card in exile " \
                               "and may cast it without paying its mana cost. Then the spell is exiled.",
                  rules: %w[702.192a 707.12 603.7 608.2g], example: { "keywords" => ["paradigm"] }

        REF = "delayed:keyword:paradigm"

        # Carries the delayed triggered ability, so the card's data names it (CardDefinition.keyword_delayed).
        class Rule < Primitive
          def kind = :paradigm
          def mana_ability? = false
          def allowed_types = %i[instant sorcery]
          def try_effects = [Paradigm.delayed]
          def to_s = "Paradigm"
        end

        def self.intrinsic_abilities = @intrinsic_abilities ||= [Rule.new.freeze].freeze
        def self.delayed = @delayed ||= Effects::ParadigmDelayed.build({}, [], "keyword:paradigm")

        def self.validate(card, errors)
          types = Array(card["types"]).map(&:to_s)
          errors << "keywords: paradigm is only for instants and sorceries" unless types.intersect?(%w[instant sorcery])
        end

        # As the spell finishes resolving: the delayed trigger the first time a spell with its name resolved
        # for its controller (remembered in their game log), then it's exiled instead of going to the
        # graveyard. False if the spell doesn't have paradigm.
        def self.resolved!(engine, spell)
          chars = engine.chars(spell)
          return false unless chars.keyword?(:paradigm)

          names = engine.game_log(spell.controller)["paradigm"] ||= []
          unless names.include?(chars.name)
            names << chars.name
            engine.create_delayed_trigger!("controller" => spell.controller, "source" => spell.id, "card" => spell.card,
                                           "ability" => REF, "game" => true)
          end
          engine.move!(spell.id, :exile, reason: "paradigm")
          true
        end
      end
    end

    module Effects
      # Paradigm's delayed triggered ability (CR 702.192a): at the beginning of each of your precombat main
      # phases, create a copy of the card in exile; you may cast it without paying its mana cost (a copy not
      # cast ceases to exist, CR 707.12). Not a card-data primitive.
      class ParadigmDelayed < DelayedTrigger
        MAIN = { "step_begins" => { "step" => "precombat_main", "whose" => "your" } }.freeze

        def self.keys = []

        def setup(_params, errors, path)
          @ref = "delayed:#{path}"
          trigger = Mechanics.build_entry(:trigger, MAIN, errors, "#{path}.when")
          cast = CastFree.build({ "to" => { "result" => 0 } }, errors, "#{path}.cast", results_count: 1)
          @delayed_ability = Abilities::TriggeredAbility.new(targets: [].freeze, effects: [ParadigmCopy.new, cast].freeze,
                                                             trigger: trigger)
        end

        def to_s = "at the beginning of each of your precombat main phases, copy this card in exile; you may cast the copy free"
      end

      # Creates a copy of the paradigm card (the delayed trigger's card) in exile, owned by its controller.
      class ParadigmCopy < Effect
        def self.keys = []

        def initialize = super(to: nil, params: {}, errors: [], path: "paradigm")
        def apply(engine, ctx) = engine.create_card_copy!([engine.object(ctx.object).card, {}], ctx.controller, :exile)
        def to_s = "create a copy of this card in exile"
      end
    end
  end
end
