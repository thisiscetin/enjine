# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # "Whenever you commit a crime" / "whenever an opponent commits a crime" (CR 700.13): once per spell cast,
      # ability activated or triggered ability put on the stack that targets an opponent, something an opponent
      # controls or a card in an opponent's graveyard (Engine::Crimes). "That spell or ability" is
      # {"triggering": "object"}; the criminal is {"triggering": "player"}.
      class CommitsCrime < PlayerTrigger
        primitive :trigger, :commits_crime,
                  description: "A player commits a crime: they cast a spell, activate an ability or put a triggered " \
                               "ability on the stack that targets an opponent, a permanent, spell or ability an " \
                               "opponent controls, or a card in an opponent's graveyard (once per spell or ability). " \
                               "`controller`: you (default) | opponent | any. {\"triggering\": \"object\"} is that " \
                               "spell or ability. Amount `{\"crimes_this_turn\": player}` counts them.",
                  rules: %w[700.13 603.2],
                  params: { "controller" => "you | opponent | any" },
                  example: { "commits_crime" => {} }

        def event_class = Events::CrimeCommitted
        def match?(engine, event, source) = player_ok?(engine, event.player, source)

        def to_s = "Whenever #{who} commit#{"s" unless @controller == "you"} a crime"
      end
    end
  end
end
