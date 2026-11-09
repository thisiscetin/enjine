# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "Distribute N +1/+1 counters among one or two target creatures" (CR 601.2d): the division was
      # announced while casting (the spell ability's `divide`); each target that is still legal gets its
      # share (CR 608.2b).
      class DistributeCounters < Effect
        primitive :effect, :distribute_counters,
                  description: "Put on each legal target the number of `counter` counters assigned to it as the spell " \
                               "or ability was cast (its `divide` amount, at least one per target).",
                  rules: %w[601.2d 608.2b 122.1],
                  params: { "counter" => "counter name" },
                  example: { "distribute_counters" => { "counter" => "+1/+1" } }

        attr_reader :counter

        def self.keys = %w[counter if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @counter = Counters.normalize(Mechanics.fetch_param(params, :counter))
          message = Counters.error(@counter)
          errors << "#{path}.counter: #{message}" if message
        end

        def to_s = "distribute #{counter} counters among the targets"

        def apply(engine, ctx)
          engine.object(ctx.object).memory.fetch("division", {}).each do |ref, n|
            next unless ctx.targets.flatten.include?(ref) # still a legal target (CR 608.2b)

            engine.add_counters!(engine.object(ref), counter, n, by_player: ctx.controller)
          end
        end
      end
    end
  end
end
