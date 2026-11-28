# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # Abilities that work only while their permanent has a designation (Engine::PermanentDesignations): a Case's
      # "Solved — [ability]" (CR 702.169, 720.3c) and an Infinity card's "∞ — [ability]" (CR 702.186). The wrapped
      # ability is built with the designation as its condition, by kind:
      #   static     "as long as it's solved/harnessed" (`if`, CR 702.169b, 702.186b)
      #   triggered  "triggers only if it's solved" (`while`: checked as it triggers, CR 702.169c)
      #   activated  "activate only if it's solved" (`only_if`, CR 702.169d)
      # joined with any condition of its own. The result is the wrapped ability itself.
      module DesignatedAbility
        CONDITION_KEYS = { "static" => "if", "triggered" => "while", "activated" => "only_if" }.freeze

        def self.build(designation, params, errors, path)
          kind, body = Mechanics.split_entry(params)
          key = CONDITION_KEYS[kind.to_s]
          unless key && body.is_a?(Hash)
            errors << "#{path}: must be one static, triggered or activated ability, e.g. {\"static\": {...}}"
            return nil
          end
          mark = { designation => true }
          body = body.transform_keys(&:to_s)
          condition = body.key?(key) ? { "all" => [mark, body[key]] } : mark
          Mechanics.build_entry(:ability, { kind.to_s => body.merge(key => condition) }, errors, path)
        end
      end
    end

    class Condition
      # "If this Case is solved" / "as long as this permanent is harnessed": the source permanent has that
      # designation (CR 720.3b, 701.64b). {"solved": true} / {"harnessed": true}.
      class PermanentDesignation
        def self.build(data, errors, path)
          key = (Engine::PermanentDesignations::NAMES & data.keys).first
          Mechanics.check_keys(data, [key], errors, path)
          errors << "#{path}.#{key}: must be true or false" unless [true, false].include?(data[key])
          new(key, data[key] != false)
        end

        def initialize(designation, value)
          @designation = designation
          @value = value
          freeze
        end

        def true?(engine, ctx)
          obj = engine.state.objects[ctx.source]
          (obj ? engine.designated?(obj, @designation) : false) == @value
        end

        def to_s = "this permanent is #{"not " unless @value}#{@designation}"
      end
    end
  end
end
