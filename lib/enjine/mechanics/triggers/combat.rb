# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # "Whenever ~ attacks" / "Whenever ~ attacks for the first time each turn".
      class Attacks < Trigger
        primitive :trigger, :attacks,
                  description: "The subject is declared as an attacker. `first_time_this_turn: true`: only the first " \
                               "time that creature attacks this turn (later combats of the turn don't trigger it).",
                  rules: %w[508.3a 603.2],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}", "first_time_this_turn" => "boolean" },
                  example: { "attacks" => { "subject" => "self", "first_time_this_turn" => true } }

        def self.keys = %w[subject first_time_this_turn]
        def event_class = Events::AttackerDeclared

        def setup(params, errors, path)
          @first_time = params["first_time_this_turn"] == true
          errors << "#{path}.first_time_this_turn: must be true or false" unless [nil, true, false].include?(params["first_time_this_turn"])
        end

        def match?(engine, event, source)
          obj = engine.state.objects[event.object] or return false
          return false if @first_time && engine.attacks_this_turn(event.object) != 1

          @subject.match?(engine, event.object, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        def to_s = "Whenever #{@subject} attacks#{" for the first time each turn" if @first_time}"
      end

      # "Whenever you attack" (CR 508.3d): once per combat, if one or more creatures attack.
      # "Whenever you attack with creatures with total power 12 or greater for the first time each turn".
      class PlayerAttacks < PlayerTrigger
        primitive :trigger, :player_attacks,
                  description: "A player declares one or more attackers (once per combat, not per creature). " \
                               "`controller`: you (default) | opponent | any. `attacking_power` ({\"at_least\": n}): " \
                               "only when the attacking creatures' total power is at least n as they're declared; " \
                               "with `first_time_this_turn: true`, only the first combat this turn in which it was.",
                  rules: %w[508.3d 508.1 603.2],
                  params: { "controller" => PLAYERS.join(" | "), "attacking_power" => "{\"at_least\": n}",
                            "first_time_this_turn" => "boolean" },
                  example: { "player_attacks" => { "controller" => "you", "attacking_power" => { "at_least" => 12 },
                                                   "first_time_this_turn" => true } }

        def self.keys = %w[controller attacking_power first_time_this_turn]
        def event_class = Events::AttacksDeclared

        def setup(params, errors, path)
          super
          power = params["attacking_power"]
          @at_least = power.is_a?(Hash) && power.keys == ["at_least"] && power["at_least"].is_a?(Integer) ? power["at_least"] : nil
          errors << "#{path}.attacking_power: must be {\"at_least\": n}" if power && @at_least.nil?
          @first_time = params["first_time_this_turn"] == true
          errors << "#{path}.first_time_this_turn: must be true or false" unless [nil, true, false].include?(params["first_time_this_turn"])
        end

        # The attackers' total power was recorded as they were declared (Engine::TurnHistory, "attack_powers").
        def match?(engine, event, source)
          return false unless player_ok?(engine, event.player, source)

          powers = engine.turn_log(engine.names.index(event.player)).fetch("attack_powers", [])
          wanted = ->(power) { power >= (@at_least || 0) }
          return false unless wanted.call(powers.last.to_i)

          !@first_time || powers[0...-1].none?(&wanted)
        end

        def to_s
          power = " with total power #{@at_least} or greater" if @at_least
          "Whenever #{who} attack#{"s" unless @controller == "you"}#{power}#{" for the first time each turn" if @first_time}"
        end
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
