# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # "Whenever ~ attacks".
      class Attacks < Trigger
        primitive :trigger, :attacks, description: "The subject is declared as an attacker.",
                                      rules: %w[508.3a], params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}" },
                                      example: { "attacks" => { "subject" => "self" } }

        def event_class = Events::AttackerDeclared

        def match?(engine, event, source)
          obj = engine.state.objects[event.object] or return false
          @subject.match?(engine, event.object, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        def to_s = "Whenever #{@subject} attacks"
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

      # "Whenever ~ blocks" / "Whenever this creature blocks a creature with flying" (CR 509.3a-b, 509.3f).
      class Blocks < Trigger
        primitive :trigger, :blocks,
                  description: "The subject is declared as a blocker. With `blocking`, only when the attacking creature " \
                               "it blocks matches that filter (\"blocks a creature with flying\"). {\"triggering\": " \
                               "\"object\"} is the blocking creature.",
                  rules: %w[509.3a 509.3b 509.3f 603.2],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}", "blocking" => "filter" },
                  example: { "blocks" => { "blocking" => { "creature" => { "keywords" => ["flying"] } } } }

        def self.keys = %w[subject blocking]
        def event_class = Events::BlockerDeclared

        def setup(params, errors, path)
          @blocking = params["blocking"] && Mechanics.build_entry(:filter, params["blocking"], errors, "#{path}.blocking")
        end

        def match?(engine, event, source)
          obj = engine.state.objects[event.object] or return false
          return false if @blocking && !@blocking.match_for?(engine, event.attacker, source["controller"], source["id"])

          @subject.match?(engine, event.object, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        def to_s = "Whenever #{@subject} blocks#{" a #{Triggers.filter_words(@blocking)}" if @blocking}"
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
    end
  end
end
