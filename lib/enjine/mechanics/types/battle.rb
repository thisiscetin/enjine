# frozen_string_literal: true

require_relative "permanent_types"
require_relative "../abilities/play_permissions"

module Enjine
  module Mechanics
    module Types
      # Battle (CR 310). Cast at sorcery speed (CR 310.1); enters with defense counters equal to its printed
      # defense (CR 310.4b); can be attacked by its protector's opponents (CR 310.5, 310.9; Engine::Combat);
      # damage dealt to it removes defense counters (CR 120.3h, 310.6); at 0 defense it's put into its owner's
      # graveyard unless it's the source of a triggered ability that hasn't left the stack (CR 310.7, 704.5v).
      # Its protector is remembered in its memory (memory["protector"], a player index; Engine#protector).
      class Battle < PermanentType
        primitive :type, :battle,
                  description: "A permanent with a printed `defense`: it enters with that many defense counters. Each " \
                               "battle has a protector (a Siege's is an opponent of its controller, chosen as it " \
                               "enters); the protector's opponents can attack it and the protector can block for it. " \
                               "Damage dealt to it removes defense counters; with none left it's put into its " \
                               "owner's graveyard (unless it's the source of a triggered ability still waiting or " \
                               "on the stack). Every battle needs a battle type: siege (CR 205.3q).",
                  rules: %w[310.1 310.4 310.5 310.6 310.7 310.9 120.3h 704.5v 205.3q],
                  example: { "name" => "Example Invasion", "mana_cost" => "{2}{R}", "types" => ["battle"],
                             "subtypes" => ["siege"], "defense" => 4 }

        def self.validate(card, errors)
          errors << "defense: battles need an integer defense (CR 310.4)" unless card["defense"].is_a?(Integer)
          # CR 205.3q, 310.12: Siege is the only battle type, and it says who can protect the battle.
          siege = Array(card["subtypes"]).map(&:to_s).include?("siege")
          errors << "subtypes: a battle needs the battle type siege (CR 205.3q)" unless siege
        end

        # CR 310.4b: it enters with defense counters equal to its printed defense.
        def self.entering(definition, enters)
          enters["counters"]["defense"] = definition.defense if definition.defense
        end
      end
    end

    module Subtypes
      # Siege (CR 310.12): as it enters, its controller chooses an opponent to protect it (in a two-player game,
      # the opponent; no decision is asked). "When the last defense counter is removed from this permanent, exile
      # it, then you may cast it transformed without paying its mana cost" is an intrinsic triggered ability
      # (Triggers::SiegeDefeated, Effects::SiegeDefeat).
      class Siege < Primitive
        primitive :subtype, :siege,
                  description: "Battle type. As it enters, an opponent of its controller becomes its protector. When " \
                               "the last defense counter is removed from it, its controller exiles it, then may cast " \
                               "it transformed (its back face) without paying its mana cost.",
                  rules: %w[310.12 310.9 712.10 608.2g],
                  example: { "types" => ["battle"], "subtypes" => ["siege"], "defense" => 3 }

        def self.applies_to = [:battle]

        # CR 310.12: the protector is chosen from among its controller's opponents as it enters.
        def self.entering_for(engine, controller, enters)
          (enters["memory"] ||= {})["protector"] = engine.state.opponent(controller)
        end

        def self.intrinsic_abilities
          @intrinsic_abilities ||= [
            Abilities::TriggeredAbility.new(trigger: Triggers::SiegeDefeated.new.freeze, targets: [].freeze,
                                            effects: [Effects::SiegeDefeat.new].freeze)
          ].freeze
        end
      end
    end

    module Triggers
      # "When the last defense counter is removed from this permanent" (CR 310.12).
      class SiegeDefeated
        def watches?(event) = event.is_a?(Events::CountersChanged)
        def leaves_battlefield? = false
        def batched? = false

        def match?(_engine, event, source)
          event.object == source["id"] && event.counter == "defense" && event.from.positive? && event.to.zero?
        end

        def to_s = "When the last defense counter is removed from this permanent"
      end
    end

    module Effects
      # The Siege's defeat (CR 310.12): exile it, then its controller may cast it transformed (back face up,
      # CR 712.10) without paying its mana cost while this resolves (CR 608.2g). Nothing happens if it already
      # left the battlefield.
      class SiegeDefeat < CastFree
        def self.keys = []

        def initialize
          errors = []
          super(to: Selector.build("self", errors, "intrinsic:siege", targets_count: 0), params: {}, errors: errors,
                path: "intrinsic:siege")
        end

        def run(engine, ctx, locals)
          unless locals.key?("exiled")
            battle = engine.state.objects[ctx.source]
            fresh = battle&.zone == :battlefield ? engine.move!(battle.id, :exile, reason: "exile") : nil
            locals["exiled"] = fresh&.zone == :exile ? fresh.id : nil
          end
          return :done unless locals["exiled"]

          super
        end

        def to_s = "exile it, then you may cast it transformed without paying its mana cost"
        def prompt = "You may cast it transformed without paying its mana cost"

        private

        # The exiled card, back face up, if that face can be cast now (CR 712.10).
        def candidates(engine, ctx, locals)
          id = locals["exiled"]
          obj = engine.state.objects[id]
          return [] unless obj&.zone == :exile && !locals.fetch("declined", []).include?(id) && engine.catalog.fetch(obj.card).double_faced?

          engine.with_face(obj, 1) { engine.free_castable?(ctx.controller, id) } ? [{ "type" => "cast", "object" => id }] : []
        end

        def start_cast!(engine, index, id, locals)
          locals["casting"] = id
          engine.begin_cast!(index, id, via: via, face: 1)
          :wait
        end
      end
    end
  end
end
