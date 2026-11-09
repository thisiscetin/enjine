# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # "Whenever you gain life" (CR 119.9): once per life gain event; gaining 0 life isn't one.
      class GainsLife < PlayerTrigger
        primitive :trigger, :gains_life,
                  description: "A player gains life (once per life gain event; lifelink combat damage is one event " \
                               "per source). `controller`: you (default) | opponent | any.",
                  rules: %w[119.9 120.3f],
                  params: { "controller" => PLAYERS.join(" | ") },
                  example: { "gains_life" => { "controller" => "you" } }

        def event_class = Events::LifeChanged
        def match?(engine, event, source) = event.gain.positive? && player_ok?(engine, event.player, source)
        def to_s = "Whenever #{who} gain#{"s" unless @controller == "you"} life"
      end

      # "Whenever an opponent loses life".
      class LosesLife < PlayerTrigger
        primitive :trigger, :loses_life,
                  description: "A player loses life (damage to a player is life loss, CR 120.3a). " \
                               "`controller`: you (default) | opponent | any.",
                  rules: %w[119.3 120.3a],
                  params: { "controller" => PLAYERS.join(" | ") },
                  example: { "loses_life" => { "controller" => "opponent" } }

        def event_class = Events::LifeChanged
        def match?(engine, event, source) = event.loss.positive? && player_ok?(engine, event.player, source)
        def to_s = "Whenever #{who} lose#{"s" unless @controller == "you"} life"
      end
    end
  end
end
