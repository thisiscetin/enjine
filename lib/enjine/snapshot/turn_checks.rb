# frozen_string_literal: true

module Enjine
  # Snapshot validation of the turn, the pending decision, delayed triggers and extra turns.
  module Snapshot
    module_function

    # CR 603.7: each delayed triggered ability names a card in the catalog and one of its delayed abilities.
    def validate_delayed_triggers(data, catalog, errors)
      list = data.fetch("delayed_triggers", [])
      return errors << "delayed_triggers: must be a list" unless list.is_a?(Array)

      list.each_with_index do |entry, i|
        path = "delayed_triggers[#{i}]"
        next errors << "#{path}: must be an object" unless entry.is_a?(Hash)

        errors << "#{path}.controller: must be 0 or 1" unless [0, 1].include?(entry["controller"])
        errors << "#{path}.results: must be a list" unless entry.fetch("results", []).is_a?(Array)
        card = catalog.include?(entry["card"].to_s) && catalog.fetch(entry["card"])
        next if card && card.ability(entry["ability"].to_s).respond_to?(:trigger)

        errors << "#{path}: #{entry["card"].inspect} has no delayed ability #{entry["ability"].inspect}"
      end
    end

    # CR 500.7: extra turns still to be taken (the last one first) and the players who began one.
    def validate_extra_turns(data, errors)
      extra = data.fetch("extra_turns", { "queue" => [], "begun" => [] })
      ok = extra.is_a?(Hash) && (extra.keys - ["skip"]).sort == %w[begun queue] && # "skip": turns to skip (CR 614.10)
           extra.values.all? { |list| list.is_a?(Array) && list.all? { [0, 1].include?(it) } }
      errors << "extra_turns: must be {\"queue\": [player index...], \"begun\": [...], \"skip\": [...] (optional)}" unless ok
    end

    def validate_turn(data, errors)
      errors << "step_state: must be one of #{State::STEP_STATES.join(", ")}" unless State::STEP_STATES.include?(data["step_state"])
      step = data["step"]
      errors << "step: unknown step #{step.inspect}" unless step.nil? || Steps::BY_NAME.key?(step.to_sym)
      if step
        errors << "active: must be 0 or 1" unless [0, 1].include?(data["active"])
        errors << "turn: must be a positive integer" unless data["turn"].is_a?(Integer) && data["turn"].positive?
        errors << "starting_player: must be 0 or 1" unless [0, 1].include?(data["starting_player"])
      end
      validate_pending(data, errors)
    end

    def validate_pending(data, errors)
      pending = data["pending"]
      if data["result"]
        errors << "pending: must be empty once the game is over" if pending
        return
      end
      return errors << "pending: a game in progress needs a pending decision" unless pending.is_a?(Hash)

      errors << "pending.kind: unknown decision #{pending["kind"].inspect}" unless Decisions::KINDS.key?(pending["kind"])
      errors << "pending.player: must be 0 or 1" unless [0, 1].include?(pending["player"])
      return unless pending["kind"] == "priority" && pending["player"] != data["priority"]

      errors << "pending: priority decision for player #{pending["player"]} but priority is #{data["priority"].inspect}"
    end
  end
end
