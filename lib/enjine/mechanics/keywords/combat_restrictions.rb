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
        attacks_each_combat: ["Requirement: this creature attacks each combat if able. Declaring attackers can't " \
                              "finish while it could still attack.", %w[508.1d]]
      }.each { |name, (description, rules)| Evergreen.define(name, description, rules) }
    end
  end
end
