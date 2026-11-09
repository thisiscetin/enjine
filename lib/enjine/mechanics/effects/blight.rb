# frozen_string_literal: true

require_relative "../costs/choices"

module Enjine
  module Mechanics
    module Costs
      # "Blight N" as a cost (CR 701.68a, 601.2h, 602.2b): put N -1/-1 counters on a creature you control,
      # chosen while casting or activating; the counters are put on it as the spell or ability becomes cast.
      # Without a creature it can't be paid (CR 701.68b, 118.3). The paid entry names the blighted creature
      # (CR 701.68c).
      class Blight < Choosing
        primitive :cost, :blight,
                  description: "Blight `amount`: put that many -1/-1 counters on a creature you control, chosen " \
                               "while casting or activating and put on it as it becomes cast.",
                  rules: %w[701.68a 701.68b 601.2h 602.2b 118.3],
                  params: { "amount" => "integer >= 1" },
                  example: { "blight" => { "amount" => 1 } }

        attr_reader :amount

        def self.keys = %w[amount]
        def self.default_filter = "creature"

        def initialize(filter, count, other, params, errors, path)
          @amount = Mechanics.integer_param(params, :amount, errors, path, min: 1)
          super
        end

        def pay_chosen!(engine, object, entries)
          entries.each do |entry|
            perm = engine.state.objects[entry["object"]]
            engine.add_counters!(perm, "-1/-1", amount, by_player: object.controller) if perm&.zone == :battlefield
          end
        end

        def to_s = "Blight #{amount}"
      end
    end

    module Effects
      # Blight N (CR 701.68a): each referenced player (default: you) puts N -1/-1 counters on a creature they
      # control, of their choice. A player without creatures can't (CR 701.68b), so in a `may` yes is offered
      # only when everyone can. The blighted creatures are the effect's results ("the blighted creature",
      # CR 701.68c).
      class Blight < ChoiceEffect
        primitive :effect, :blight,
                  description: "Each referenced player (default: you) blights `amount`: puts that many -1/-1 " \
                               "counters on a creature they control, chosen as it resolves (one `effect_choice` " \
                               "each, in turn order). The blighted creatures are its results.",
                  rules: %w[701.68a 701.68b 701.68c],
                  params: { "amount" => "amount", "to" => "player selector (default you)" },
                  example: { "blight" => { "amount" => 2 } }

        def self.default_to = "you"

        def possible?(engine, ctx) = players(engine, ctx).all? { !creatures(engine, it).empty? }

        def run(engine, ctx, locals)
          return :done unless locals.key?("queue") || condition.nil? || condition.true?(engine, ctx)

          queue = (locals["queue"] ||= players(engine, ctx))
          locals["n"] ||= amount_for(engine, ctx)
          chosen = answers(locals)
          while chosen.size < queue.size
            index = queue[chosen.size]
            options = creatures(engine, index).map { { "type" => "blight", "object" => it } }
            return ask(engine, locals, index, "Blight #{locals["n"]}: choose a creature you control", options) unless options.empty?

            chosen << { "type" => "none" } # CR 701.68b: nothing to blight
          end
          apply_all(engine, locals, queue, chosen)
        end

        def to_s = "blight #{amount} → #{to}"

        private

        def creatures(engine, index)
          engine.state.battlefield.select { engine.object(it).controller == index && engine.chars(it).creature? }
        end

        # The counters are put on once every player has chosen.
        def apply_all(engine, locals, queue, chosen)
          chosen.each_with_index do |answer, i|
            next unless answer["type"] == "blight" && locals["n"].positive?

            engine.add_counters!(engine.object(answer["object"]), "-1/-1", locals["n"], by_player: queue[i])
            engine.record_result!(answer["object"])
          end
          :done
        end
      end
    end
  end
end
