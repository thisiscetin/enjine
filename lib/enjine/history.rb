# frozen_string_literal: true

module Enjine
  # One entry of a game's history: the decision a player made (nil for the game's
  # opening) and every event it caused.
  HistoryEntry = Data.define(:seq, :turn, :step, :player, :kind, :option, :events) do
    def self.from_h(hash)
      h = hash.transform_keys(&:to_s)
      new(seq: h["seq"], turn: h["turn"], step: h["step"], player: h["player"], kind: h["kind"],
          option: h["option"]&.transform_keys(&:to_sym), events: h["events"].map { Events.from_h(it) })
    end

    def to_h = for_viewer(:observer)

    # What `viewer` (a player name or :observer) may know about this entry.
    def for_viewer(viewer)
      shown = if option.nil? || viewer == :observer || viewer == player || !Decisions::KINDS.key?(kind)
                option # concessions (and other non-decision entries) are public
              else
                Decisions.fetch(kind).redact(option, false)
              end
      { "seq" => seq, "turn" => turn, "step" => step, "player" => player, "kind" => kind,
        "option" => shown&.transform_keys(&:to_s), "events" => events.map { it.for_viewer(viewer) } }
    end
  end
end
