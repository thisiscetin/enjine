# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # "Whenever ~ becomes untapped" (CR 603.2e): not a permanent that enters untapped.
      class BecomesUntapped < Trigger
        primitive :trigger, :becomes_untapped,
                  description: "The subject becomes untapped (in the untap step or by an effect). A permanent that " \
                               "enters untapped doesn't become untapped.",
                  rules: %w[603.2e 701.26b],
                  params: { "subject" => "\"self\" (default), \"attached\" or {\"each\": filter, ...}" },
                  example: { "becomes_untapped" => { "subject" => "attached" } }

        def event_class = Events::Untapped

        def match?(engine, event, source)
          obj = engine.state.objects[event.object] or return false
          @subject.match?(engine, event.object, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        def to_s = "Whenever #{@subject} becomes untapped"
      end

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
    end
  end
end
