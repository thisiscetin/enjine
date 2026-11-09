# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # Trigger conditions for triggered abilities (CR 603). A trigger watches one kind of
      # event and decides whether it matches for a given source permanent:
      #   match?(engine, event, source) -> true/false
      # `source` is a Hash with "id", "card", "controller" (for a permanent that just left
      # the battlefield it describes the object as it last existed, CR 603.10a).
      # What an event tells a triggered ability about itself (CR 603.2): the object and player it is
      # about and a number ("that many"). Effects name them with {"triggering": "object" | "player"}
      # and the amount {"triggering": "amount"}; "card" is the object's card, for conditions.
      def self.event_facts(engine, event)
        facts = {}
        case event
        when Events::ZoneChanged then facts.merge!("object" => event.new_id, "player" => engine.names.index(event.owner))
        when Events::SpellCast, Events::DilemmaFaced, Events::Tapped, Events::AttackerDeclared, Events::BecameBlocked,
             Events::BlockerDeclared
          facts["object"] = event.object
        when Events::AbilityActivated then facts.merge!("object" => event.source, "ability" => event.object)
        when Events::TriggerPutOnStack then facts["ability"] = event.object
        when Events::DamageDealt
          facts.merge!("object" => event.source, "amount" => event.amount, "player" => Filters.player_index(engine, event.target))
        when Events::LifeChanged then facts["amount"] = [event.gain, event.loss].max
        when Events::CountersChanged then facts.merge!("object" => event.object, "amount" => event.to - event.from)
        when Events::StepBegan then facts["player"] = engine.state.active # "that player": whose step it is
        end
        cast_facts(engine, event, facts) if event.is_a?(Events::SpellCast)
        facts["player"] ||= engine.names.index(event.player) if event.respond_to?(:player)
        facts["card"] = event.respond_to?(:card) ? event.card : engine.state.objects[facts["object"]]&.card
        facts.compact
      end

      # CR 601.2h: the mana spent to cast "that spell" and the sources of what artifacts made, as it was cast;
      # storm's "that many" (CR 702.40a).
      def self.cast_facts(engine, event, facts)
        spell = engine.state.objects[event.object]
        facts["mana_spent"] = spell&.mana_spent&.dup
        facts["mana_from"] = Snapshot.deep_copy(spell&.memory&.[]("mana_from"))
        facts["amount"] = Triggers.spells_before(engine)
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

      # A `batched` flag: "one or more ..." triggers once per event batch (CR 603.2c), and its "that many"
      # ({"triggering": "amount"}) is how many occurrences the batch had (Engine::Triggering#queue_trigger).
      module Batched
        def setup_batched(params, errors, path)
          @batched = params.fetch("batched", false)
          errors << "#{path}.batched: must be true or false" unless [true, false].include?(@batched)
        end

        def batched? = @batched
      end

      # Matching a card (not a permanent) by its printed characteristics.
      module CardMatch
        def setup_card(params, errors, path)
          @card = params["card"] && Mechanics.build_entry(:filter, params["card"], errors, "#{path}.card")
        end

        def card_ok?(engine, card)
          return true unless @card

          defn = engine.catalog.fetch(card)
          @card.matches_facts?(Filters::Facts.new(chars: defn.printed_characteristics, counters: {}, token: defn.token?))
        end

        def card_words = @card ? Triggers.filter_words(@card) : "card"
      end
    end
  end
end
