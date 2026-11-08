# frozen_string_literal: true

module Enjine
  # The twelve steps of a turn (CR 500.1). Each step object owns its turn-based
  # actions and whether players receive priority during it.
  module Steps
    # Base step: turn-based actions are a no-op and players get priority.
    class Step
      attr_reader :name, :phase

      def initialize(name, phase)
        @name = name
        @phase = phase
        freeze
      end

      def priority? = true
      def skip?(_engine) = false

      # Performs the step's turn-based actions. May set a pending decision; in that
      # case the decision calls engine.turn_based_actions_done! when finished.
      def begin(engine)
        engine.turn_based_actions_done!
      end
    end

    # CR 502: phasing (later), untap the active player's permanents; no priority.
    class Untap < Step
      def priority? = false

      def begin(engine)
        engine.untap_all!(engine.state.active)
        engine.turn_based_actions_done!
      end
    end

    # CR 504: the active player draws, except the starting player on turn 1 (CR 103.8a).
    class Draw < Step
      def begin(engine)
        state = engine.state
        engine.draw!(state.active) unless state.turn == 1 && state.active == state.starting_player
        engine.turn_based_actions_done!
      end
    end

    # CR 508.8: without attackers, declare blockers and combat damage are skipped.
    class CombatStepAfterAttackers < Step
      def skip?(engine) = engine.attackers.empty?
    end

    # CR 514: discard to maximum hand size, then end "until end of turn" effects; no priority.
    class Cleanup < Step
      MAX_HAND_SIZE = 7

      def priority? = false

      def begin(engine)
        excess = engine.active_player.hand.size - MAX_HAND_SIZE
        if excess.positive?
          engine.ask!("kind" => "discard", "player" => engine.state.active, "count" => excess)
        else
          engine.turn_based_actions_done!
        end
      end
    end

    ORDER = [
      Untap.new(:untap, :beginning),
      Step.new(:upkeep, :beginning),
      Draw.new(:draw, :beginning),
      Step.new(:precombat_main, :precombat_main),
      Step.new(:beginning_of_combat, :combat),
      Step.new(:declare_attackers, :combat),
      CombatStepAfterAttackers.new(:declare_blockers, :combat),
      CombatStepAfterAttackers.new(:combat_damage, :combat),
      Step.new(:end_of_combat, :combat),
      Step.new(:postcombat_main, :postcombat_main),
      Step.new(:end, :ending),
      Cleanup.new(:cleanup, :ending)
    ].freeze
    BY_NAME = ORDER.to_h { [it.name, it] }.freeze
    MAIN_PHASE_STEPS = %i[precombat_main postcombat_main].freeze

    def self.fetch(name) = BY_NAME.fetch(name.to_sym)
    def self.index(name) = ORDER.index(fetch(name))
  end
end
