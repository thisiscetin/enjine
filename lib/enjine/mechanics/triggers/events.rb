# frozen_string_literal: true

require_relative "triggers"

module Enjine
  module Mechanics
    module Triggers
      PLAYERS = %w[you opponent any].freeze

      # Base for triggers about a player ("whenever you gain life", "whenever you attack"):
      # `controller` is you (default) | opponent | any, relative to the source's controller.
      class PlayerTrigger < Trigger
        def self.keys = %w[controller]

        def setup(params, errors, path)
          @controller = params.fetch("controller", "you")
          errors << "#{path}.controller: must be one of #{PLAYERS.join(", ")}" unless PLAYERS.include?(@controller)
        end

        def player_ok?(engine, player_name, source)
          return true if @controller == "any"

          (@controller == "you") == (engine.names.index(player_name) == source["controller"])
        end

        def who = { "you" => "you", "opponent" => "an opponent", "any" => "a player" }.fetch(@controller)
      end

      # "Whenever ~ deals combat damage to a player" / "Whenever a creature you control deals damage".
      class DealsDamage < Trigger
        RECIPIENTS = %w[player creature any].freeze

        primitive :trigger, :deals_damage,
                  description: "The subject deals damage. `combat: true` only counts combat damage; `to`: player | " \
                               "creature | any (default). Triggers once per damage event (each combat damage step " \
                               "is one, so double strike can trigger twice).",
                  rules: %w[510.2 603.2 603.2c 120.3],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}", "combat" => "true | false",
                            "to" => RECIPIENTS.join(" | ") },
                  example: { "deals_damage" => { "combat" => true, "to" => "player" } }

        def self.keys = %w[subject combat to]
        def event_class = Events::DamageDealt

        def setup(params, errors, path)
          @combat = params.fetch("combat", false)
          @to = params.fetch("to", "any")
          errors << "#{path}.combat: must be true or false" unless [true, false].include?(@combat)
          errors << "#{path}.to: must be one of #{RECIPIENTS.join(", ")}" unless RECIPIENTS.include?(@to)
        end

        def match?(engine, event, source)
          return false if @combat && !event.combat
          return false unless recipient_ok?(engine, event.target)

          obj = engine.state.objects[event.source] or return false
          @subject.match?(engine, event.source, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        def recipient_ok?(engine, ref)
          case @to
          when "player" then !Filters.player_index(engine, ref).nil?
          when "creature" then engine.state.objects.key?(ref) && engine.chars(ref).creature?
          else true
          end
        end

        def to_s = "Whenever #{@subject} deals #{"combat " if @combat}damage#{" to a #{@to}" unless @to == "any"}"
      end

      # "Whenever you attack" (CR 508.3d): once per combat, if one or more creatures attack.
      class PlayerAttacks < PlayerTrigger
        primitive :trigger, :player_attacks,
                  description: "A player declares one or more attackers (once per combat, not per creature). " \
                               "`controller`: you (default) | opponent | any.",
                  rules: %w[508.3d 508.1],
                  params: { "controller" => PLAYERS.join(" | ") },
                  example: { "player_attacks" => { "controller" => "you" } }

        def event_class = Events::AttacksDeclared
        def match?(engine, event, source) = player_ok?(engine, event.player, source)
        def to_s = "Whenever #{who} attack#{"s" unless @controller == "you"}"
      end

      # "Whenever ~ becomes blocked" (CR 509.3c): once per combat, however many creatures block it.
      class BecomesBlocked < Trigger
        primitive :trigger, :becomes_blocked,
                  description: "The subject becomes blocked: once per combat when blockers are declared, even if " \
                               "several creatures block it.",
                  rules: %w[509.3c 509.1h 603.2e],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}" },
                  example: { "becomes_blocked" => { "subject" => "self" } }

        def event_class = Events::BecameBlocked

        def match?(engine, event, source)
          obj = engine.state.objects[event.object] or return false
          @subject.match?(engine, event.object, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        def to_s = "Whenever #{@subject} becomes blocked"
      end

      # "Whenever you gain life" (CR 119.9): once per life gain event; gaining 0 life isn't one.
      class GainsLife < PlayerTrigger
        primitive :trigger, :gains_life,
                  description: "A player gains life (once per life gain event; lifelink combat damage is one event " \
                               "per source). `controller`: you (default) | opponent | any.",
                  rules: %w[119.9 120.3f],
                  params: { "controller" => PLAYERS.join(" | ") },
                  example: { "gains_life" => { "controller" => "you" } }

        def event_class = Events::LifeChanged
        def match?(engine, event, source) = event.gain.positive? && player_ok?(engine, event.player, source)
        def to_s = "Whenever #{who} gain#{"s" unless @controller == "you"} life"
      end

      # "Whenever an opponent loses life".
      class LosesLife < PlayerTrigger
        primitive :trigger, :loses_life,
                  description: "A player loses life (damage to a player is life loss, CR 120.3a). " \
                               "`controller`: you (default) | opponent | any.",
                  rules: %w[119.3 120.3a],
                  params: { "controller" => PLAYERS.join(" | ") },
                  example: { "loses_life" => { "controller" => "opponent" } }

        def event_class = Events::LifeChanged
        def match?(engine, event, source) = event.loss.positive? && player_ok?(engine, event.player, source)
        def to_s = "Whenever #{who} lose#{"s" unless @controller == "you"} life"
      end

      # "Whenever you draw a card" (CR 121.2): once for each card drawn.
      class Draws < PlayerTrigger
        primitive :trigger, :draws,
                  description: "A player draws a card; triggers once per card (draws happen one at a time). " \
                               "`controller`: you (default) | opponent | any.",
                  rules: %w[121.1 121.2],
                  params: { "controller" => PLAYERS.join(" | ") },
                  example: { "draws" => { "controller" => "you" } }

        def event_class = Events::ZoneChanged

        def match?(engine, event, source)
          event.from == "library" && event.to == "hand" && event.reason == "draw" && player_ok?(engine, event.owner, source)
        end

        def to_s = "Whenever #{who} draw#{"s" unless @controller == "you"} a card"
      end

      # "Whenever ~ enters or attacks": one ability with several trigger events. It triggers once
      # per event that matches any of them (CR 603.2c).
      class AnyOf < Trigger
        primitive :trigger, :any_of,
                  description: "Triggers when any of the listed trigger conditions is met.",
                  rules: %w[603.2 603.2c],
                  params: { "(list)" => "two or more trigger conditions" },
                  example: { "any_of" => [{ "enters" => {} }, { "attacks" => {} }] }

        attr_reader :parts

        def self.scalar_params? = true

        def self.build(params, errors, path, **)
          unless params.is_a?(Array) && params.size >= 2
            errors << "#{path}: must be a list of at least two trigger conditions"
            params = []
          end
          parts = params.each_with_index.filter_map { |entry, i| Mechanics.build_entry(:trigger, entry, errors, "#{path}[#{i}]") }
          new(parts)
        end

        def initialize(parts) # rubocop:disable Lint/MissingSuper -- no subject or params of its own
          @parts = parts.freeze
          freeze
        end

        def watches?(event) = parts.any? { it.watches?(event) }
        def leaves_battlefield? = parts.any?(&:leaves_battlefield?)
        def match?(engine, event, source) = parts.any? { it.watches?(event) && it.match?(engine, event, source) }

        def to_s
          parts.map(&:to_s).each_with_index.map { |text, i| i.zero? ? text : text.sub(/\A(When|Whenever) /, "") }.join(" or ")
        end
      end
    end
  end
end
