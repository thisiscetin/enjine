# frozen_string_literal: true

require_relative "evergreen"

module Enjine
  module Mechanics
    module Keywords
      # Combat restrictions and requirements (CR 508.1c-d, 509.1b). They aren't keyword abilities
      # in the CR (702), but they work exactly like one: a flag on the object's current
      # characteristics that combat code checks. So a card prints them (`"keywords": ["cant_block"]`),
      # a static ability hands them out ("Creatures your opponents control can't block") and the
      # `grant` effect gives them until end of turn ("Target creature can't be blocked this turn").
      {
        cant_attack: ["Restriction: this creature can't attack.", %w[508.1c]],
        cant_block: ["Restriction: this creature can't block.", %w[509.1b]],
        cant_be_blocked: ["Restriction: this creature can't be blocked.", %w[509.1b]],
        cant_attack_alone: ["Restriction: this creature can't attack unless another creature attacks too. It is " \
                            "offered as an attacker only while another creature attacks or could still be declared, " \
                            "and declaring attackers can't finish while it attacks alone.", %w[506.5 508.1c]],
        attacks_each_combat: ["Requirement: this creature attacks each combat if able. Declaring attackers can't " \
                              "finish while it could still attack.", %w[508.1d]]
      }.each { |name, (description, rules)| Evergreen.define(name, description, rules) }
    end

    module Abilities
      # Base for restriction abilities a permanent has on itself (CR 509.1b, 115.4): no stack, no effects.
      class Restriction < Primitive
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
      end

      # "This creature can't be blocked by creatures with power 2 or less" / "... by artifact creatures".
      class CantBeBlockedBy < Restriction
        primitive :ability, :cant_be_blocked_by,
                  description: "This creature can't be blocked by creatures matching `filter` (checked as blockers " \
                               "are declared, with their current characteristics).",
                  rules: %w[509.1b 509.1a],
                  params: { "filter" => "a creature filter, e.g. {\"creature\": {\"power\": {\"at_most\": 2}}}" },
                  example: { "cant_be_blocked_by" => { "filter" => { "creature" => { "power" => { "at_most" => 2 } } } } }

        attr_reader :filter

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[filter], errors, path)
          raw = Mechanics.fetch_param(params, :filter)
          errors << "#{path}.filter: required" if raw.nil?
          filter = raw && Mechanics.build_entry(:filter, raw, errors, "#{path}.filter")
          new(filter)
        end

        def initialize(filter)
          super()
          @filter = filter
          freeze
        end

        def kind = :cant_be_blocked_by
        def allowed_types = [:creature]
        def to_s = "can't be blocked by #{filter.is_a?(Class) ? filter.primitive_name : filter}"

        # Whether `blocker` may not block this creature (controller-relative filter keys use the blocker's).
        def forbids?(engine, blocker) = filter.match?(engine, blocker, engine.object(blocker).controller)
      end

      # "This creature can't be the target of abilities from artifact sources your opponents control."
      class CantBeTargetedBy < Restriction
        primitive :ability, :cant_be_targeted_by,
                  description: "This permanent can't be the target of abilities its controller's opponents control " \
                               "whose source matches `abilities_from` (a card spec, e.g. {\"types\": [\"artifact\"]}).",
                  rules: %w[115.4 113.7 702.11d],
                  params: { "abilities_from" => "card spec of the ability's source" },
                  example: { "cant_be_targeted_by" => { "abilities_from" => { "types" => ["artifact"] } } }

        attr_reader :spec

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[abilities_from], errors, path)
          raw = Mechanics.fetch_param(params, :abilities_from)
          errors << "#{path}.abilities_from: required" if raw.nil?
          new(CardSpec.build(raw, errors, "#{path}.abilities_from"))
        end

        def initialize(spec)
          super()
          @spec = spec
          freeze
        end

        def kind = :cant_be_targeted_by
        def to_s = "can't be the target of abilities from #{spec.to_s.delete_suffix(" card")} sources opponents control"

        # Whether an ability whose source is `source` (a card object) may not target this permanent.
        def forbids?(engine, source) = spec.match?(engine, source)
      end
    end
  end
end
