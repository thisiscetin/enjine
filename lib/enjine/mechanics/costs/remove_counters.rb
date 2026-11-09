# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # "Remove N counters from among [permanents] you control" (CR 122.8 / 118.3): each choice is one
      # counter on one permanent; they are removed as the ability becomes cast.
      class RemoveCounters < Choosing
        primitive :cost, :remove_counters,
                  description: "Remove `count` counters (of kind `counter`, or any kind) from among permanents you " \
                               "control matching `filter` (default creature), one counter per choice. Removed as " \
                               "it becomes cast.",
                  rules: %w[602.2b 601.2h 118.3 122.1],
                  params: { "count" => "integer", "filter" => "filter (default creature)", "counter" => "counter name (optional)" },
                  example: { "remove_counters" => { "count" => 3 } }

        def self.keys = %w[filter count counter]
        def self.default_filter = "creature"

        def initialize(filter, count, other, params, errors, path)
          @counter = Mechanics.fetch_param(params, :counter)
          errors << "#{path}.counter: #{Counters.error(@counter)}" if @counter && Counters.error(@counter)
          super
        end

        # Counters still available: [object, kind] once per counter, minus those already chosen.
        def units(engine, object, chosen)
          taken = chosen.map { [it["object"], it["counter"]] }
          matching(engine, object).flat_map do |id|
            engine.object(id).counters.flat_map do |kind, n|
              next [] unless @counter.nil? || kind == @counter

              left = n - taken.count([id, kind])
              left.positive? ? [[id, kind]] * left : []
            end
          end
        end

        def payable?(engine, object) = units(engine, object, []).size >= count
        def choice_options(engine, object, chosen) = units(engine, object, chosen).uniq.map { { object: it[0], counter: it[1] } }
        def choose!(_engine, option) = { "object" => option[:object], "counter" => option[:counter] }

        def pay_chosen!(engine, _object, entries)
          entries.each { engine.remove_counters!(engine.object(it["object"]), it["counter"], 1) }
        end

        def to_s = "Remove #{count} #{"#{@counter} " if @counter}counters from among #{what}s you control"
      end
    end
  end
end
