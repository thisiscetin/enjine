# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Sacrifice permanents (CR 701.21): "sacrifice it at the beginning of the next end step".
      class Sacrifice < Effect
        primitive :effect, :sacrifice,
                  description: "The controller sacrifices each referenced permanent they control (it goes to its " \
                               "owner's graveyard; it isn't destroyed, so indestructible doesn't stop it).",
                  rules: %w[701.21a],
                  params: { "to" => "selector" },
                  example: { "sacrifice" => { "to" => { "result" => 0 } } }

        def self.keys = %w[to if]

        def apply(engine, ctx) = mine(engine, ctx).each { engine.move!(it, :graveyard, reason: "sacrifice") }

        # CR 701.21a: a player can't sacrifice a permanent they don't control.
        def mine(engine, ctx) = objects(engine, ctx).select { engine.can_sacrifice?(engine.object(it), ctx.controller) }
        def possible?(engine, ctx) = !mine(engine, ctx).empty?
      end

      # Edicts and sacrifices of the player's choice: each referenced player chooses a number of permanents
      # they control matching `filter`, in APNAP order (CR 101.4); then all of them are sacrificed at the
      # same time (CR 701.21a).
      class SacrificeChoice < ChoiceEffect
        primitive :effect, :sacrifice_choice,
                  description: "Each referenced player (default: you) sacrifices `count` (default 1; \"any\": any number) " \
                               "permanents they control matching `filter`, chosen by them in turn order starting with " \
                               "the active player; all are sacrificed at once. The `filter`'s `controller` and `other` " \
                               "restrictions are relative to the effect's controller and source.",
                  rules: %w[701.21a 101.4 118.3],
                  params: { "filter" => "a filter, e.g. {\"creature\": {\"token\": false}}", "count" => "integer or \"any\"",
                            "to" => "selector of players" },
                  example: { "sacrifice_choice" => { "filter" => "creature", "to" => "each_opponent" } }

        attr_reader :filter, :count

        def self.keys = %w[filter count to if]
        def self.default_to = "you"

        def setup(params, errors, path)
          raw = Mechanics.fetch_param(params, :filter)
          errors << "#{path}.filter: required" if raw.nil?
          @filter = raw && Mechanics.build_entry(:filter, raw, errors, "#{path}.filter")
          @count = Mechanics.fetch_param(params, :count) || 1
          return if @count == "any" || (@count.is_a?(Integer) && @count.positive?)

          errors << "#{path}.count: must be a positive integer or \"any\""
        end

        def to_s = "#{to} sacrifices #{count == "any" ? "any number of" : count} #{words} of their choice"
        def words = filter.is_a?(Class) ? filter.primitive_name.tr("_", " ") : filter.to_s

        # CR 118.3: as the optional part of a "may", there must be enough permanents to sacrifice.
        def possible?(engine, ctx)
          players(engine, ctx).all? { candidates(engine, ctx, it, []).size >= (count == "any" ? 0 : count) }
        end

        def run(engine, ctx, locals)
          return :done unless locals["asked"] || locals.key?("queue") || condition.nil? || condition.true?(engine, ctx)

          queue = (locals["queue"] ||= apnap(engine, players(engine, ctx)))
          picks = (locals["picks"] ||= [])
          take_answers(locals, picks)
          while (index = queue.first)
            mine = picks.select { it[0] == index }.map { it[1] }
            ask_for = remaining(engine, ctx, locals, index, mine)
            return ask_for if ask_for == :wait

            queue.shift
          end
          picks.each { finish!(engine, it[1]) }
          :done
        end

        # Hooks for Effects::ReturnChoice: what happens to the chosen permanents, who may choose one.
        def finish!(engine, id) = engine.move!(id, :graveyard, reason: "sacrifice")
        def choosable?(engine, obj, index) = engine.can_sacrifice?(obj, index)
        def verb = "sacrifice"

        private

        def apnap(engine, indexes) = engine.turn_order_from_active.select { indexes.include?(it) }

        # Permanents `index` controls that match the filter, not yet chosen.
        def candidates(engine, ctx, index, chosen)
          filter.candidates_for(engine, ctx.controller, ctx.source)
                .select { engine.state.objects.key?(it) && choosable?(engine, engine.object(it), index) } - chosen
        end

        # Asks `index` for their next permanent, or picks automatically when there is no real choice.
        def remaining(engine, ctx, locals, index, mine)
          left = candidates(engine, ctx, index, mine)
          return :next if left.empty? || locals["stopped"] == index || (count != "any" && mine.size >= count)

          if count != "any" && left.size <= count - mine.size
            left.each { locals["picks"] << [index, it] }
            return :next
          end
          choices = left.map { { "type" => verb, "object" => it } }
          choices << { "type" => "done" } if count == "any"
          locals["chooser"] = index
          ask(engine, locals, index, "#{verb.capitalize} #{words}", choices)
        end

        def take_answers(locals, picks)
          (locals["taken"] ||= 0).upto(answers(locals).size - 1) do |i|
            answer = answers(locals)[i]
            answer["type"] == "done" ? locals["stopped"] = locals["chooser"] : picks << [locals["chooser"], answer["object"]]
          end
          locals["taken"] = answers(locals).size
        end
      end
    end
  end
end
