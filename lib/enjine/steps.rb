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
      def finish(_engine) = nil

      # Performs the step's turn-based actions. May set a pending decision; in that
      # case the decision calls engine.turn_based_actions_done! when finished.
      def begin(engine)
        engine.turn_based_actions_done!
      end
    end

    # CR 502: phasing (502.1), then the active player's permanents untap (502.3), some by their choice
    # (Engine::TurnStructure); no priority (502.4).
    class Untap < Step
      def priority? = false
      def begin(engine) = engine.begin_untap_step!
    end

    # CR 504: the active player draws. In a two-player game the starting player skips the whole
    # draw step of their first turn (CR 103.8a): no draw, no priority, no "draw step" triggers.
    class Draw < Step
      def skip?(engine) = engine.state.then { it.turn == 1 && it.active == it.starting_player }

      def begin(engine)
        engine.draw!(engine.state.active)
        engine.turn_based_actions_done!
      end
    end

    # CR 505.4 / 715.3c: as the precombat main phase begins, the active player puts a
    # lore counter on each Saga they control with one or more chapter abilities.
    class PrecombatMain < Step
      def begin(engine)
        engine.add_lore_counters!(engine.state.active)
        engine.turn_based_actions_done!
      end
    end

    # CR 508.8: if no creatures were declared as attackers, declare blockers and combat damage are skipped.
    class CombatStepAfterAttackers < Step
      def skip?(engine) = engine.state.attacks_declared.zero?
    end

    # CR 508.1: the active player declares attackers (a turn-based action).
    class DeclareAttackers < Step
      def begin(engine) = engine.begin_declare_attackers!
    end

    # CR 509.1: the defending player declares blockers.
    class DeclareBlockers < CombatStepAfterAttackers
      def begin(engine) = engine.begin_declare_blockers!
    end

    # CR 510: combat damage is assigned and dealt simultaneously.
    class CombatDamage < CombatStepAfterAttackers
      def begin(engine) = engine.begin_combat_damage!
    end

    # CR 514: discard to maximum hand size, then end "until end of turn" effects; no priority.
    class Cleanup < Step
      def priority? = false

      # CR 514.2: remove marked damage and end "until end of turn" effects (control returns first).
      def finish(engine)
        engine.revert_temporary_control!
        engine.cleanup_turn!
      end

      # CR 514.1 / 402.2: discard down to the maximum hand size, if the player has one.
      def begin(engine)
        max = engine.max_hand_size(engine.state.active)
        excess = max ? engine.active_player.hand.size - max : 0
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
      PrecombatMain.new(:precombat_main, :precombat_main),
      Step.new(:beginning_of_combat, :combat),
      DeclareAttackers.new(:declare_attackers, :combat),
      DeclareBlockers.new(:declare_blockers, :combat),
      CombatDamage.new(:combat_damage, :combat),
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
