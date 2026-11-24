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
      # untapped to tapped; entering tapped isn't becoming tapped. `for: "teamwork"`: "becomes tapped to pay a
      # teamwork cost" (CR 702.194a), known once the spell is cast.
      class BecomesTapped < Trigger
        COSTS = %w[teamwork].freeze

        primitive :trigger, :becomes_tapped,
                  description: "The subject becomes tapped (for any reason: a cost, attacking, an effect). A " \
                               "permanent that enters tapped doesn't become tapped. `for: \"teamwork\"`: only when " \
                               "it's tapped to pay a teamwork cost (it triggers once the spell is cast).",
                  rules: %w[603.2e 701.26a 702.194a],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}", "for" => COSTS.join(" | ") },
                  example: { "becomes_tapped" => { "subject" => "self" } }

        def self.keys = %w[subject for]
        def event_class = @for ? Events::TappedForCost : Events::Tapped

        def setup(params, errors, path)
          @for = params["for"]
          errors << "#{path}.for: must be one of #{COSTS.join(", ")}" unless @for.nil? || COSTS.include?(@for)
        end

        def match?(engine, event, source)
          obj = engine.state.objects[event.object] or return false
          @subject.match?(engine, event.object, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        def to_s = "Whenever #{@subject} becomes tapped#{" to pay a #{@for} cost" if @for}"
      end

      # "Whenever one or more [kind] counters are put on ~" (CR 122.6): counters put on a permanent, including
      # the counters it enters with. Once per counter-placing event. `nth`: "when the fourth plan counter is put
      # on this": only the event that takes the number of those counters from below N to N or more.
      class CountersPlaced < Trigger
        primitive :trigger, :counters_placed,
                  description: "One or more counters (only `counter`, if given) are put on the subject, including the " \
                               "counters it enters the battlefield with. Triggers once per event, however many counters. " \
                               "`nth` (needs `counter`): only when the Nth such counter is put on it (the event that " \
                               "takes it from fewer than N to N or more).",
                  rules: %w[122.6 603.2 603.2c],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}", "counter" => "counter name",
                            "first_time_this_turn" => "true: only the first time each turn such counters are put on " \
                                                      "that permanent (an earlier placement counts even if nothing " \
                                                      "could trigger then)",
                            "by" => "you | opponent: only counters that player puts (\"whenever you put ...\", CR 122.6a; " \
                                    "a permanent's controller puts the counters it enters with)",
                            "nth" => "positive integer" },
                  example: { "counters_placed" => { "counter" => "+1/+1", "by" => "you" } }

        def self.keys = %w[subject counter first_time_this_turn by nth]
        def watches?(event) = event.is_a?(Events::CountersChanged) || event.is_a?(Events::ZoneChanged)

        def setup(params, errors, path)
          @counter = params["counter"] && Counters.parse(params["counter"], errors, "#{path}.counter")
          @first_time = params["first_time_this_turn"]
          errors << "#{path}.first_time_this_turn: must be true or false" unless [nil, true, false].include?(@first_time)
          @by = params["by"]
          errors << "#{path}.by: must be you or opponent" unless [nil, "you", "opponent"].include?(@by)
          @nth = params["nth"]
          errors << "#{path}.nth: must be a positive integer" unless @nth.nil? || (@nth.is_a?(Integer) && @nth.positive?)
          errors << "#{path}.nth: needs a counter" if @nth && @counter.nil?
        end

        def occurrences(engine, event, source)
          id, from, to = placed(engine, event)
          amount = to.to_i - from.to_i
          return [] unless amount.positive? && put_by_ok?(engine, event, id, source)
          return [] if @nth && !(from < @nth && to >= @nth)
          return [] if @first_time && engine.counter_placements_this_turn(id, @counter) != 1

          obj = engine.object(id)
          return [] unless @subject.match?(engine, id, obj.controller, obj.card, source, types: engine.chars(obj).types)

          [{ "object" => id, "player" => obj.controller, "amount" => amount, "card" => obj.card }]
        end

        def match?(engine, event, source) = !occurrences(engine, event, source).empty?

        def to_s
          return "When #{@counter} counter number #{@nth} is put on #{@subject}" if @nth

          first = " for the first time each turn" if @first_time
          return "Whenever one or more #{"#{@counter} " if @counter}counters are put on #{@subject}#{first}" unless @by

          who = @by == "you" ? "you put" : "an opponent puts"
          "Whenever #{who} one or more #{"#{@counter} " if @counter}counters on #{@subject}#{first}"
        end

        private

        # CR 122.6a: who put the counters, relative to the source's controller. Counters a permanent enters with are
        # put by its controller.
        def put_by_ok?(engine, event, id, source)
          return true unless @by

          putter = event.is_a?(Events::CountersChanged) ? engine.names.index(event.by) : engine.object(id).controller
          (@by == "you") == (putter == source["controller"])
        end

        # [object id, how many matching counters it had before, how many after] for this event, or nil.
        def placed(engine, event)
          if event.is_a?(Events::CountersChanged)
            return nil if @counter && event.counter != @counter

            [event.object, event.from, event.to]
          elsif event.to == "battlefield" && (obj = engine.state.objects[event.new_id])
            counts = @counter ? [obj.counters.fetch(@counter, 0)] : obj.counters.values
            [obj.id, 0, counts.sum]
          end
        end
      end
    end
  end
end
