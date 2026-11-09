# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # "Whenever you cast a spell" (optionally only matching spells); "when you cast this spell" (`self`).
      # It triggers once the spell becomes cast (CR 601.2i), so a cast that is cancelled never triggers it.
      class Cast < Trigger
        include ChosenMatch

        primitive :trigger, :cast,
                  description: "A player casts a spell. `controller`: you (default) | opponent | any; `spell`: creature | " \
                               "noncreature | instant_or_sorcery, or any spell filter, e.g. {\"spell\": {\"subtypes\": " \
                               "[\"saga\"]}} or {\"one_of\": [...]} for \"creature or Spacecraft spell\"; `name` / " \
                               "`mana_value`: \"chosen\" (the source's as-it-entered choice); `self: true`: \"when you cast " \
                               "this spell\" (it functions on the stack). `targets`: only a spell that targets something " \
                               "matching this filter (\"self\": this permanent), e.g. {\"creature\": {\"controller\": " \
                               "\"you\"}}. `from` / `not_from`: only a spell cast from (not from) that zone: hand | " \
                               "graveyard | exile | library | outside. `single_target: true`: only a spell with exactly " \
                               "one target.",
                  rules: %w[603.2 601.2i 113.6 202.3e 201.4 607.2 115.1 601.2a 601.2c],
                  params: { "controller" => "you | opponent | any", "spell" => "creature | noncreature | instant_or_sorcery | filter",
                            "name" => "\"chosen\"", "mana_value" => "\"chosen\"", "self" => "true",
                            "targets" => "\"self\" or a target filter", "from" => "zone", "not_from" => "zone",
                            "single_target" => "true" },
                  example: { "cast" => { "controller" => "you", "spell" => "noncreature" } }

        SPELLS = %w[creature noncreature instant_or_sorcery].freeze

        def self.keys = %w[controller spell name mana_value self targets from not_from single_target]
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
          setup_targets(params, errors, path)
          @single = params["single_target"] == true
          errors << "#{path}.single_target: must be true" unless params["single_target"].nil? || @single
          @zones = CastFrom.build(params, errors, path)
        end

        def match?(engine, event, source)
          return event.object == source["id"] if @self

          caster = engine.names.index(event.player)
          return false unless @controller == "any" || (@controller == "you") == (caster == source["controller"])
          return false unless spell_ok?(engine, event, caster, source) && targets_ok?(engine, event, source)
          return false unless @zones.match?((spell = engine.state.objects[event.object]) && engine.cast_origin(spell))

          chosen_ok?(engine, source, event.card, engine.state.objects[event.object]&.x)
        end

        # "Those creatures" ({"triggering": "targets"}): the spell's targets that matched `targets` (all of them
        # without it), as they were chosen (CR 601.2c).
        def occurrences(engine, event, source)
          return [] unless match?(engine, event, source)

          [Triggers.event_facts(engine, event).merge("targets" => matched_targets(engine, event, source))]
        end

        # "A spell that targets this creature / a creature you control" (CR 115.1, 601.2c): one of the
        # targets chosen as it was cast matches, relative to the trigger's source.
        def setup_targets(params, errors, path)
          raw = params["targets"]
          @targets = raw == "self" ? :self : raw && Mechanics.build_entry(:filter, raw, errors, "#{path}.targets")
        end

        def targets_ok?(engine, event, source)
          return false if @single && Array(event.targets).flatten.compact.uniq.size != 1 # "with a single target"

          !@targets || matched_targets(engine, event, source).any?
        end

        def matched_targets(engine, event, source)
          Array(event.targets).flatten.compact.uniq.select do |ref|
            next true unless @targets

            @targets == :self ? ref == source["id"] : @targets.match_for?(engine, ref, source["controller"], source["id"])
          end
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
            "#{@zones}#{target_words}#{chosen_words}"
        end

        def target_words
          return "" unless @targets || @single

          return " with a single target" if @single && !@targets

          " that targets #{@targets == :self ? "this" : Triggers.filter_words(@targets)}"
        end
      end

      # "Whenever a creature you control becomes the target of a spell or ability an opponent controls"
      # (CR 115.1, 603.2): checked once the spell is cast, the ability activated or the triggered ability
      # put on the stack with its targets, so a cancelled cast never triggers it. Each matching object
      # that became a target is one occurrence.
      class BecomesTarget < Trigger
        BY = %w[opponent you any].freeze
        EVENTS = %i[SpellCast AbilityActivated TriggerPutOnStack].freeze

        primitive :trigger, :becomes_target,
                  description: "The subject becomes the target of a spell or ability (controlled by `by`: opponent | you | " \
                               "any (default), relative to the source's controller). One trigger per matching object " \
                               "targeted.",
                  rules: %w[115.1 601.2c 603.2 603.2c],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}", "by" => BY.join(" | ") },
                  example: { "becomes_target" => { "subject" => { "each" => "creature", "controller" => "you" },
                                                   "by" => "opponent" } }

        def self.keys = %w[subject by]
        def watches?(event) = EVENTS.any? { event.is_a?(Events.const_get(it)) }

        def setup(params, errors, path)
          @by = params.fetch("by", "any")
          errors << "#{path}.by: must be one of #{BY.join(", ")}" unless BY.include?(@by)
        end

        def occurrences(engine, event, source)
          player = engine.names.index(event.player)
          return [] unless @by == "any" || (@by == "you") == (player == source["controller"])

          Array(event.targets).uniq.filter_map do |ref|
            obj = engine.state.objects[ref]
            next unless obj && obj.zone == :battlefield
            next unless @subject.match?(engine, ref, obj.controller, obj.card, source, types: engine.chars(obj).types)

            { "object" => ref, "player" => player, "card" => obj.card }
          end
        end

        def match?(engine, event, source) = !occurrences(engine, event, source).empty?

        def to_s
          "Whenever #{@subject} becomes the target of a spell or ability#{{ "you" => " you control",
                                                                            "opponent" => " an opponent controls" }[@by]}"
        end
      end

      # "Whenever a player activates an ability of a source with ..." (CR 602.2, 605.1): non-mana activated
      # and loyalty abilities only (mana abilities aren't activated through the stack and aren't watched).
      class ActivatesAbility < PlayerTrigger
        include ChosenMatch

        primitive :trigger, :activates_ability,
                  description: "A player (`controller`: you (default) | opponent | any) activates an ability that isn't a " \
                               "mana ability. `source`: optional filter on the source's card; `name: \"chosen\"`: only a " \
                               "source with the name chosen as this permanent entered. `exhaust: true`: only an exhaust " \
                               "ability (\"whenever you activate an exhaust ability\", CR 702.177). `boast: true`: only a " \
                               "boast ability (\"whenever a creature you control boasts\", CR 702.142b).",
                  rules: %w[602.2 605.1a 603.2 201.4 702.177a 702.142b],
                  params: { "controller" => PLAYERS.join(" | "), "source" => "card filter", "name" => "\"chosen\"",
                            "exhaust" => "true: only exhaust abilities", "boast" => "true: only boast abilities" },
                  example: { "activates_ability" => { "controller" => "opponent" } }

        def self.keys = %w[controller source name exhaust boast]
        KINDS = { "exhaust" => :exhaust?, "boast" => :boast? }.freeze
        def event_class = Events::AbilityActivated

        def setup(params, errors, path)
          super
          @source = params["source"] && Mechanics.build_entry(:filter, params["source"], errors, "#{path}.source")
          setup_chosen(params, errors, path)
          @kinds = KINDS.select { |key, _| params[key] == true }.values
          KINDS.each_key { errors << "#{path}.#{it}: must be true or false" unless [nil, true, false].include?(params[it]) }
        end

        def match?(engine, event, source)
          return false unless player_ok?(engine, event.player, source) && chosen_ok?(engine, source, event.card)
          return false unless @kinds.all? { kind?(engine, event, it) }
          return true unless @source

          defn = engine.catalog.fetch(event.card)
          @source.matches_facts?(Filters::Facts.new(chars: defn.printed_characteristics, counters: {}, token: defn.token?))
        end

        def to_s
          kinds = @kinds.map { "#{it.to_s.delete("?")} " }.join
          "Whenever #{who} activate#{"s" unless @controller == "you"} an #{kinds}ability#{chosen_words}"
        end

        private

        # The activated ability on the stack is an exhaust ability (CR 702.177a) / a boast ability (CR 702.142b).
        def kind?(engine, event, flag)
          obj = engine.state.objects[event.object]
          ability = obj && engine.stack_ability(obj)
          ability.respond_to?(flag) && ability.public_send(flag)
        end
      end
    end
  end
end
