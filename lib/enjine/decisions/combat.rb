# frozen_string_literal: true

module Enjine
  module Decisions
    DONE = { type: "done" }.freeze

    # CR 508.1: the active player declares attackers one at a time, then `done`.
    class DeclareAttackers < Base
      def self.doc = 'Declare one attacker: `{type: "attack", object: id, target: ref}` (the defending player ' \
                     'or one of their planeswalkers), or `{type: "done"}`.'

      def self.options(engine, _pending)
        targets = engine.attack_targets
        [DONE] + engine.eligible_attackers.flat_map { |id| targets.map { { type: "attack", object: id, target: _1 } } }
      end

      def self.submit(engine, _pending, option)
        option[:type] == "done" ? engine.finish_attackers! : engine.declare_attacker!(option[:object], option[:target])
      end
    end
    register("declare_attackers", DeclareAttackers)

    # CR 509.1: the defending player declares blockers one at a time, then `done`.
    class DeclareBlockers < Base
      def self.doc = 'Declare one blocker: `{type: "block", object: id, attacker: id}`, or `{type: "done"}`.'

      def self.options(engine, _pending)
        attackers = engine.attackers.keys
        [DONE] + engine.eligible_blockers.flat_map { |id| attackers.map { { type: "block", object: id, attacker: _1 } } }
      end

      def self.submit(engine, _pending, option)
        option[:type] == "done" ? engine.turn_based_actions_done! : engine.declare_blocker!(option[:object], option[:attacker])
      end
    end
    register("declare_blockers", DeclareBlockers)

    # CR 510.1c: assign one point of a multiply-blocked attacker's damage to one of its blockers.
    class AssignDamage < Base
      def self.doc = 'Assign one point of combat damage of `attacker`: `{type: "assign", object: blocker_id}`. ' \
                     "`remaining` points are left."

      def self.options(engine, pending)
        engine.blockers_of(pending["attacker"]).map { { type: "assign", object: _1 } }
      end

      def self.submit(engine, pending, option) = engine.assign_damage!(pending["attacker"], option[:object])
    end
    register("assign_damage", AssignDamage)
  end
end
