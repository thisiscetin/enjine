# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # "Whenever you scry" / "Whenever you surveil" (CR 701.22, 701.25): once the whole action is done
      # (CR 701.25d); scry 0 / surveil 0 isn't one (CR 701.22b, 701.25c). "Whenever you scry or surveil" is
      # `any_of` both.
      class KeywordActionTrigger < PlayerTrigger
        def event_class = Events::KeywordAction
        def match?(engine, event, source) = event.action == self.class.action && player_ok?(engine, event.player, source)
        def to_s = "Whenever #{who} #{self.class.action}#{"s" unless @controller == "you"}"
      end

      # "Whenever you scry".
      class Scries < KeywordActionTrigger
        primitive :trigger, :scries,
                  description: "A player (`controller`: you (default) | opponent | any) scries (not scry 0). Triggers " \
                               "after the scry is complete.",
                  rules: %w[701.22a 701.22b],
                  params: { "controller" => PLAYERS.join(" | ") },
                  example: { "any_of" => [{ "scries" => {} }, { "surveils" => {} }] }

        def self.action = "scry"
      end

      # "Whenever you surveil".
      class Surveils < KeywordActionTrigger
        primitive :trigger, :surveils,
                  description: "A player (`controller`: you (default) | opponent | any) surveils (not surveil 0). " \
                               "Triggers after the surveil is complete.",
                  rules: %w[701.25a 701.25c 701.25d],
                  params: { "controller" => PLAYERS.join(" | ") },
                  example: { "surveils" => { "controller" => "you" } }

        def self.action = "surveil"
      end

      # "Whenever you give a gift" (CR 702.174c): an instant or sorcery spell you control whose gift cost was paid
      # resolves, or the gift triggered ability of a permanent you control (its "enters" trigger with
      # `"if": {"cast_with": "gift"}`) resolves (Engine::Resolution#gift_given!).
      class GivesGift < KeywordActionTrigger
        primitive :trigger, :gives_gift,
                  description: "A player (`controller`: you (default) | opponent | any) gives a gift: an instant or " \
                               "sorcery spell they control whose gift was promised resolves, or the gift triggered " \
                               "ability (an enters trigger under `{\"cast_with\": \"gift\"}`) of a permanent they control " \
                               "resolves.",
                  rules: %w[702.174c 702.174b],
                  params: { "controller" => PLAYERS.join(" | ") },
                  example: { "gives_gift" => {} }

        def self.action = "give_gift"
        def to_s = "Whenever #{who} give#{"s" unless @controller == "you"} a gift"
      end

      # "Whenever you earthbend / waterbend / airbend / firebend" (CR 701.66b, 701.67c, 701.65b, 702.189b): the
      # bending happened (the earthbend delayed trigger was created, a waterbend cost was paid, objects were
      # exiled by an airbend, a firebending ability resolved). "Whenever you waterbend, earthbend, firebend, or
      # airbend" is `any_of` the four.
      {
        earthbends: ["earthbend", %w[701.66b]], waterbends: ["waterbend", %w[701.67c]],
        airbends: ["airbend", %w[701.65b]], firebends: ["firebend", %w[702.189b]]
      }.each do |name, (verb, rules)|
        klass = Class.new(KeywordActionTrigger) { define_singleton_method(:action) { verb } }
        Triggers.const_set(name.to_s.capitalize, klass)
        klass.primitive :trigger, name,
                        description: "A player (`controller`: you (default) | opponent | any) #{verb}s.",
                        rules: rules, params: { "controller" => PLAYERS.join(" | ") }, example: { name.to_s => {} }
      end
    end
  end
end
