# frozen_string_literal: true

module Enjine
  module Mechanics
    # Trigger conditions for triggered abilities (CR 603). A trigger watches one kind of
    # event and decides whether it matches for a given source permanent:
    #   match?(engine, event, source) -> true/false
    # `source` is a Hash with "id", "card", "controller" (for a permanent that just left
    # the battlefield it describes the object as it last existed, CR 603.10a).
    module Triggers
      # What an event tells a triggered ability about itself (CR 603.2): the object and player it is
      # about and a number ("that many"). Effects name them with {"triggering": "object" | "player"}
      # and the amount {"triggering": "amount"}; "card" is the object's card, for conditions.
      def self.event_facts(engine, event)
        facts = {}
        case event
        when Events::ZoneChanged then facts.merge!("object" => event.new_id, "player" => engine.names.index(event.owner))
        when Events::SpellCast, Events::DilemmaFaced, Events::Tapped, Events::AttackerDeclared, Events::BecameBlocked
          facts["object"] = event.object
        when Events::AbilityActivated then facts["object"] = event.source
        when Events::DamageDealt
          facts.merge!("object" => event.source, "amount" => event.amount, "player" => Filters.player_index(engine, event.target))
        when Events::LifeChanged then facts["amount"] = [event.gain, event.loss].max
        when Events::CountersChanged then facts.merge!("object" => event.object, "amount" => event.to - event.from)
        when Events::StepBegan then facts["player"] = engine.state.active # "that player": whose step it is
        end
        # CR 601.2h: the mana spent to cast "that spell", as it was cast
        facts["mana_spent"] = engine.state.objects[event.object]&.mana_spent&.dup if event.is_a?(Events::SpellCast)
        facts["player"] ||= engine.names.index(event.player) if event.respond_to?(:player)
        facts["card"] = event.respond_to?(:card) ? event.card : engine.state.objects[facts["object"]]&.card
        facts.compact
      end

      def self.filter_words(filter)
        return nil if filter.nil?

        filter.is_a?(Class) ? filter.primitive_name.tr("_", " ") : filter.to_s
      end

      # One entry (the event facts) per occurrence of the trigger event in `event` (CR 603.2c). Works for
      # any trigger condition, including ones that only answer match? (a Saga's chapter trigger).
      def self.occurrences(trigger, engine, event, source)
        return trigger.occurrences(engine, event, source) if trigger.respond_to?(:occurrences)

        trigger.match?(engine, event, source) ? [event_facts(engine, event)] : []
      end

      # Who a trigger is about: "self" (default), "attached" (the creature the source equips or
      # enchants, CR 301.5f / 303.4m), "watched" (the objects a delayed triggered ability was created
      # to watch, CR 603.7c: "when that creature dies this turn") or {"each": filter, "controller": ...,
      # "other": true}.
      class Subject
        def self.build(data, errors, path)
          data = "self" if data.nil?
          return new(data.to_sym) if %w[self attached watched].include?(data)

          unless data.is_a?(Hash) && data["each"]
            errors << "#{path}: must be \"self\", \"attached\", \"watched\" or " \
                      "{\"each\": filter, \"controller\": you|opponent|any, \"other\": bool}"
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
        # `types`: its card types at the time (current or last known, CR 603.10a); printed if omitted.
        def match?(engine, object_id, object_controller, card, source, types: nil)
          return object_id == source["id"] if @kind == :self
          return object_id == engine.state.objects[source["id"]]&.attached_to if @kind == :attached
          return Array(source["watched"]).include?(object_id) if @kind == :watched
          return false if @other && object_id == source["id"]
          return false unless controller_ok?(object_controller, source["controller"])

          obj = engine.state.objects[object_id]
          return @filter.match_for?(engine, object_id, source["controller"], source["id"]) if obj&.zone == :battlefield

          # Left the battlefield: as it last existed (CR 603.10a), from its card, last known types and counters.
          defn = engine.catalog.fetch(card)
          chars = types ? defn.printed_characteristics.with(types: types) : defn.printed_characteristics
          lki = engine.last_known(object_id) || {}
          token = lki.fetch("token") { defn.token? } # a token copy of a card (CR 111.1)
          @filter.matches_facts?(Filters::Facts.new(chars: chars, counters: lki.fetch("counters", nil) || {}, token: token,
                                                    chosen: engine.state.objects[source["id"]]&.memory))
        end

        def controller_ok?(object_controller, you)
          @controller == "any" || (@controller == "you") == (object_controller == you)
        end

        def to_s
          return "this" if @kind == :self
          return "the attached creature" if @kind == :attached
          return "that object" if @kind == :watched

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

        # Whether this trigger looks at `event` at all (one event class by default).
        def watches?(event) = event.is_a?(event_class)

        # "One or more ...": all occurrences in one event batch trigger it once (CR 603.2c).
        def batched? = false

        # "When you cast this spell": the trigger functions while its card is a spell on the stack.
        def own_spell? = false

        # The event facts of each occurrence this trigger matches (CR 603.2c); see Triggers.event_facts.
        def occurrences(engine, event, source) = match?(engine, event, source) ? [Triggers.event_facts(engine, event)] : []
      end

      # "When ~ enters" / "Whenever a creature you control enters" (landfall: lands you control).
      # `untapped: true` is "when this land enters untapped": the status it entered with (CR 614.12).
      class Enters < Trigger
        primitive :trigger, :enters,
                  description: "The subject enters the battlefield. `untapped: true`: only if it entered untapped.",
                  rules: %w[603.6a 603.2 614.12],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, \"controller\": you|opponent|any, \"other\": true}",
                            "untapped" => "true | false" },
                  example: { "enters" => { "subject" => { "each" => "land", "controller" => "you" } } }

        def self.keys = %w[subject untapped]
        def event_class = Events::ZoneChanged

        def setup(params, errors, path)
          @untapped = params.fetch("untapped", false)
          errors << "#{path}.untapped: must be true or false" unless [true, false].include?(@untapped)
        end

        def match?(engine, event, source)
          return false unless event.to == "battlefield"

          obj = engine.state.objects[event.new_id] or return false
          return false if @untapped && obj.tapped

          @subject.match?(engine, event.new_id, obj.controller, event.card, source, types: engine.chars(obj).types)
        end

        def to_s = "When #{@subject} enters#{" untapped" if @untapped}"
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
          @subject.match?(engine, event.old_id, lki["controller"], event.card, source, types: lki["types"])
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
          @subject.match?(engine, event.object, obj.controller, obj.card, source, types: engine.chars(obj).types)
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

      # Matching the source's "as this enters" choice (CR 614.12, 607.2): `"name": "chosen"` is "with the
      # chosen name" (CR 201.4) and `"mana_value": "chosen"` is "with mana value equal to the chosen number".
      module ChosenMatch
        def setup_chosen(params, errors, path)
          @chosen = %w[name mana_value].select { params.key?(it) }
          @chosen.each { errors << "#{path}.#{it}: must be \"chosen\"" unless params[it] == "chosen" }
        end

        # `card`: the card the spell or source is; `x_value`: the X announced for a spell on the stack (CR 202.3e).
        def chosen_ok?(engine, source, card, x_value = 0)
          memory = engine.state.objects[source["id"]]&.memory || {}
          defn = engine.catalog.fetch(card)
          @chosen.all? do |key|
            if key == "name" then !memory["chosen_name"].nil? && defn.name == memory["chosen_name"]
            else
              cost = defn.mana_cost
              !memory["chosen_number"].nil? && (cost ? cost.mana_value + (cost.x_symbols * x_value.to_i) : 0) == memory["chosen_number"]
            end
          end
        end

        def chosen_words = @chosen.map { it == "name" ? " with the chosen name" : " with mana value equal to the chosen number" }.join
      end

      # "Whenever you cast a spell" (optionally only matching spells); "when you cast this spell" (`self`).
      # It triggers once the spell becomes cast (CR 601.2i), so a cast that is cancelled never triggers it.
      class Cast < Trigger
        include ChosenMatch

        primitive :trigger, :cast,
                  description: "A player casts a spell. `controller`: you (default) | opponent | any; `spell`: creature | " \
                               "noncreature | instant_or_sorcery, or any spell filter, e.g. {\"spell\": {\"subtypes\": " \
                               "[\"saga\"]}} or {\"one_of\": [...]} for \"creature or Spacecraft spell\"; `name` / " \
                               "`mana_value`: \"chosen\" (the source's as-it-entered choice); `self: true`: \"when you cast " \
                               "this spell\" (it functions on the stack).",
                  rules: %w[603.2 601.2i 113.6 202.3e 201.4 607.2],
                  params: { "controller" => "you | opponent | any", "spell" => "creature | noncreature | instant_or_sorcery | filter",
                            "name" => "\"chosen\"", "mana_value" => "\"chosen\"", "self" => "true" },
                  example: { "cast" => { "controller" => "you", "spell" => "noncreature" } }

        SPELLS = %w[creature noncreature instant_or_sorcery].freeze

        def self.keys = %w[controller spell name mana_value self]
        def event_class = Events::SpellCast
        def own_spell? = @self

        def setup(params, errors, path)
          @controller = params.fetch("controller", "you")
          @self = params["self"] == true
          raw = params["spell"]
          errors << "#{path}.controller: must be one of you, opponent, any" unless %w[you opponent any].include?(@controller)
          errors << "#{path}.self: must be true" unless params["self"].nil? || @self
          if raw.is_a?(String) && SPELLS.include?(raw) then @spell = raw
          elsif !raw.nil? && !raw.is_a?(String) then @filter = Mechanics.build_entry(:filter, raw, errors, "#{path}.spell")
          elsif raw then errors << "#{path}.spell: must be one of #{SPELLS.join(", ")} or a spell filter"
          end
          setup_chosen(params, errors, path)
        end

        def match?(engine, event, source)
          return event.object == source["id"] if @self

          caster = engine.names.index(event.player)
          return false unless @controller == "any" || (@controller == "you") == (caster == source["controller"])
          return false unless spell_ok?(engine, event, caster, source)

          chosen_ok?(engine, source, event.card, engine.state.objects[event.object]&.x)
        end

        def spell_ok?(engine, event, caster, source)
          return @filter.match_for?(engine, event.object, caster, source["id"]) if @filter # "of the chosen color"

          types = engine.catalog.fetch(event.card).types
          case @spell
          when "creature" then types.include?(:creature)
          when "noncreature" then !types.include?(:creature)
          when "instant_or_sorcery" then types.intersect?(%i[instant sorcery])
          else true
          end
        end

        def to_s
          return "When you cast this spell" if @self

          kind = Triggers.filter_words(@filter) || @spell || "spell"
          "Whenever #{{ "you" => "you cast", "opponent" => "an opponent casts" }.fetch(@controller, "a player casts")} a #{kind}" \
            "#{chosen_words}"
        end
      end
    end
  end
end
