# frozen_string_literal: true

module Enjine
  module Mechanics
    module Keywords
      # Evergreen keyword abilities. A keyword is a flag on the object's characteristics;
      # the rules code asks chars(obj).keyword?(:name) at the point the rule applies.
      class Evergreen < Primitive
        def self.define(name, description, rules)
          klass = Class.new(self)
          Keywords.const_set(name.to_s.split("_").map(&:capitalize).join, klass)
          klass.primitive :keyword, name, description: description, rules: rules, example: { "keywords" => [name.to_s.tr("_", " ")] }
        end
      end

      {
        flying: ["Can't be blocked except by creatures with flying or reach.", %w[702.9b]],
        reach: ["Can block creatures with flying.", %w[702.17b]],
        vigilance: ["Attacking doesn't cause this creature to tap.", %w[702.20b]],
        menace: ["Can't be blocked except by two or more creatures.", %w[702.111b]],
        defender: ["Can't attack.", %w[702.3b]],
        trample: ["Excess combat damage beyond lethal damage to its blockers can be assigned to the player or " \
                  "planeswalker it's attacking.", %w[702.19b 702.19e]],
        first_strike: ["Deals combat damage in a first combat damage step, before creatures without first strike.",
                       %w[702.7b 510.4]],
        double_strike: ["Deals combat damage in both the first-strike and the regular combat damage step.",
                        %w[702.4b 510.4]],
        deathtouch: ["Any damage it deals to a creature is enough to destroy it; 1 damage counts as lethal when " \
                     "assigning combat damage.", %w[702.2b 702.2c 704.5h]],
        lifelink: ["Damage dealt by this source also causes its controller to gain that much life.", %w[702.15b]],
        indestructible: ["Can't be destroyed: lethal damage, deathtouch and \"destroy\" effects don't put it into " \
                         "the graveyard.", %w[702.12b]],
        hexproof: ["Can't be the target of spells or abilities your opponents control.", %w[702.11b]],
        wither: ["Damage this source deals to creatures is dealt as that many -1/-1 counters instead of marked " \
                 "damage, put by its controller.", %w[702.80a 702.80c 702.80d 120.3d]]
      }.each { |name, (description, rules)| Evergreen.define(name, description, rules) }

      # Flash (CR 702.8): may be cast any time its controller could cast an instant.
      class Flash < Primitive
        primitive :keyword, :flash,
                  description: "You may cast this spell any time you could cast an instant.",
                  rules: %w[702.8a], example: { "keywords" => ["flash"] }
      end

      # Haste (CR 702.10): can attack and {T} the turn it comes under your control.
      class Haste < Primitive
        primitive :keyword, :haste,
                  description: "This creature can attack and use {T} abilities even if it hasn't been under your " \
                               "control continuously since your most recent turn began.",
                  rules: %w[702.10a 302.6], example: { "keywords" => ["haste"] }
      end
    end
  end
end
