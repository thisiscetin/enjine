# frozen_string_literal: true

require_relative "triggers"
require_relative "events"

module Enjine
  module Mechanics
    module Triggers
      # "Whenever ~ becomes tapped" (CR 603.2e): only a permanent already on the battlefield changing from
      # untapped to tapped; entering tapped isn't becoming tapped.
      class BecomesTapped < Trigger
        primitive :trigger, :becomes_tapped,
                  description: "The subject becomes tapped (for any reason: a cost, attacking, an effect). A " \
                               "permanent that enters tapped doesn't become tapped.",
                  rules: %w[603.2e 701.26a],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}" },
                  example: { "becomes_tapped" => { "subject" => "self" } }

        def event_class = Events::Tapped

        def match?(engine, event, source)
          obj = engine.state.objects[event.object] or return false
          @subject.match?(engine, event.object, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        def to_s = "Whenever #{@subject} becomes tapped"
      end

      # "Whenever one or more [kind] counters are put on ~" (CR 122.6): counters put on a permanent, including
      # the counters it enters with. Once per counter-placing event.
      class CountersPlaced < Trigger
        primitive :trigger, :counters_placed,
                  description: "One or more counters (only `counter`, if given) are put on the subject, including the " \
                               "counters it enters the battlefield with. Triggers once per event, however many counters.",
                  rules: %w[122.6 603.2 603.2c],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}", "counter" => "counter name",
                            "first_time_this_turn" => "true: only the first time each turn such counters are put on " \
                                                      "that permanent (an earlier placement counts even if nothing " \
                                                      "could trigger then)" },
                  example: { "counters_placed" => { "counter" => "+1/+1" } }

        def self.keys = %w[subject counter first_time_this_turn]
        def watches?(event) = event.is_a?(Events::CountersChanged) || event.is_a?(Events::ZoneChanged)

        def setup(params, errors, path)
          @counter = params["counter"] && Counters.normalize(params["counter"])
          message = @counter && Counters.error(@counter)
          errors << "#{path}.counter: #{message}" if message
          @first_time = params["first_time_this_turn"]
          errors << "#{path}.first_time_this_turn: must be true or false" unless [nil, true, false].include?(@first_time)
        end

        def occurrences(engine, event, source)
          id, amount = placed(engine, event)
          return [] unless amount&.positive?
          return [] if @first_time && engine.counter_placements_this_turn(id, @counter) != 1

          obj = engine.object(id)
          return [] unless @subject.match?(engine, id, obj.controller, obj.card, source, types: engine.chars(obj).types)

          [{ "object" => id, "player" => obj.controller, "amount" => amount, "card" => obj.card }]
        end

        def match?(engine, event, source) = !occurrences(engine, event, source).empty?

        def to_s
          first = " for the first time each turn" if @first_time
          "Whenever one or more #{"#{@counter} " if @counter}counters are put on #{@subject}#{first}"
        end

        private

        # [object id, how many matching counters were put on it] for this event, or nil.
        def placed(engine, event)
          if event.is_a?(Events::CountersChanged)
            return nil if @counter && event.counter != @counter

            [event.object, event.to - event.from]
          elsif event.to == "battlefield" && (obj = engine.state.objects[event.new_id])
            counts = @counter ? [obj.counters.fetch(@counter, 0)] : obj.counters.values
            [obj.id, counts.sum]
          end
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

      # "Whenever a card leaves your graveyard" / "whenever one or more cards leave your graveyard" (`batched`).
      # Looks back in time (CR 603.10a): the card is matched as it was in the graveyard.
      class LeavesGraveyard < PlayerTrigger
        primitive :trigger, :leaves_graveyard,
                  description: "A card leaves a graveyard (whose: `controller` you (default) | opponent | any). Optional " \
                               "`card` filter on its card types. `batched: true` is \"one or more cards leave\": once per " \
                               "event that moves cards (one effect, cost or action), however many cards.",
                  rules: %w[603.10a 603.2c 404.1],
                  params: { "controller" => PLAYERS.join(" | "), "card" => "card type filter, e.g. \"creature\"",
                            "batched" => "true | false" },
                  example: { "leaves_graveyard" => { "controller" => "you", "batched" => true } }

        def self.keys = %w[controller card batched]
        def event_class = Events::ZoneChanged
        def batched? = @batched

        def setup(params, errors, path)
          super
          @batched = params.fetch("batched", false)
          errors << "#{path}.batched: must be true or false" unless [true, false].include?(@batched)
          @card = params["card"] && Mechanics.build_entry(:filter, params["card"], errors, "#{path}.card")
        end

        def match?(engine, event, source)
          return false unless event.from == "graveyard" && player_ok?(engine, event.owner, source)
          return true unless @card

          defn = engine.catalog.fetch(event.card)
          @card.matches_facts?(Filters::Facts.new(chars: defn.printed_characteristics, counters: {}, token: defn.token?))
        end

        def to_s
          what = @card ? Triggers.filter_words(@card) : "card"
          whose = { "you" => "your", "opponent" => "an opponent's" }.fetch(@controller, "a")
          "Whenever #{@batched ? "one or more #{what}s leave" : "a #{what} leaves"} #{whose} graveyard"
        end
      end

      # "Whenever a player activates an ability of a source with ..." (CR 602.2, 605.1): non-mana activated
      # and loyalty abilities only (mana abilities aren't activated through the stack and aren't watched).
      class ActivatesAbility < PlayerTrigger
        include ChosenMatch

        primitive :trigger, :activates_ability,
                  description: "A player (`controller`: you (default) | opponent | any) activates an ability that isn't a " \
                               "mana ability. `source`: optional filter on the source's card; `name: \"chosen\"`: only a " \
                               "source with the name chosen as this permanent entered.",
                  rules: %w[602.2 605.1a 603.2 201.4],
                  params: { "controller" => PLAYERS.join(" | "), "source" => "card filter", "name" => "\"chosen\"" },
                  example: { "activates_ability" => { "controller" => "opponent" } }

        def self.keys = %w[controller source name]
        def event_class = Events::AbilityActivated

        def setup(params, errors, path)
          super
          @source = params["source"] && Mechanics.build_entry(:filter, params["source"], errors, "#{path}.source")
          setup_chosen(params, errors, path)
        end

        def match?(engine, event, source)
          return false unless player_ok?(engine, event.player, source) && chosen_ok?(engine, source, event.card)
          return true unless @source

          defn = engine.catalog.fetch(event.card)
          @source.matches_facts?(Filters::Facts.new(chars: defn.printed_characteristics, counters: {}, token: defn.token?))
        end

        def to_s = "Whenever #{who} activate#{"s" unless @controller == "you"} an ability#{chosen_words}"
      end
    end
  end
end
