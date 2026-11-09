# frozen_string_literal: true

require_relative "entering_choices"
require_relative "../copy_except"

module Enjine
  module Mechanics
    module Abilities
      # "You may have this creature enter as a copy of any artifact or creature on the battlefield" (CR 707.5,
      # 614.1c, 614.12): as it would enter, its controller chooses a permanent matching `of` (or none); it
      # enters as a copy of it, with the `except` modifications, and with `with_counters: true` also with
      # the same number and kinds of counters the copied permanent has.
      class EnterAsCopy < EnteringChoice
        primitive :ability, :enter_as_copy,
                  description: "As this permanent enters, its controller may choose a permanent on the battlefield " \
                               "matching `of`; it enters as a copy of that permanent (its copiable values, with the " \
                               "`except` modifications) and its enter abilities trigger. `with_counters: true`: it " \
                               "also enters with the counters the copied permanent has. Choosing none: it enters as " \
                               "itself.",
                  rules: %w[707.5 707.9b 614.1c 614.12],
                  params: { "of" => "filter (the permanents it may copy)", "except" => Mechanics::CopyExcept::PARAM,
                            "with_counters" => "boolean" },
                  example: { "enter_as_copy" => { "of" => { "permanent" => { "any_of" => %w[artifact creature] } },
                                                  "except" => { "legendary" => false }, "with_counters" => true } }

        attr_reader :filter, :except, :with_counters

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[of except with_counters], errors, path)
          raw = Mechanics.fetch_param(params, :of)
          filter = raw.nil? ? (errors << "#{path}.of: required") && nil : Mechanics.build_entry(:filter, raw, errors, "#{path}.of")
          except = Mechanics::CopyExcept.build(Mechanics.fetch_param(params, :except), errors, "#{path}.except")
          new(filter, except, Mechanics.flag_param(params, :with_counters, errors, path))
        end

        def initialize(filter, except, with_counters)
          super()
          @filter = filter
          @except = except
          @with_counters = with_counters
          freeze
        end

        def to_s
          what = filter.is_a?(Class) ? filter.primitive_name : filter
          "you may have it enter as a copy of a #{what}#{Mechanics::CopyExcept.to_s(except)}#{" with its counters" if with_counters}"
        end

        def options(engine, controller)
          candidates = filter ? filter.candidates_for(engine, controller, nil) : []
          candidates.select { engine.state.battlefield.include?(it) }.map { { type: "copy", object: it } } +
            [{ type: "dont_copy" }]
        end

        # What it enters with (Engine#enters_from_answer): the copy, and the copied permanent's counters.
        def enters_with(engine, answer)
          obj = answer[:type] == "copy" && engine.state.objects[answer[:object]]
          return nil unless obj && obj.zone == :battlefield

          card, except = engine.copiable_values(obj)
          enters = { "copy" => { "card" => card, "except" => Engine::Copies.merge_except(except, @except) } }
          with_counters && !obj.counters.empty? ? enters.merge("counters" => obj.counters.dup) : enters
        end

        def enters_for(_answer) = nil
      end
    end
  end
end
