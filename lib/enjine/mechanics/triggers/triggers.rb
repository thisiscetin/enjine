# frozen_string_literal: true

module Enjine
  module Mechanics
    # Trigger conditions for triggered abilities (CR 603). A trigger watches one kind of
    # event and decides whether it matches for a given source permanent:
    #   match?(engine, event, source) -> true/false
    # `source` is a Hash with "id", "card", "controller" (for a permanent that just left
    # the battlefield it describes the object as it last existed, CR 603.10a).
    module Triggers
      # Who a trigger is about: "self" (default), "attached" (the creature the source equips or
      # enchants, CR 301.5f / 303.4m) or {"each": filter, "controller": ..., "other": true}.
      class Subject
        def self.build(data, errors, path)
          data = "self" if data.nil?
          return new(data.to_sym) if %w[self attached].include?(data)

          unless data.is_a?(Hash) && data["each"]
            errors << "#{path}: must be \"self\", \"attached\" or {\"each\": filter, \"controller\": you|opponent|any, \"other\": bool}"
            return nil
          end
          Mechanics.check_keys(data, %w[each controller other], errors, path)
          filter = Mechanics.build_entry(:filter, data["each"], errors, "#{path}.each")
          controller = data.fetch("controller", "any")
          errors << "#{path}.controller: must be one of you, opponent, any" unless %w[you opponent any].include?(controller)
          new(:each, filter, controller, other: data["other"] == true)
        end

        def initialize(kind, filter = nil, controller = nil, other: false)
          @kind = kind
          @filter = filter
          @controller = controller
          @other = other
          freeze
        end

        # Does the object `object_id` (controlled by `object_controller`, of card `card`) count?
        def match?(engine, object_id, object_controller, card, source)
          return object_id == source["id"] if @kind == :self
          return object_id == engine.state.objects[source["id"]]&.attached_to if @kind == :attached
          return false if @other && object_id == source["id"]
          return false unless controller_ok?(object_controller, source["controller"])

          types = engine.catalog.fetch(card).types
          @filter.matches_types?(types)
        end

        def controller_ok?(object_controller, you)
          @controller == "any" || (@controller == "you") == (object_controller == you)
        end

        def to_s
          return "this" if @kind == :self
          return "the attached creature" if @kind == :attached

          "#{"another " if @other}#{@filter.primitive_name.tr("_",
                                                              " ")}#{{ "you" => " you control",
                                                                       "opponent" => " an opponent controls" }[@controller]}"
        end
      end

      # Base class for trigger conditions.
      class Trigger < Primitive
        def self.keys = %w[subject]

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, keys, errors, path)
          new(params.transform_keys(&:to_s), errors, path)
        end

        def initialize(params, errors, path)
          super()
          @subject = Subject.build(params["subject"], errors, "#{path}.subject") if self.class.keys.include?("subject")
          setup(params, errors, path)
          freeze
        end

        def setup(_params, _errors, _path) = nil
        def leaves_battlefield? = false
      end

      # "When ~ enters" / "Whenever a creature you control enters" (landfall: lands you control).
      class Enters < Trigger
        primitive :trigger, :enters,
                  description: "The subject enters the battlefield.",
                  rules: %w[603.6a 603.2],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, \"controller\": you|opponent|any, \"other\": true}" },
                  example: { "enters" => { "subject" => { "each" => "land", "controller" => "you" } } }

        def event_class = Events::ZoneChanged

        def match?(engine, event, source)
          return false unless event.to == "battlefield"

          obj = engine.state.objects[event.new_id] or return false
          @subject.match?(engine, event.new_id, obj.controller, event.card, source)
        end

        def to_s = "When #{@subject} enters"
      end

      # "When ~ dies" / "Whenever another creature you control dies".
      class Dies < Trigger
        primitive :trigger, :dies,
                  description: "The subject is put into a graveyard from the battlefield. Looks back in time (CR 603.10a).",
                  rules: %w[603.6c 603.10a 700.4],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}" },
                  example: { "dies" => { "subject" => "self" } }

        def event_class = Events::ZoneChanged
        def leaves_battlefield? = true

        def match?(engine, event, source)
          return false unless event.from == "battlefield" && event.to == "graveyard"

          lki = engine.last_known(event.old_id) or return false
          @subject.match?(engine, event.old_id, lki["controller"], event.card, source)
        end

        def to_s = "When #{@subject} dies"
      end

      # "Whenever ~ attacks".
      class Attacks < Trigger
        primitive :trigger, :attacks, description: "The subject is declared as an attacker.",
                                      rules: %w[508.3a], params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}" },
                                      example: { "attacks" => { "subject" => "self" } }

        def event_class = Events::AttackerDeclared

        def match?(engine, event, source)
          obj = engine.state.objects[event.object] or return false
          @subject.match?(engine, event.object, obj.controller, obj.card, source)
        end

        def to_s = "Whenever #{@subject} attacks"
      end

      # "At the beginning of your upkeep" / "... of each end step".
      class StepBegins < Trigger
        STEPS = %w[untap upkeep draw precombat_main beginning_of_combat declare_attackers declare_blockers
                   combat_damage end_of_combat postcombat_main end cleanup].freeze
        WHOSE = %w[your each opponent].freeze

        primitive :trigger, :step_begins,
                  description: "A step begins. `whose`: \"your\" (default), \"each\" or \"opponent\".",
                  rules: %w[603.6b 503.1a 513.1a],
                  params: { "step" => "upkeep | draw | precombat_main | end | ...", "whose" => WHOSE.join(" | ") },
                  example: { "step_begins" => { "step" => "upkeep", "whose" => "your" } }

        def self.keys = %w[step whose]
        def event_class = Events::StepBegan

        def setup(params, errors, path)
          @step = params["step"]
          @whose = params.fetch("whose", "your")
          errors << "#{path}.step: must be one of #{STEPS.join(", ")}" unless STEPS.include?(@step)
          errors << "#{path}.whose: must be one of #{WHOSE.join(", ")}" unless WHOSE.include?(@whose)
        end

        def match?(engine, event, source)
          return false unless event.step == @step

          active = engine.state.active
          @whose == "each" || (@whose == "your") == (active == source["controller"])
        end

        def to_s = "At the beginning of #{@whose == "each" ? "each" : @whose} #{@step.tr("_", " ")}"
      end

      # "Whenever you cast a spell" (optionally only spells with a given card type).
      class Cast < Trigger
        primitive :trigger, :cast,
                  description: "A player casts a spell. `controller`: you (default) | opponent | any; " \
                               "`spell`: optional filter on the spell's card types (e.g. \"creature\", \"noncreature\").",
                  rules: %w[603.2 601.2i],
                  params: { "controller" => "you | opponent | any", "spell" => "creature | noncreature | instant_or_sorcery" },
                  example: { "cast" => { "controller" => "you", "spell" => "noncreature" } }

        SPELLS = %w[creature noncreature instant_or_sorcery].freeze

        def self.keys = %w[controller spell]
        def event_class = Events::SpellCast

        def setup(params, errors, path)
          @controller = params.fetch("controller", "you")
          @spell = params["spell"]
          errors << "#{path}.controller: must be one of you, opponent, any" unless %w[you opponent any].include?(@controller)
          errors << "#{path}.spell: must be one of #{SPELLS.join(", ")}" if @spell && !SPELLS.include?(@spell)
        end

        def match?(engine, event, source)
          caster = engine.names.index(event.player)
          return false unless @controller == "any" || (@controller == "you") == (caster == source["controller"])

          types = engine.catalog.fetch(event.card).types
          case @spell
          when "creature" then types.include?(:creature)
          when "noncreature" then !types.include?(:creature)
          when "instant_or_sorcery" then types.intersect?(%i[instant sorcery])
          else true
          end
        end

        def to_s = "Whenever #{@controller == "you" ? "you cast" : "a player casts"} a #{@spell || "spell"}"
      end
    end
  end
end
