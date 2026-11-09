# frozen_string_literal: true

require_relative "evergreen"

module Enjine
  module Mechanics
    module Keywords
      # Rules modifications that work like a keyword: a flag on the object's characteristics that the
      # rules code checks, printed, handed out by a static ability (often a conditional one) or gained until end of
      # turn.
      {
        attacks_despite_defender: ["Defender doesn't stop this creature from attacking.", %w[702.3b 508.1c]],
        doesnt_untap: ["This permanent doesn't untap during its controller's untap step.", %w[502.3]],
        assigns_damage_by_toughness: ["If this creature's toughness is greater than its power, it assigns combat damage " \
                                      "equal to its toughness rather than its power.", %w[510.1a]],
        keeps_damage: ["Damage isn't removed from this permanent during cleanup steps (remove_damage still removes it).",
                       %w[514.2 120.6]]
      }.each { |name, (description, rules)| Evergreen.define(name, description, rules) }

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
                              "finish while it could still attack.", %w[508.1d]],
        must_be_blocked: ["Requirement: this attacking creature must be blocked if able. Declaring blockers can't " \
                          "finish while it is unblocked and a creature that could block it blocks nothing.", %w[509.1c]]
      }.each { |name, (description, rules)| Evergreen.define(name, description, rules) }

      # "This spell can't be countered." (CR 101.2: a "can't" wins over an effect that would counter it.)
      Evergreen.define(:cant_be_countered, "This spell can't be countered: counter effects leave it on the stack.",
                       %w[701.6a 101.2])
    end
  end
end
