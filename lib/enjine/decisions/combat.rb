# frozen_string_literal: true

module Enjine
  module Decisions
    DONE = { type: "done" }.freeze

    # CR 508.1: the active player declares attackers one at a time, then `done`.
    class DeclareAttackers < Base
      def self.doc
        'Declare one attacker: `{type: "attack", object: id, target: ref}` (the defending player ' \
          'or one of their planeswalkers), or `{type: "done"}` (withheld while a creature that attacks ' \
          "each combat if able could still attack, CR 508.1d, or while a creature that can't attack alone " \
          'attacks alone, CR 506.5; then `{type: "withdraw", object: id}` undoes an attack).'
      end

      def self.options(engine, _pending)
        targets = engine.attack_targets
        legal = engine.attack_declaration_legal?
        done = engine.unmet_attack_requirements.empty? && legal ? [DONE] : [] # CR 508.1c-d
        withdraw = legal ? [] : engine.attackers.keys.map { { type: "withdraw", object: it } }
        done + engine.attack_candidates.flat_map { |id| targets.map { { type: "attack", object: id, target: it } } } + withdraw
      end

      def self.submit(engine, _pending, option)
        case option[:type]
        when "done" then engine.finish_attackers!
        when "withdraw" then engine.withdraw_attacker!(option[:object])
        else engine.declare_attacker!(option[:object], option[:target])
        end
      end
    end
    register("declare_attackers", DeclareAttackers)

    # CR 509.1: the defending player declares blockers one at a time, then `done`.
    class DeclareBlockers < Base
      def self.doc
        'Declare one blocker: `{type: "block", object: id, attacker: id}`, `{type: "done"}` (only when the ' \
          'blocks are legal), or `{type: "unblock", object: id}` to fix an illegal menace block or free a ' \
          "creature for an attacker that must be blocked if able (CR 509.1c)."
      end

      # "done" is offered only when the blocks are legal (menace, requirements); otherwise blocks can be removed.
      def self.options(engine, _pending)
        blocks = engine.block_options.map { |id, attacker| { type: "block", object: id, attacker: attacker } }
        unblock = engine.menace_violations.flat_map { engine.blockers_of(it) } + engine.requirement_unblocks
        removals = unblock.uniq.map { { type: "unblock", object: it } }
        (engine.blocks_legal? ? [DONE] : []) + blocks + removals
      end

      def self.submit(engine, _pending, option)
        case option[:type]
        when "done" then engine.finish_blockers!
        when "unblock" then engine.remove_blocker!(option[:object])
        else engine.declare_blocker!(option[:object], option[:attacker])
        end
      end
    end
    register("declare_blockers", DeclareBlockers)

    # CR 510.1c: assign one point of a multiply-blocked attacker's damage to one of its blockers.
    class AssignDamage < Base
      def self.doc
        'Assign one point of combat damage of `attacker`: `{type: "assign", object: blocker_id}`. ' \
          "`remaining` points are left."
      end

      def self.options(engine, pending)
        engine.assignment_targets(pending["attacker"]).map { { type: "assign", object: it } }
      end

      def self.submit(engine, pending, option) = engine.assign_damage!(pending["attacker"], option[:object])
    end
    register("assign_damage", AssignDamage)
  end
end
